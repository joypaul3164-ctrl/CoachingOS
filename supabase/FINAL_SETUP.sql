-- CoachingOS FINAL SETUP BUNDLE
-- Run this single file once in Supabase SQL Editor.
-- Includes the pending portal student-record matching update and a safe
-- DELETE-event fix for the staff notification trigger.
-- Previously applied migrations are intentionally NOT repeated.

-- CoachingOS Portal identity isolation hardening
-- Run this migration in Supabase SQL Editor before testing the updated portal UI.

create or replace function public.get_coachingos_portal_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'linked_user_id', l.user_id,
        'institute_id', i.id,
        'institute_name', i.name,
        'relationship', l.relationship,
        'student_record_id', s.id,
        'student', s.record_data,
        'attendance', coalesce((
          select jsonb_agg(a.record_data order by a.created_at desc)
          from public.coachingos_records a
          where a.institute_id = l.institute_id
            and a.record_type = 'attendance'
            and (
              a.record_data->>'student_record_id' = s.id::text
              or a.record_data->>'student_id' = s.id::text
              or (
                nullif(s.record_data->>'name','') is not null
                and a.record_data->>'student' = s.record_data->>'name'
                and (
                  select count(*)
                  from public.coachingos_records s2
                  where s2.institute_id = l.institute_id
                    and s2.record_type = 'students'
                    and s2.record_data->>'name' = s.record_data->>'name'
                ) = 1
              )
            )
        ), '[]'::jsonb),
        'exams', coalesce((
          select jsonb_agg(e.record_data order by e.created_at desc)
          from public.coachingos_records e
          where e.institute_id = l.institute_id
            and e.record_type = 'exams'
            and (
              e.record_data->>'student_record_id' = s.id::text
              or e.record_data->>'student_id' = s.id::text
              or (
                nullif(s.record_data->>'name','') is not null
                and e.record_data->>'student' = s.record_data->>'name'
                and (
                  select count(*)
                  from public.coachingos_records s2
                  where s2.institute_id = l.institute_id
                    and s2.record_type = 'students'
                    and s2.record_data->>'name' = s.record_data->>'name'
                ) = 1
              )
            )
        ), '[]'::jsonb),
        'fees', coalesce((
          select jsonb_agg(f.record_data order by f.created_at desc)
          from public.coachingos_records f
          where f.institute_id = l.institute_id
            and f.record_type = 'fees'
            and (
              f.record_data->>'student_record_id' = s.id::text
              or f.record_data->>'student_id' = s.id::text
              or (
                nullif(s.record_data->>'name','') is not null
                and f.record_data->>'student' = s.record_data->>'name'
                and (
                  select count(*)
                  from public.coachingos_records s2
                  where s2.institute_id = l.institute_id
                    and s2.record_type = 'students'
                    and s2.record_data->>'name' = s.record_data->>'name'
                ) = 1
              )
            )
        ), '[]'::jsonb)
      )
      order by i.name, s.record_data->>'name'
    ),
    '[]'::jsonb
  )
  from public.institute_portal_links l
  join public.institutes i
    on i.id = l.institute_id and i.status = 'active'
  join public.coachingos_records s
    on s.id = l.student_record_id
   and s.institute_id = l.institute_id
   and s.record_type = 'students'
  where l.user_id = (select auth.uid());
$$;

revoke all on function public.get_coachingos_portal_dashboard() from public;
grant execute on function public.get_coachingos_portal_dashboard() to authenticated;


-- Reapply stricter Student versus Parent/Guardian exclusivity checks.
-- CoachingOS portal relationship isolation hardening
-- Student accounts: exactly one linked student profile per institute.
-- Parent/guardian accounts: may link multiple children, but cannot mix with student-role links.

create or replace function public.admin_link_coachingos_portal_account(
  _institute_id uuid,
  _student_record_id uuid,
  _email text,
  _relationship text default 'parent'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text;
  target_user_id uuid;
  link_id uuid;
  rel text := lower(trim(coalesce(_relationship,'parent')));
begin
  select m.role into caller_role
  from public.institute_members m
  where m.institute_id = _institute_id
    and m.user_id = (select auth.uid());

  if coalesce(caller_role,'') not in ('owner','admin','manager') then
    raise exception 'Portal linking requires institute owner, admin or manager'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.institutes i
    where i.id = _institute_id and i.status = 'active'
  ) then
    raise exception 'Institute is not active';
  end if;

  if rel not in ('student','parent','guardian') then
    raise exception 'Invalid portal relationship';
  end if;

  if coalesce(length(trim(_email)),0) < 5 then
    raise exception 'Enter the registered account email';
  end if;

  if not exists (
    select 1 from public.coachingos_records r
    where r.id = _student_record_id
      and r.institute_id = _institute_id
      and r.record_type = 'students'
  ) then
    raise exception 'Student record not found in this institute';
  end if;

  select u.id into target_user_id
  from auth.users u
  where lower(u.email) = lower(trim(_email))
    and u.email_confirmed_at is not null
  limit 1;

  if target_user_id is null then
    raise exception 'No verified account found for this email. The user must sign up and verify email first.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_institute_id::text || ':' || target_user_id::text, 0)
  );

  if rel = 'student' and exists (
    select 1 from public.institute_portal_links l
    where l.institute_id = _institute_id
      and l.user_id = target_user_id
      and (l.student_record_id <> _student_record_id or l.relationship <> 'student')
  ) then
    raise exception 'A student account can be linked to only one student profile. Use Parent or Guardian for multiple children.';
  end if;

  if rel in ('parent','guardian') and exists (
    select 1 from public.institute_portal_links l
    where l.institute_id = _institute_id
      and l.user_id = target_user_id
      and l.relationship = 'student'
  ) then
    raise exception 'This account already has a Student link. A Student account cannot also be used as a Parent or Guardian account.';
  end if;

  insert into public.institute_portal_links(
    institute_id, student_record_id, user_id, relationship, created_by
  )
  values (_institute_id, _student_record_id, target_user_id, rel, (select auth.uid()))
  on conflict (institute_id, student_record_id, user_id)
  do update set relationship = excluded.relationship
  returning id into link_id;

  return link_id;
