-- Narrow student selector RPC for operational roles that need to link attendance, exams or fees.
-- It returns only the minimum student fields and is institute-scoped.
create or replace function public.get_coachingos_student_options(_institute_id uuid)
returns table(id uuid, name text, roll text, class_name text, batch text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select
    r.id,
    coalesce(r.record_data->>'name','') as name,
    coalesce(r.record_data->>'roll','') as roll,
    coalesce(r.record_data->>'class_name','') as class_name,
    coalesce(r.record_data->>'batch','') as batch
  from public.coachingos_records r
  join public.institutes i on i.id = r.institute_id and i.status = 'active'
  where r.institute_id = _institute_id
    and r.record_type = 'students'
    and exists (
      select 1
      from public.institute_members m
      where m.institute_id = _institute_id
        and m.user_id = (select auth.uid())
        and m.role in ('owner','admin','manager','teacher','accountant','receptionist')
    )
  order by r.record_data->>'name';
end;
$$;

revoke all on function public.get_coachingos_student_options(uuid) from public, anon;
grant execute on function public.get_coachingos_student_options(uuid) to authenticated;
