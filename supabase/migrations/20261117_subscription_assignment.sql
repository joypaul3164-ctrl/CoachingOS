-- CoachingOS subscription assignment and trial controls
-- Safe to rerun. Existing subscriptions are preserved until an admin assigns a new one.

create or replace function public.admin_assign_coachingos_subscription(
  _institute_id uuid,
  _plan_id text,
  _status text,
  _trial_days integer default 14
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  period_start timestamptz := now();
  period_end timestamptz;
  trial_end timestamptz;
begin
  if not exists (
    select 1 from public.platform_admins p
    where p.user_id = (select auth.uid())
  ) then
    raise exception 'Platform Super Admin access required'
      using errcode = '42501';
  end if;

  if _status not in ('trial','active','past_due','cancelled','suspended') then
    raise exception 'Invalid subscription status';
  end if;
  if _trial_days is null or _trial_days < 1 or _trial_days > 365 then
    raise exception 'Trial days must be between 1 and 365';
  end if;
  if not exists (select 1 from public.institutes i where i.id = _institute_id) then
    raise exception 'Institute not found';
  end if;
  if not exists (
    select 1 from public.subscription_plans p
    where p.id = lower(trim(_plan_id)) and p.is_active = true
  ) then
    raise exception 'Choose an active subscription plan';
  end if;

  if _status = 'trial' then
    trial_end := period_start + make_interval(days => _trial_days);
    period_end := trial_end;
  elsif _status = 'active' then
    period_end := period_start + interval '1 month';
    trial_end := null;
  else
    period_end := null;
    trial_end := null;
  end if;

  insert into public.institute_subscriptions(
    institute_id, plan_id, status, billing_cycle,
    current_period_start, current_period_end, trial_ends_at, updated_at
  )
  values (
    _institute_id, lower(trim(_plan_id)), _status, 'monthly',
    case when _status in ('trial','active') then period_start else null end,
    period_end, trial_end, now()
  )
  on conflict (institute_id) do update
    set plan_id = excluded.plan_id,
        status = excluded.status,
        billing_cycle = excluded.billing_cycle,
        current_period_start = excluded.current_period_start,
        current_period_end = excluded.current_period_end,
        trial_ends_at = excluded.trial_ends_at,
        updated_at = now();

  return true;
end;
$$;

revoke all on function public.admin_assign_coachingos_subscription(uuid,text,text,integer) from public;
grant execute on function public.admin_assign_coachingos_subscription(uuid,text,text,integer) to authenticated;
