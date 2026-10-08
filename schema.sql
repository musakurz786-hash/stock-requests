-- Stock Requests — Supabase schema
-- Run this once in the Supabase SQL Editor. Lives in its own "stock_requests" schema so it can
-- safely share the WHIP project's database (free-tier plans cap the number of projects per org,
-- and WHIP's project already has its own "products"/"orders" tables in "public" — a separate
-- schema keeps this app's tables fully isolated from those, same as if it were its own project).
--
-- Models the marketing team's actual process (not a budget/approval flow): a requester submits a
-- request for one or more products; logistics later pulls the stock and records a Transfer Number
-- once it's physically moved; some requests are loans that get reconciled later (recon date,
-- whether it was received back, an outcome note, and a return transfer number). Many requests are
-- simply consumed and never reconciled — that's normal, not an error state.

create schema if not exists stock_requests;

create table stock_requests.requesters (
  id bigint generated always as identity primary key,
  name text not null unique,
  department text
);

create table stock_requests.stores (
  id bigint generated always as identity primary key,
  name text not null unique
);

create table stock_requests.products (
  sku text primary key,
  product text not null,
  category text,
  subcat text,
  available numeric, -- HQ stock on hand from the Cin7 stock report; null = never imported (unknown, still requestable)
  updated_at timestamptz default now()
);

-- One row per product line. Items submitted together in the same request share a batch_id so the
-- UI can group them back into a single request card.
create table stock_requests.requests (
  id bigint generated always as identity primary key,
  batch_id uuid not null,
  created_at timestamptz default now(),
  request_date date not null default current_date,
  requester_name text not null, -- always a person's name, whether an HQ/marketing request or a
                                 -- store one (store_name below says which store, if any)
  department text,
  request_type text not null default 'hq' check (request_type in ('hq','store')),
  store_name text, -- set only when request_type='store'; free text, not FK'd to stores.name,
                    -- same reasoning as requester_name/product: history must survive a store
                    -- being renamed or removed from the stores list later
  reason text not null,
  expected_return_date date, -- "Date stock will be returned" on the request form; null if not a loan
  sku text, -- intentionally no FK to products: history must survive a product being discontinued
  product text not null,
  qty int not null default 1,
  transfer_number text,   -- filled in by logistics once the stock is physically moved out
  date_completed date,    -- when logistics completed that outbound transfer
  recon_date date,
  received boolean,       -- null = not yet reconciled, not "no"
  feedback text,          -- free text outcome, e.g. "Returned to Stock" / "Transferred to rejects" / "Reject"
  return_transfer_number text,
  notes text,
  deleted_at timestamptz -- soft delete: "Delete" in the app sets this instead of removing the
                         -- row, so a mistaken delete is recoverable. Every read query filters
                         -- deleted_at=is.null. Requesters/products stay hard-delete (low-stakes
                         -- reference data, and requesters' unique name constraint would fight a
                         -- soft-deleted-then-re-added row).
);

create index requests_batch_idx on stock_requests.requests(batch_id);
create index requests_requester_idx on stock_requests.requests(requester_name);
create index requests_transfer_idx on stock_requests.requests(transfer_number);
create index products_product_idx on stock_requests.products using gin (to_tsvector('english', product));

alter table stock_requests.requesters enable row level security;
alter table stock_requests.stores enable row level security;
alter table stock_requests.products enable row level security;
alter table stock_requests.requests enable row level security;

-- Internal tool, no login system — same anon-key model as WHIP and staff-allowance. Not suitable
-- if this were ever made public-facing.
create policy "anon read requesters" on stock_requests.requesters for select using (true);
create policy "anon insert requesters" on stock_requests.requesters for insert with check (true);
create policy "anon update requesters" on stock_requests.requesters for update using (true) with check (true);
create policy "anon delete requesters" on stock_requests.requesters for delete using (true);
create policy "anon read stores" on stock_requests.stores for select using (true);
create policy "anon insert stores" on stock_requests.stores for insert with check (true);
create policy "anon update stores" on stock_requests.stores for update using (true) with check (true);
create policy "anon delete stores" on stock_requests.stores for delete using (true);
create policy "anon read products" on stock_requests.products for select using (true);
create policy "anon write products" on stock_requests.products for all using (true) with check (true);
create policy "anon read requests" on stock_requests.requests for select using (true);
create policy "anon insert requests" on stock_requests.requests for insert with check (true);
create policy "anon update requests" on stock_requests.requests for update using (true) with check (true);
create policy "anon delete requests" on stock_requests.requests for delete using (true);

-- PostgREST only serves schemas it's been granted access to.
grant usage on schema stock_requests to anon, authenticated;
grant all on all tables in schema stock_requests to anon, authenticated;
grant all on all sequences in schema stock_requests to anon, authenticated;

