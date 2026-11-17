-- CoachingOS initial Supabase schema
-- Run once in Supabase Dashboard -> SQL Editor -> New query.
-- Safe to run again: tables, indexes, policies and helper function are guarded.
-- This migration does not delete existing data.

create extension if not exists pgcrypto;

create table if not exists public.institutes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.institute_members (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner'
    check (role in ('owner', 'admin', 'manager', 'teacher', 'accountant', 'receptionist', 'staff')),
  created_at timestamptz not null default now(),
  unique (institute_id, user_id)
);

create table if not exists public.coachingos_records (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes(id) on delete cascade,
  record_type text not null,
  record_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists institute_members_user_id_idx
  on public.institute_members(user_id);
create index if not exists coachingos_records_institute_id_idx
  on public.coachingos_records(institute_id);
create index if not exists coachingos_records_type_idx
  on public.coachingos_records(institute_id, record_type);

-- A narrowly-scoped SECURITY DEFINER helper avoids RLS policy recursion
-- when the first account creates its own institute membership.
create or replace function public.is_coachingos_institute_owner(_institute_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.institutes i
    where i.id = _institute_id
      and i.owner_id = (select auth.uid())
  );
$$;

revoke all on function public.is_coachingos_institute_owner(uuid) from public;
grant execute on function public.is_coachingos_institute_owner(uuid) to authenticated;

alter table public.institutes enable row level security;
alter table public.institute_members enable row level security;
alter table public.coachingos_records enable row level security;

drop policy if exists "CoachingOS members can view their institutes" on public.institutes;
create policy "CoachingOS members can view their institutes"
on public.institutes for select
to authenticated
using (
  owner_id = (select auth.uid())
  or exists (
    select 1
    from public.institute_members m
    where m.institute_id = institutes.id
      and m.user_id = (select auth.uid())
  )
);

drop policy if exists "Users can create an institute they own" on public.institutes;
create policy "Users can create an institute they own"
on public.institutes for insert
to authenticated
with check (owner_id = (select auth.uid()));

drop policy if exists "Owners can update their institutes" on public.institutes;
create policy "Owners can update their institutes"
on public.institutes for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

drop policy if exists "Owners can delete their institutes" on public.institutes;
create policy "Owners can delete their institutes"
on public.institutes for delete
to authenticated
using (owner_id = (select auth.uid()));

drop policy if exists "Users can view their own institute memberships" on public.institute_members;
create policy "Users can view their own institute memberships"
on public.institute_members for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Institute owners can add their own owner membership" on public.institute_members;
create policy "Institute owners can add their own owner membership"
on public.institute_members for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and role = 'owner'
  and public.is_coachingos_institute_owner(institute_id)
);

drop policy if exists "Institute members can read institute records" on public.coachingos_records;
create policy "Institute members can read institute records"
on public.coachingos_records for select
to authenticated
using (
  exists (
    select 1 from public.institute_members m
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
  )
);

drop policy if exists "Institute admins can add records" on public.coachingos_records;
create policy "Institute admins can add records"
on public.coachingos_records for insert
to authenticated
with check (
  exists (
    select 1 from public.institute_members m
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists "Institute admins can update records" on public.coachingos_records;
create policy "Institute admins can update records"
on public.coachingos_records for update
to authenticated
using (
  exists (
    select 1 from public.institute_members m
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
)
with check (
  exists (
    select 1 from public.institute_members m
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists "Institute admins can delete records" on public.coachingos_records;
create policy "Institute admins can delete records"
on public.coachingos_records for delete
to authenticated
using (
  exists (
    select 1 from public.institute_members m
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.institutes to authenticated;
grant select, insert on public.institute_members to authenticated;
grant select, insert, update, delete on public.coachingos_records to authenticated;
