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


-- Enforce lifecycle status at the data boundary.
-- Suspended/pending institutes retain their data, but ordinary members cannot
-- read or modify institute records until a Platform Super Admin reactivates them.
create or replace function public.guard_coachingos_institute_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status
     and not exists (
       select 1 from public.platform_admins p
       where p.user_id = (select auth.uid())
     ) then
    raise exception 'Only Platform Super Admin can change institute status'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists coachingos_guard_institute_status on public.institutes;
create trigger coachingos_guard_institute_status
before update of status on public.institutes
for each row execute function public.guard_coachingos_institute_status();

drop policy if exists "Institute members can read institute records" on public.coachingos_records;
create policy "Active institute members can read institute records"
on public.coachingos_records for select
to authenticated
using (
  exists (
    select 1
    from public.institute_members m
    join public.institutes i on i.id = m.institute_id
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and i.status = 'active'
  )
);

drop policy if exists "Institute admins can add records" on public.coachingos_records;
create policy "Active institute admins can add records"
on public.coachingos_records for insert
to authenticated
with check (
  exists (
    select 1
    from public.institute_members m
    join public.institutes i on i.id = m.institute_id
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
      and i.status = 'active'
  )
);

drop policy if exists "Institute admins can update records" on public.coachingos_records;
create policy "Active institute admins can update records"
on public.coachingos_records for update
to authenticated
using (
  exists (
    select 1
    from public.institute_members m
    join public.institutes i on i.id = m.institute_id
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
      and i.status = 'active'
  )
)
with check (
  exists (
    select 1
    from public.institute_members m
    join public.institutes i on i.id = m.institute_id
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
      and i.status = 'active'
  )
);

drop policy if exists "Institute admins can delete records" on public.coachingos_records;
create policy "Active institute admins can delete records"
on public.coachingos_records for delete
to authenticated
using (
  exists (
    select 1
    from public.institute_members m
    join public.institutes i on i.id = m.institute_id
    where m.institute_id = coachingos_records.institute_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
      and i.status = 'active'
  )
);

revoke all on function public.guard_coachingos_institute_status() from public;
