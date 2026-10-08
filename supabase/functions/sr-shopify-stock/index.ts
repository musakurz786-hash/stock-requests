// sr-shopify-stock — ONE-WAY stock sync: Shopify (FOM Online / HQ) -> stock_requests.products.available
// Reads from Shopify only. Never writes to Shopify. Same model as Staff Allowance's shopify-stock function.
// Runs on a schedule via pg_cron (stock_requests.trigger_shopify_stock_sync), staggered to :07/:22/:37/:52
// so it never overlaps Staff Allowance's sync on the shared Shopify app's rate limit.
//
// Lives in the same Supabase project as the order fulfilment app but touches none of its tables or
// functions — only stock_requests.* . Shopify credentials are the project's existing secrets
// (SHOPIFY_CLIENT_ID + SHOPIFY_CLIENT_SECRET, read-only Dev Dashboard app); refuses to run if the
// app ever has a write_ scope.
//
// Auth: deployed with verify_jwt off; only accepts calls carrying header x-sync-secret = Vault secret
// 'sr_stock_sync_secret' (read via stock_requests.stock_sync_secret(), service role only).
// Alerts (optional): RESEND_API_KEY + SR_ALERT_EMAIL -> email on first failure and on recovery.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const STORE = Deno.env.get("SHOPIFY_SHOP") ?? "fom-sa.myshopify.com";
const STATIC_TOKEN = Deno.env.get("SHOPIFY_ADMIN_TOKEN") ?? "";
const CLIENT_ID = Deno.env.get("SHOPIFY_CLIENT_ID") ?? "";
const CLIENT_SECRET = Deno.env.get("SHOPIFY_CLIENT_SECRET") ?? "";
const API_VERSION = "2026-01";
const LOCATION_ID = "gid://shopify/Location/85895971122"; // FOM Online (HQ)
const ENDPOINT = `https://${STORE}/admin/api/${API_VERSION}/graphql.json`;
const RESEND_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const ALERT_EMAIL = Deno.env.get("SR_ALERT_EMAIL") ?? "";
const MAX_PAGES = 150;

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "stock_requests" },
  auth: { persistSession: false },
});
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

let syncSecret: string | null = null;
async function authorised(req: Request): Promise<boolean> {
  const sent = req.headers.get("x-sync-secret");
  if (!sent) return false;
  if (syncSecret === null) {
    const { data } = await db.rpc("stock_sync_secret");
    syncSecret = typeof data === "string" ? data : "";
  }
  return !!syncSecret && sent === syncSecret;
}

let cachedToken: { value: string; expiresAt: number } | null = null;
async function getToken(): Promise<string> {
  if (STATIC_TOKEN) return STATIC_TOKEN;
  if (!CLIENT_ID || !CLIENT_SECRET) throw new Error("Shopify credentials not set (SHOPIFY_CLIENT_ID / SHOPIFY_CLIENT_SECRET)");
  if (cachedToken && Date.now() < cachedToken.expiresAt) return cachedToken.value;
  const res = await fetch(`https://${STORE}/admin/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: new URLSearchParams({ grant_type: "client_credentials", client_id: CLIENT_ID, client_secret: CLIENT_SECRET }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Token request failed (HTTP ${res.status}): ${text.slice(0, 200)}`);
  const body = JSON.parse(text);
  if (!body.access_token) throw new Error(`No access_token in response: ${text.slice(0, 200)}`);
  // Read-only by design: refuse to run at all if the app has been given any write scope.
  const writeScopes = String(body.scope ?? "").split(",").map((s) => s.trim()).filter((s) => s.startsWith("write_"));
  if (writeScopes.length) throw new Error(`Refusing to sync: the Shopify app has write access (${writeScopes.join(", ")}). Remove it so the app is read-only.`);
  const ttl = Number(body.expires_in ?? 3600);
  cachedToken = { value: body.access_token, expiresAt: Date.now() + Math.max(60, ttl - 300) * 1000 };
  return cachedToken.value;
}

const QUERY = `query LocationStock($locationId: ID!, $after: String) {
  location(id: $locationId) {
    inventoryLevels(first: 100, after: $after) {
      pageInfo { hasNextPage endCursor }
      nodes { item { sku } quantities(names: ["available"]) { name quantity } }
    }
  }
}`;

