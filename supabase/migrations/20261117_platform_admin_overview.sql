-- CoachingOS Platform Super Admin overview
-- Safe to rerun. Read-only reporting; no institute data is modified.
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
      'other_subscriptions', (select count(*) from public.institute_subscriptions where status not in ('active','trial'))
    ),
    'institutes', coalesce((
      select jsonb_agg(item order by created_at desc)
      from (
        select jsonb_build_object(
          'id', i.id,
          'name', i.name,
          'institute_type', i.institute_type,
          'created_at', i.created_at,
          'plan_name', p.name,
          'subscription_status', s.status
        ) as item, i.created_at
        from public.institutes i
        left join public.institute_subscriptions s on s.institute_id = i.id
        left join public.subscription_plans p on p.id = s.plan_id
        order by i.created_at desc
        limit 100
      ) recent
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

revoke all on function public.get_coachingos_platform_overview() from public;
grant execute on function public.get_coachingos_platform_overview() to authenticated;
