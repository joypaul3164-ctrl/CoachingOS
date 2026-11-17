-- CoachingOS multi-institution SaaS foundation
-- Phase 1: role-aware membership reads, platform administration and subscription catalog.
-- Safe to rerun. Does not delete or rewrite existing institute records.
-- Run in Supabase SQL Editor after the existing CoachingOS schema.

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.subscription_plans (
  id text primary key,
  name text not null,
  monthly_price numeric(12,2) not null default 0 check (monthly_price >= 0),
  max_branches integer,
  max_members integer,
  max_records integer,
  features jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.subscription_plans
  (id, name, monthly_price, max_branches, max_members, max_records, features)
values
  ('free', 'Free', 0, 1, 3, 500, '{"reports":true,"exports":false}'::jsonb),
  ('basic', 'Basic', 499, 3, 10, 5000, '{"reports":true,"exports":true}'::jsonb),
  ('pro', 'Pro', 1499, 10, 50, 50000, '{"reports":true,"exports":true,"advanced_analytics":true}'::jsonb),
  ('enterprise', 'Enterprise', 4999, null, null, null, '{"reports":true,"exports":true,"advanced_analytics":true,"priority_support":true}'::jsonb)
on conflict (id) do nothing;

create table if not exists public.institute_subscriptions (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null unique references public.institutes(id) on delete cascade,
  plan_id text not null references public.subscription_plans(id),
  status text not null default 'trial'
    check (status in ('trial','active','past_due','cancelled','suspended')),
  billing_cycle text not null default 'monthly'
    check (billing_cycle in ('monthly','yearly')),
  current_period_start timestamptz,
  current_period_end timestamptz,
  trial_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.institute_invitations (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes(id) on delete cascade,
  email text not null,
  role text not null
    check (role in ('admin','manager','teacher','accountant','receptionist','staff')),
  token_hash text not null unique,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists institute_invitations_institute_idx
  on public.institute_invitations(institute_id, created_at desc);
create index if not exists institute_subscriptions_plan_status_idx
  on public.institute_subscriptions(plan_id, status);

create or replace function public.is_coachingos_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.platform_admins p
    where p.user_id = (select auth.uid())
  );
$$;

create or replace function public.has_coachingos_institute_role(
  _institute_id uuid,
  _roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.institute_members m
    where m.institute_id = _institute_id
      and m.user_id = (select auth.uid())
      and m.role = any(_roles)
  );
$$;

create or replace function public.can_view_coachingos_subscription(_institute_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    public.is_coachingos_super_admin()
    or exists (
      select 1 from public.institutes i
      where i.id = _institute_id and i.owner_id = (select auth.uid())
    )
    or public.has_coachingos_institute_role(
      _institute_id, array['owner','admin']::text[]
    );
$$;

revoke all on function public.is_coachingos_super_admin() from public;
revoke all on function public.has_coachingos_institute_role(uuid,text[]) from public;
revoke all on function public.can_view_coachingos_subscription(uuid) from public;
grant execute on function public.is_coachingos_super_admin() to authenticated;
grant execute on function public.has_coachingos_institute_role(uuid,text[]) to authenticated;
grant execute on function public.can_view_coachingos_subscription(uuid) to authenticated;

alter table public.platform_admins enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.institute_subscriptions enable row level security;
alter table public.institute_invitations enable row level security;

drop policy if exists "Users can view own platform admin entry" on public.platform_admins;
create policy "Users can view own platform admin entry"
on public.platform_admins for select
to authenticated
using (user_id = (select auth.uid()) or public.is_coachingos_super_admin());

drop policy if exists "Authenticated users can view active plans" on public.subscription_plans;
create policy "Authenticated users can view active plans"
on public.subscription_plans for select
to authenticated
using (is_active = true or public.is_coachingos_super_admin());

drop policy if exists "Institute owners and admins can view subscription" on public.institute_subscriptions;
create policy "Institute owners and admins can view subscription"
on public.institute_subscriptions for select
to authenticated
using (public.can_view_coachingos_subscription(institute_id));

drop policy if exists "Super admins can manage subscriptions" on public.institute_subscriptions;
create policy "Super admins can manage subscriptions"
on public.institute_subscriptions for all
to authenticated
using (public.is_coachingos_super_admin())
with check (public.is_coachingos_super_admin());

-- Members can see their own membership. Owners/admins/managers can view
-- the member roster for their own institute; no cross-institute access.
drop policy if exists "Users can view their own institute memberships" on public.institute_members;
drop policy if exists "Institute managers can view institute memberships" on public.institute_members;
create policy "Institute managers can view institute memberships"
on public.institute_members for select
to authenticated
using (
  user_id = (select auth.uid())
  or public.has_coachingos_institute_role(
    institute_id, array['owner','admin','manager']::text[]
  )
);

-- Keep invitation creation/acceptance server-side until a trusted Edge Function
-- validates invite tokens. Browser clients receive no invitation-table access.
revoke all on public.institute_invitations from anon, authenticated;
grant all on public.institute_invitations to service_role;

-- Platform admin membership must be provisioned manually by the project owner
-- in the SQL Editor after verifying the intended user's auth.users UUID.
revoke all on public.platform_admins from anon, authenticated;
grant select on public.platform_admins to authenticated;
revoke insert, update, delete on public.subscription_plans from anon, authenticated;
grant select on public.subscription_plans to authenticated;
revoke insert, update, delete on public.institute_subscriptions from anon, authenticated;
grant select on public.institute_subscriptions to authenticated;

grant usage on schema public to authenticated;
