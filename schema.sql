-- Stock Requests — Supabase schema
-- Run this once in the Supabase SQL Editor on a new project (separate from WHIP / staff-allowance).
--
-- Models the marketing team's actual process (not a budget/approval flow): a requester submits a
-- request for one or more products; logistics later pulls the stock and records a Transfer Number
-- once it's physically moved; some requests are loans that get reconciled later (recon date,
-- whether it was received back, an outcome note, and a return transfer number). Many requests are
-- simply consumed and never reconciled — that's normal, not an error state.

create table requesters (
  id bigint generated always as identity primary key,
  name text not null unique,
  department text
);

create table products (
  sku text primary key,
  product text not null,
  category text,
  subcat text,
  updated_at timestamptz default now()
);

-- One row per product line. Items submitted together in the same request share a batch_id so the
-- UI can group them back into a single request card.
create table requests (
  id bigint generated always as identity primary key,
  batch_id uuid not null,
  created_at timestamptz default now(),
  request_date date not null default current_date,
  requester_name text not null,
  department text,
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
  notes text
);

create index requests_batch_idx on requests(batch_id);
create index requests_requester_idx on requests(requester_name);
create index requests_transfer_idx on requests(transfer_number);
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
