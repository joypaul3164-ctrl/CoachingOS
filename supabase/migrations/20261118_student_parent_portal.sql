-- CoachingOS Student & Parent Portal — secure account linking and read-only dashboard
-- Run after the existing CoachingOS + staff-management migrations.
-- Portal users receive access only to explicitly linked student records.

create table if not exists public.institute_portal_links (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes(id) on delete cascade,
  student_record_id uuid not null references public.coachingos_records(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  relationship text not null default 'parent'
    check (relationship in ('student','parent','guardian')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (institute_id, student_record_id, user_id)
);

create index if not exists institute_portal_links_user_idx
  on public.institute_portal_links(user_id, institute_id);

alter table public.institute_portal_links enable row level security;
revoke all on public.institute_portal_links from anon, authenticated;
grant all on public.institute_portal_links to service_role;

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
              a.record_data->>'student_id' = s.id::text
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
              e.record_data->>'student_id' = s.id::text
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
              f.record_data->>'student_id' = s.id::text
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

revoke all on function public.admin_link_coachingos_portal_account(uuid,uuid,text,text) from public;
revoke all on function public.get_coachingos_portal_dashboard() from public;
grant execute on function public.admin_link_coachingos_portal_account(uuid,uuid,text,text) to authenticated;
grant execute on function public.get_coachingos_portal_dashboard() to authenticated;