-- One-time manual step (can't be done from SQL): in the Supabase dashboard, go to
-- Project Settings -> Data API -> "Exposed schemas" and add "stock_requests" to the list
-- (it starts as just "public"). Without this, PostgREST returns 404 for every request below.

-- ============================================================================
-- MIGRATION (2026-08): adds soft-delete to an already-running installation.
-- Safe to run even though the table above already has the column in fresh installs —
-- IF NOT EXISTS makes this a no-op there.
-- ============================================================================
alter table stock_requests.requests add column if not exists deleted_at timestamptz;

-- ============================================================================
-- MIGRATION (2026-09): adds store requests alongside the existing HQ/marketing ones.
-- ============================================================================
create table if not exists stock_requests.stores (
  id bigint generated always as identity primary key,
  name text not null unique
);
alter table stock_requests.stores enable row level security;
do $$ begin
  create policy "anon read stores" on stock_requests.stores for select using (true);
  create policy "anon insert stores" on stock_requests.stores for insert with check (true);
  create policy "anon update stores" on stock_requests.stores for update using (true) with check (true);
  create policy "anon delete stores" on stock_requests.stores for delete using (true);
exception when duplicate_object then null; -- re-running this migration block is then a no-op
end $$;
grant all on stock_requests.stores to anon, authenticated;
grant all on all sequences in schema stock_requests to anon, authenticated; -- covers the new stores_id_seq

alter table stock_requests.requests add column if not exists request_type text not null default 'hq';
alter table stock_requests.requests add column if not exists store_name text;
do $$ begin
  alter table stock_requests.requests add constraint requests_request_type_check
    check (request_type in ('hq','store'));
exception when duplicate_object then null; -- re-running this migration block is then a no-op
end $$;

-- ============================================================================
-- MIGRATION (2026-10): HQ stock levels, same model as the Staff Allowance app. Filled by the
-- admin "Import Stock Report" (HQ location rows only); null means the SKU hasn't had stock
-- imported yet and stays requestable, 0 means out of stock and blocks it on the request form.
-- ============================================================================
alter table stock_requests.products add column if not exists available numeric;

-- ============================================================================
-- MIGRATION (2026-10): automatic HQ stock sync from Shopify (FOM Online), same model as Staff
-- Allowance. Edge function: supabase/functions/sr-shopify-stock (deployed with verify_jwt off; it
-- checks the x-sync-secret header against Vault instead). Uses the project's existing read-only
-- Shopify secrets (SHOPIFY_CLIENT_ID / SHOPIFY_CLIENT_SECRET). Touches only stock_requests.* —
-- the order fulfilment app's ful_* tables, functions and cron jobs in this project are separate.
-- ============================================================================
create table if not exists stock_requests.stock_sync_log (
  id bigint generated always as identity primary key,
  run_at timestamptz default now(),
  shopify_rows integer,
  updated_count integer,
  status text,
  detail text
);
alter table stock_requests.stock_sync_log enable row level security;
do $$ begin
  create policy "anon read stock_sync_log" on stock_requests.stock_sync_log for select using (true);
exception when duplicate_object then null; end $$;
grant select on stock_requests.stock_sync_log to anon, authenticated;
grant all on stock_requests.stock_sync_log to service_role;

-- Writes Shopify HQ "available" onto existing catalog SKUs only (never adds products).
create or replace function stock_requests.apply_shopify_stock(items jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  update stock_requests.products p
     set available = s.available,
         updated_at = now()
    from (
      select x->>'sku' as sku, max((x->>'available')::numeric) as available
        from jsonb_array_elements(items) x
       where coalesce(x->>'sku','') <> ''
       group by x->>'sku'
    ) s
   where p.sku = s.sku
     and p.available is distinct from s.available;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function stock_requests.apply_shopify_stock(jsonb) from public, anon, authenticated;
grant execute on function stock_requests.apply_shopify_stock(jsonb) to service_role;

-- Shared secret between the cron job and the edge function, so only the schedule can trigger a sync.
do $$ begin
  if not exists (select 1 from vault.secrets where name = 'sr_stock_sync_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'sr_stock_sync_secret', 'Stock Requests Shopify stock sync');
  end if;
end $$;

create or replace function stock_requests.stock_sync_secret()
returns text language sql security definer set search_path = ''
as $$ select decrypted_secret from vault.decrypted_secrets where name = 'sr_stock_sync_secret' $$;
revoke all on function stock_requests.stock_sync_secret() from public, anon, authenticated;
grant execute on function stock_requests.stock_sync_secret() to service_role;

create or replace function stock_requests.trigger_shopify_stock_sync()
returns bigint language plpgsql security definer set search_path = ''
as $$
declare req_id bigint;
begin
  select net.http_post(
    url := 'https://wqsibegaczuhgrcjwitl.supabase.co/functions/v1/sr-shopify-stock',
    headers := jsonb_build_object('Content-Type','application/json',
                                  'x-sync-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'sr_stock_sync_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  ) into req_id;
  return req_id;
end $$;
revoke all on function stock_requests.trigger_shopify_stock_sync() from public, anon, authenticated;

grant usage on schema stock_requests to service_role;
grant select, update on stock_requests.products to service_role;

-- Every 15 min, staggered off Staff Allowance's :00/:15/:30/:45 sync (they share one Shopify app's rate limit).
-- To stop it: select cron.unschedule('sr-shopify-stock');
select cron.schedule('sr-shopify-stock', '7,22,37,52 * * * *', 'select stock_requests.trigger_shopify_stock_sync()');
