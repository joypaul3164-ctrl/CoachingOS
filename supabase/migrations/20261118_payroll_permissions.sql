-- CoachingOS Payroll module permissions
-- Accountant can read and manage payroll records; owners/admins/managers retain full access.

create or replace function public.can_view_coachingos_records(
  _institute_id uuid,
  _record_type text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
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
        or (m.role = 'staff' and _record_type in ('routine','attendance'))
      )
  );
$$;

create or replace function public.can_manage_coachingos_records(
  _institute_id uuid,
  _record_type text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
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

revoke all on function public.can_view_coachingos_records(uuid,text) from public;
revoke all on function public.can_manage_coachingos_records(uuid,text) from public;
grant execute on function public.can_view_coachingos_records(uuid,text) to authenticated;
grant execute on function public.can_manage_coachingos_records(uuid,text) to authenticated;
