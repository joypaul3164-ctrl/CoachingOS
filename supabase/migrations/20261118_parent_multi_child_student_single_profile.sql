-- CoachingOS Parent multi-child / Student single-profile access rule
-- Parent/guardian accounts may link multiple students in an institute.
-- A student relationship may link only one student record per user per institute.
-- All portal reads remain scoped to auth.uid() in get_coachingos_portal_dashboard().

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

  -- Serialize concurrent link attempts for this account/institute.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_institute_id::text || ':' || target_user_id::text, 0)
  );

  if rel = 'student' and exists (
    select 1
    from public.institute_portal_links l
    where l.institute_id = _institute_id
      and l.user_id = target_user_id
      and l.relationship = 'student'
      and l.student_record_id <> _student_record_id
  ) then
    raise exception 'A student account can be linked to only one student profile in this institute. Use Parent relationship for multiple children.';
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
