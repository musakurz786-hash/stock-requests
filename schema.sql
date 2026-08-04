-- Stock Requests — Supabase schema
-- Run this once in the Supabase SQL Editor on a new project (separate from WHIP / staff-allowance).

create table requesters (
  id bigint generated always as identity primary key,
  name text not null unique,
  email text,
  department text
);

create table products (
  sku text primary key,
  product text not null,
  category text,
  subcat text,
  available numeric default 0,
  updated_at timestamptz default now()
);

-- One row per line item. Items submitted together in the same cart share a batch_id so the UI
-- can group them back into a single "request" card, but each line has its own approve/fulfil status
-- since an approver may want to knock back one item without blocking the rest.
create table requests (
  id bigint generated always as identity primary key,
  batch_id uuid not null,
  created_at timestamptz default now(),
  requester_name text not null references requesters(name),
  department text,
  purpose text not null, -- 'photoshoot' | 'gifting_pr' | 'event' | 'social_media' | 'in_store_display' | 'other'
  note text,
  sku text, -- intentionally no FK to products: history must survive a product being discontinued
  product text not null,
  qty_requested int not null default 1,
  qty_approved int,
  status text not null default 'pending' check (status in ('pending','approved','rejected','fulfilled')),
  approved_by text,
  approved_at timestamptz,
  rejected_reason text,
  fulfilled_at timestamptz
);

create index requests_batch_idx on requests(batch_id);
create index requests_requester_idx on requests(requester_name);
create index requests_status_idx on requests(status);
create index products_product_idx on products using gin (to_tsvector('english', product));

alter table requesters enable row level security;
alter table products enable row level security;
alter table requests enable row level security;

-- Internal tool, no login system — same anon-key model as WHIP and staff-allowance. Not suitable
-- if this were ever made public-facing.
create policy "anon read requesters" on requesters for select using (true);
create policy "anon insert requesters" on requesters for insert with check (true);
create policy "anon update requesters" on requesters for update using (true) with check (true);
create policy "anon delete requesters" on requesters for delete using (true);
create policy "anon read products" on products for select using (true);
create policy "anon write products" on products for all using (true) with check (true);
create policy "anon read requests" on requests for select using (true);
create policy "anon insert requests" on requests for insert with check (true);
create policy "anon update requests" on requests for update using (true) with check (true);
create policy "anon delete requests" on requests for delete using (true);