end;
$$;

revoke all on function public.admin_link_coachingos_portal_account(uuid,uuid,text,text) from public;
grant execute on function public.admin_link_coachingos_portal_account(uuid,uuid,text,text) to authenticated;


-- Fix notification trigger handling for DELETE operations.
create or replace function public.capture_coachingos_staff_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_title text;
  event_message text;
  target_user uuid;
  event_category text := 'staff';
  inst_id uuid;
  actor uuid := auth.uid();
begin
  if tg_table_name = 'institute_members' then
    if tg_op = 'DELETE' then
      inst_id := old.institute_id;
    else
      inst_id := new.institute_id;
    end if;
    if tg_op = 'INSERT' then
      target_user := new.user_id;
      event_title := 'Staff member added';
      event_message := 'You have been added to an institute with role: ' || coalesce(new.role,'staff') || '.';
      if target_user is not null and target_user is distinct from actor then
        insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
        values(inst_id,target_user,actor,'staff',event_title,event_message,new.id);
      end if;
      return new;
    elsif tg_op = 'UPDATE' then
      if old.role is distinct from new.role then
        target_user := new.user_id;
        event_title := 'Your staff role was changed';
        event_message := 'Your institute role is now: ' || coalesce(new.role,'staff') || '.';
        if target_user is not null and target_user is distinct from actor then
          insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
          values(inst_id,target_user,actor,'staff',event_title,event_message,new.id);
        end if;
      end if;
      return new;
    elsif tg_op = 'DELETE' then
      target_user := old.user_id;
      if target_user is not null and target_user is distinct from actor then
        insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
        values(inst_id,target_user,actor,'staff','Institute access removed','Your access to this institute has been removed.',old.id);
      end if;
      return old;
    end if;
  elsif tg_table_name = 'institute_staff_invitations' then
    inst_id := new.institute_id;
    if tg_op = 'INSERT' then
      insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
      select inst_id, m.user_id, actor, 'invitation', 'A staff invitation was created',
        'A new invitation was created for ' || coalesce(new.email,new.phone,'a staff member') || '.',
        new.id
      from public.institute_members m
      where m.institute_id = inst_id
        and m.role in ('owner','admin','manager')
        and m.user_id is distinct from actor;
      return new;
    elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
      if new.status = 'accepted' and new.created_by is not null and new.created_by is distinct from new.accepted_by then
        insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
        values(inst_id,new.created_by,new.accepted_by,'invitation','Staff invitation accepted',
          'The invitation for ' || coalesce(new.email,new.phone,'a staff member') || ' was accepted.',new.id);
      elsif new.status = 'revoked' then
        for target_user in
          select u.id
          from auth.users u
          where (new.email is not null and lower(u.email) = lower(new.email) and u.email_confirmed_at is not null)
             or (new.phone is not null and u.phone = new.phone and u.phone_confirmed_at is not null)
        loop
          if target_user is distinct from actor then
            insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
            values(inst_id,target_user,actor,'invitation','Staff invitation revoked',
              'A staff invitation for your account was revoked.',new.id);
          end if;
        end loop;
      end if;
      return new;
    end if;
  end if;
  return null;
end;
$$;

-- CoachingOS final security and performance reconciliation
-- Idempotent, non-destructive: adds missing FK indexes and tightens RPC execution.
-- No institute/student/business records are modified.

create index if not exists institute_portal_links_student_record_idx
  on public.institute_portal_links(student_record_id);
create index if not exists institute_portal_links_created_by_idx
  on public.institute_portal_links(created_by);
create index if not exists institutes_owner_id_idx
  on public.institutes(owner_id);
create index if not exists institute_invitations_created_by_idx
  on public.institute_invitations(created_by);
create index if not exists institute_staff_invitations_created_by_idx
  on public.institute_staff_invitations(created_by);
create index if not exists institute_staff_invitations_accepted_by_idx
  on public.institute_staff_invitations(accepted_by);
create index if not exists institute_notifications_institute_id_idx
  on public.institute_notifications(institute_id);
create index if not exists institute_notifications_actor_user_id_idx
  on public.institute_notifications(actor_user_id);

-- Enforce one Student profile per account per institute at the database boundary.
-- The existing account-link RPC separately blocks mixing Student and Parent/Guardian.
create unique index if not exists institute_portal_links_one_student_profile
  on public.institute_portal_links(institute_id,user_id)
  where relationship = 'student';

-- Remove anonymous/public direct execution from SECURITY DEFINER functions.
-- Authenticated access remains for application RPCs and RLS helper functions.
-- Trigger functions are not directly executable by browser roles.
do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as signature,
           p.prorettype = 'trigger'::regtype as is_trigger
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from public, anon', fn.signature);
    if fn.is_trigger then
      execute format('revoke execute on function %s from authenticated', fn.signature);
    else
      execute format('grant execute on function %s to authenticated', fn.signature);
    end if;
  end loop;
end;
$$;

-- Enable leaked-password protection separately in Supabase Dashboard:
-- Authentication -> Settings -> Password Security -> Leaked password protection.
