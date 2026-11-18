create or replace function public.coachingos_subscription_write_allowed(_institute_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    public.is_coachingos_super_admin()
    or not exists (
      select 1 from public.institute_subscriptions s
      where s.institute_id = _institute_id
    )
    or exists (
      select 1 from public.institute_subscriptions s
      where s.institute_id = _institute_id
        and (
          (s.status = 'active' and
            (s.current_period_end is null or s.current_period_end > now()))
          or
          (s.status = 'trial' and
            coalesce(s.trial_ends_at, s.current_period_end) > now())
        )
    );
$$;

create or replace function public.can_manage_coachingos_records(_institute_id uuid, _record_type text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.coachingos_subscription_write_allowed(_institute_id)
    and exists (
      select 1
      from public.institute_members m
      join public.institutes i on i.id = m.institute_id
      where m.institute_id = _institute_id
        and m.user_id = (select auth.uid())
        and i.status = 'active'
        and (
          m.role in ('owner','admin','manager')
          or (m.role = 'teacher' and _record_type in ('batches','routine','attendance','exams'))
          or (m.role = 'accountant' and _record_type in ('fees','expenses','payroll'))
          or (m.role = 'receptionist' and _record_type in ('students','attendance','fees'))
        )
    );
$$;

create or replace function public.enforce_coachingos_subscription_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan public.subscription_plans%rowtype;
  v_count bigint;
begin
  if not public.coachingos_subscription_write_allowed(new.institute_id) then
    raise exception 'Subscription is expired or inactive. Contact the platform administrator.'
      using errcode = '42501';
  end if;

  if tg_table_name = 'coachingos_records' then
    select p.* into v_plan
    from public.institute_subscriptions s
    join public.subscription_plans p on p.id = s.plan_id
    where s.institute_id = new.institute_id
    limit 1;

    if not found then return new; end if;

    if tg_op = 'UPDATE'
       and old.institute_id = new.institute_id
       and old.record_type = new.record_type then
      return new;
    end if;

    perform pg_advisory_xact_lock(hashtextextended(new.institute_id::text, 0));

    if v_plan.max_records is not null then
      select count(*) into v_count
      from public.coachingos_records r
      where r.institute_id = new.institute_id;
      if v_count >= v_plan.max_records then
        raise exception 'Plan record limit reached (%). Upgrade the plan to add more records.', v_plan.max_records
          using errcode = 'P0001';
      end if;
    end if;

    if new.record_type = 'branches' and v_plan.max_branches is not null then
      select count(*) into v_count
      from public.coachingos_records r
      where r.institute_id = new.institute_id
        and r.record_type = 'branches';
      if v_count >= v_plan.max_branches then
        raise exception 'Plan branch limit reached (%). Upgrade the plan to add another branch.', v_plan.max_branches
          using errcode = 'P0001';
      end if;
    end if;
    return new;

  elsif tg_table_name = 'institute_members' then
    if tg_op = 'UPDATE' and old.institute_id = new.institute_id then
      return new;
    end if;

    select p.* into v_plan
    from public.institute_subscriptions s
    join public.subscription_plans p on p.id = s.plan_id
    where s.institute_id = new.institute_id
    limit 1;

    if found then
      perform pg_advisory_xact_lock(hashtextextended(new.institute_id::text, 0));
    end if;

    if found and v_plan.max_members is not null then
      select count(*) into v_count
      from public.institute_members m
      where m.institute_id = new.institute_id;
      if v_count >= v_plan.max_members then
        raise exception 'Plan member limit reached (%). Upgrade the plan to add another member.', v_plan.max_members
          using errcode = 'P0001';
      end if;
    end if;
    return new;
  end if;
  return new;
end;
$$;

drop trigger if exists coachingos_subscription_record_limits on public.coachingos_records;
create trigger coachingos_subscription_record_limits
before insert or update on public.coachingos_records
for each row execute function public.enforce_coachingos_subscription_limits();

drop trigger if exists coachingos_subscription_member_limits on public.institute_members;
create trigger coachingos_subscription_member_limits
before insert or update on public.institute_members
for each row execute function public.enforce_coachingos_subscription_limits();

revoke all on function public.coachingos_subscription_write_allowed(uuid) from public, anon;
revoke all on function public.coachingos_subscription_write_allowed(uuid) from public, anon, authenticated, service_role;
revoke all on function public.enforce_coachingos_subscription_limits() from public, anon, authenticated;
