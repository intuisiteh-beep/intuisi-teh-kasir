-- INTUISI.TEH ONLINE KASIR — Supabase setup
-- Jalankan seluruh file ini di Supabase SQL Editor.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Kasir',
  role text not null default 'kasir' check (role in ('admin','kasir')),
  created_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  local_id text,
  buyer_name text not null default 'Pelanggan',
  channel text not null default 'Outlet',
  payment_method text not null check (payment_method in ('Cash','QRIS')),
  total integer not null default 0 check (total >= 0),
  paid integer not null default 0 check (paid >= 0),
  change_amount integer not null default 0 check (change_amount >= 0),
  note text,
  cashier_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.sale_items (
  id bigint generated always as identity primary key,
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_name text not null,
  category text not null,
  size text not null,
  qty integer not null check (qty > 0),
  price integer not null check (price >= 0),
  subtotal integer generated always as (qty * price) stored
);

create index if not exists sales_created_at_idx on public.sales(created_at desc);
create index if not exists sales_cashier_id_idx on public.sales(cashier_id);
create index if not exists sale_items_sale_id_idx on public.sale_items(sale_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(coalesce(new.email,''),'@',1), 'Kasir'),
    'kasir'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

alter table public.profiles enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;

revoke all on table public.profiles from anon;
revoke all on table public.sales from anon;
revoke all on table public.sale_items from anon;

grant select on public.profiles to authenticated;
grant select, insert on public.sales to authenticated;
grant select, insert on public.sale_items to authenticated;
grant update, delete on public.sales to authenticated;
grant delete on public.sale_items to authenticated;

drop policy if exists profiles_read_authenticated on public.profiles;
create policy profiles_read_authenticated on public.profiles
for select to authenticated using (true);

drop policy if exists sales_read_authenticated on public.sales;
create policy sales_read_authenticated on public.sales
for select to authenticated using (true);

drop policy if exists sales_insert_authenticated on public.sales;
create policy sales_insert_authenticated on public.sales
for insert to authenticated
with check (cashier_id = auth.uid());

drop policy if exists sales_update_admin on public.sales;
create policy sales_update_admin on public.sales
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists sales_delete_admin on public.sales;
create policy sales_delete_admin on public.sales
for delete to authenticated
using (public.is_admin());

drop policy if exists sale_items_read_authenticated on public.sale_items;
create policy sale_items_read_authenticated on public.sale_items
for select to authenticated using (true);

drop policy if exists sale_items_insert_authenticated on public.sale_items;
create policy sale_items_insert_authenticated on public.sale_items
for insert to authenticated
with check (exists (
  select 1 from public.sales s
  where s.id = sale_items.sale_id
  and s.cashier_id = auth.uid()
));

drop policy if exists sale_items_delete_admin on public.sale_items;
create policy sale_items_delete_admin on public.sale_items
for delete to authenticated
using (public.is_admin());

-- Setelah membuat akun admin di Authentication > Users,
-- jalankan contoh berikut dengan UUID user admin:
-- update public.profiles set role='admin', full_name='Admin Intuisi.teh'
-- where id='GANTI-DENGAN-UUID-USER-ADMIN';
