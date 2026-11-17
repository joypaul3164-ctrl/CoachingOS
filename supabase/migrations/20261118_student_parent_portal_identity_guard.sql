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

revoke all on function public.get_coachingos_portal_dashboard() from public;
grant execute on function public.get_coachingos_portal_dashboard() to authenticated;
