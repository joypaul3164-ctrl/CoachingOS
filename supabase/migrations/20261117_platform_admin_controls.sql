-- CoachingOS Platform Super Admin controls
-- Adds institute lifecycle status and secure Super Admin RPCs.
-- Safe to rerun; existing institutes remain active by default.

alter table public.institutes
  add column if not exists status text not null default 'active';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'institutes_status_check'
      and conrelid = 'public.institutes'::regclass
  ) then
    alter table public.institutes
      add constraint institutes_status_check
      check (status in ('pending','active','suspended'));
  end if;
end $$;

create or replace function public.admin_set_coachingos_institute_status(
  _institute_id uuid,
  _status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.platform_admins p
    where p.user_id = (select auth.uid())
  ) then
    raise exception 'Platform Super Admin access required'
      using errcode = '42501';
  end if;

  if _status not in ('pending','active','suspended') then
    raise exception 'Invalid institute status';
  end if;

  update public.institutes
  set status = _status
  where id = _institute_id;

  if not found then
    raise exception 'Institute not found';
  end if;
  return true;
end;
$$;

create or replace function public.admin_upsert_coachingos_plan(
  _id text,
  _name text,
  _monthly_price numeric,
  _is_active boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.platform_admins p
    where p.user_id = (select auth.uid())
  ) then
    raise exception 'Platform Super Admin access required'
      using errcode = '42501';
  end if;

  if coalesce(length(trim(_id)),0) < 2
     or coalesce(length(trim(_name)),0) < 2
     or _monthly_price is null
     or _monthly_price < 0 then
    raise exception 'Provide a valid plan ID, name and non-negative price';
  end if;

  insert into public.subscription_plans(id,name,monthly_price,is_active)
  values (lower(trim(_id)),trim(_name),_monthly_price,coalesce(_is_active,true))
  on conflict (id) do update
    set name = excluded.name,
        monthly_price = excluded.monthly_price,
        is_active = excluded.is_active;

  return true;
end;
$$;

revoke all on function public.admin_set_coachingos_institute_status(uuid,text) from public;
revoke all on function public.admin_upsert_coachingos_plan(text,text,numeric,boolean) from public;
grant execute on function public.admin_set_coachingos_institute_status(uuid,text) to authenticated;
grant execute on function public.admin_upsert_coachingos_plan(text,text,numeric,boolean) to authenticated;

create or replace function public.get_coachingos_platform_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not exists (
    select 1 from public.platform_admins p
    where p.user_id = (select auth.uid())
  ) then
    raise exception 'Platform Super Admin access required'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'totals', jsonb_build_object(
      'institutes', (select count(*) from public.institutes),
      'active_subscriptions', (select count(*) from public.institute_subscriptions where status = 'active'),
      'trial_subscriptions', (select count(*) from public.institute_subscriptions where status = 'trial'),
      'other_subscriptions', (select count(*) from public.institute_subscriptions where status not in ('active','trial')),
      'suspended_institutes', (select count(*) from public.institutes where status = 'suspended'),
      'pending_institutes', (select count(*) from public.institutes where status = 'pending')
    ),
    'institutes', coalesce((
      select jsonb_agg(item order by created_at desc)
      from (
        select jsonb_build_object(
          'id', i.id,
          'name', i.name,
          'institute_type', i.institute_type,
          'status', i.status,
          'created_at', i.created_at,
          'plan_name', p.name,
          'subscription_status', s.status
        ) as item, i.created_at
        from public.institutes i
        left join public.institute_subscriptions s on s.institute_id = i.id
        left join public.subscription_plans p on p.id = s.plan_id
        order by i.created_at desc
        limit 500
      ) recent
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_coachingos_platform_overview() from public;
grant execute on function public.get_coachingos_platform_overview() to authenticated;
