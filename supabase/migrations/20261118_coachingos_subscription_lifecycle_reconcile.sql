create or replace function public.admin_reconcile_coachingos_subscription_status()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  changed_count integer := 0;
begin
  if not exists (
    select 1
    from public.platform_admins p
    where p.user_id = (select auth.uid())
  ) then
    raise exception 'Platform Super Admin access required'
      using errcode = '42501';
  end if;

  update public.institute_subscriptions s
  set status = 'past_due',
      updated_at = now()
  where
    (s.status = 'trial'
      and coalesce(s.trial_ends_at, s.current_period_end) is not null
      and coalesce(s.trial_ends_at, s.current_period_end) <= now())
    or
    (s.status = 'active'
      and s.current_period_end is not null
      and s.current_period_end <= now());

  get diagnostics changed_count = row_count;
  return changed_count;
end;
$function$;

revoke all on function public.admin_reconcile_coachingos_subscription_status() from public, anon, service_role;
grant execute on function public.admin_reconcile_coachingos_subscription_status() to authenticated;