// deno-lint-ignore no-explicit-any
async function shopify(token: string, variables: Record<string, unknown>, attempt = 0): Promise<any> {
  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Shopify-Access-Token": token },
    body: JSON.stringify({ query: QUERY, variables }),
  });
  if (res.status === 401 || res.status === 403) cachedToken = null;
  if (res.status === 429 && attempt < 5) { await sleep(1000 * (attempt + 1)); return shopify(token, variables, attempt + 1); }
  if (!res.ok) throw new Error(`Shopify HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const body = await res.json();
  // deno-lint-ignore no-explicit-any
  if (body.errors?.some((e: any) => e?.extensions?.code === "THROTTLED") && attempt < 5) {
    await sleep(1000 * (attempt + 1));
    return shopify(token, variables, attempt + 1);
  }
  if (body.errors?.length) throw new Error(`Shopify error: ${JSON.stringify(body.errors).slice(0, 200)}`);
  const left = body.extensions?.cost?.throttleStatus?.currentlyAvailable;
  if (typeof left === "number" && left < 200) await sleep(1000);
  return body.data;
}

async function lastStatus(): Promise<string | null> {
  const { data } = await db.from("stock_sync_log").select("status").order("run_at", { ascending: false }).limit(1);
  return data?.[0]?.status ?? null;
}

async function sendEmail(subject: string, text: string) {
  if (!RESEND_KEY || !ALERT_EMAIL) return;
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${RESEND_KEY}` },
      body: JSON.stringify({ from: "Stock Sync <onboarding@resend.dev>", to: [ALERT_EMAIL], subject, text }),
    });
    if (!res.ok) console.error("Alert email failed", res.status, await res.text());
  } catch (e) {
    console.error("Alert email error", e);
  }
}

const sast = () => new Date().toLocaleString("en-ZA", { timeZone: "Africa/Johannesburg" });

Deno.serve(async (req) => {
  if (!(await authorised(req))) return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 });
  const previous = await lastStatus();
  try {
    const token = await getToken();
    const items: { sku: string; available: number }[] = [];
    let after: string | null = null;
    for (let page = 0; page < MAX_PAGES; page++) {
      const data = await shopify(token, { locationId: LOCATION_ID, after });
      if (!data.location) throw new Error("HQ location not found in Shopify");
      for (const n of data.location.inventoryLevels.nodes) {
        const sku = n.item?.sku?.trim();
        if (!sku) continue;
        // deno-lint-ignore no-explicit-any
        const a = n.quantities?.find((q: any) => q.name === "available")?.quantity ?? 0;
        items.push({ sku, available: Math.max(0, a) });
      }
      const pi = data.location.inventoryLevels.pageInfo;
      if (!pi.hasNextPage) break;
      after = pi.endCursor;
    }

    const { data: updated, error } = await db.rpc("apply_shopify_stock", { items });
    if (error) throw new Error(`DB update failed: ${error.message}`);

    await db.from("stock_sync_log").insert({ status: "ok", shopify_rows: items.length, updated_count: updated ?? 0 });
    if (previous === "error") {
      await sendEmail("✅ Stock Requests stock sync recovered",
        `The stock sync is working again (${sast()}).\nRead ${items.length} stock lines from FOM Online, updated ${updated ?? 0} products.`);
    }
    return new Response(JSON.stringify({ ok: true, shopify_rows: items.length, updated: updated ?? 0 }), { status: 200 });
  } catch (err) {
    const msg = (err as Error).message.slice(0, 500);
    console.error(err);
    await db.from("stock_sync_log").insert({ status: "error", detail: msg });
    if (previous !== "error") {
      await sendEmail("⚠️ Stock Requests stock sync failed",
        `The stock sync from Shopify (FOM Online) failed at ${sast()}.\n\nError: ${msg}\n\nStock in Stock Requests is not updating until this is fixed (the manual Import Stock Report still works). You'll get one more email when it recovers.`);
    }
    return new Response(JSON.stringify({ ok: false, error: msg }), { status: 502 });
  }
});
