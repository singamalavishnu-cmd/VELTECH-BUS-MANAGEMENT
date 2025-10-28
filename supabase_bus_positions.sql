-- Supabase SQL: bus_positions table, indexes, RLS policies, and realtime notes
-- Run this in Supabase SQL Editor

-- 1) Table
create table if not exists public.bus_positions (
  bus_no text primary key,
  lat double precision not null,
  lng double precision not null,
  speed double precision,
  heading double precision,
  updated_at timestamptz not null default now()
);

-- 2) Helpful indexes
create index if not exists idx_bus_positions_updated_at on public.bus_positions(updated_at desc);
create index if not exists idx_bus_positions_geo on public.bus_positions(lat, lng);

-- 3) Enable Row Level Security (RLS)
alter table public.bus_positions enable row level security;

-- 4) Policies (clean re-create; NO IF NOT EXISTS). Run as-is.
-- Drop existing policies if present (ignore errors if they don't exist)
drop policy if exists bus_positions_read on public.bus_positions;
drop policy if exists bus_positions_insert on public.bus_positions;
drop policy if exists bus_positions_update on public.bus_positions;

-- Read policy (students/admin): allow read for both anon and authenticated
create policy bus_positions_read
on public.bus_positions
for select
to anon, authenticated
using (true);

-- Write policies (drivers). For quick demo with driver.html (anon key), allow anon & authenticated.
-- Tighten later by requiring authenticated and/or per-driver constraints.
create policy bus_positions_insert
on public.bus_positions
for insert
to anon, authenticated
with check (true);

create policy bus_positions_update
on public.bus_positions
for update
to anon, authenticated
using (true)
with check (true);

-- 6) Realtime setup (do this in Dashboard UI):
-- Go to Database → Replication (Realtime) → Enable for table public.bus_positions
-- Or via SQL (if extension is available):
-- alter publication supabase_realtime add table public.bus_positions;
