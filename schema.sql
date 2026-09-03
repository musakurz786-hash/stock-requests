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
