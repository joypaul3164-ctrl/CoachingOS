-- CoachingOS Staff Management & role-based permissions
-- Adds secure member administration for existing registered accounts.
-- No passwords, service-role keys, or invitation tokens are exposed to the browser.
-- Safe to rerun; existing memberships and records are preserved.

create or replace function public.can_view_coachingos_records(
  _institute_id uuid,
  _record_type text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $
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
        or (m.role = 'accountant' and _record_type in ('fees','expenses'))
        or (m.role = 'receptionist' and _record_type in ('students','attendance','fees'))
        or (m.role = 'staff' and _record_type in ('routine','attendance'))
      )
  );
$;

revoke all on function public.can_view_coachingos_records(uuid,text) from public;
grant execute on function public.can_view_coachingos_records(uuid,text) to authenticated;

drop policy if exists "Active institute members can read institute records" on public.coachingos_records;
create policy "Role permitted members can read records"
on public.coachingos_records for select
to authenticated
using (public.can_view_coachingos_records(institute_id, record_type));

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
        or (m.role = 'accountant' and _record_type in ('fees','expenses'))
        or (m.role = 'receptionist' and _record_type in ('students','attendance','fees'))
      )
  );
$$;

revoke all on function public.can_manage_coachingos_records(uuid,text) from public;
grant execute on function public.can_manage_coachingos_records(uuid,text) to authenticated;

-- Replace broad admin/manager write rules with module-aware checks.
drop policy if exists "Active institute admins can add records" on public.coachingos_records;
drop policy if exists "Active institute admins can update records" on public.coachingos_records;
drop policy if exists "Active institute admins can delete records" on public.coachingos_records;

create policy "Role permitted members can add records"
on public.coachingos_records for insert
to authenticated
with check (public.can_manage_coachingos_records(institute_id, record_type));

create policy "Role permitted members can update records"
on public.coachingos_records for update
to authenticated
using (public.can_manage_coachingos_records(institute_id, record_type))
with check (public.can_manage_coachingos_records(institute_id, record_type));

create policy "Role permitted members can delete records"
on public.coachingos_records for delete
to authenticated
using (public.can_manage_coachingos_records(institute_id, record_type));

-- Return only the active institute's roster to its owner/admin/manager.
create or replace function public.get_coachingos_institute_members(_institute_id uuid)
returns table(user_id uuid, email text, role text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_coachingos_institute_role(
    _institute_id, array['owner','admin','manager']::text[]
  ) then
    raise exception 'Institute roster access required'
      using errcode = '42501';
  end if;

  return query
    select m.user_id, u.email::text, m.role, m.created_at
    from public.institute_members m
    join auth.users u on u.id = m.user_id
    where m.institute_id = _institute_id
    order by case m.role when 'owner' then 0 when 'admin' then 1 when 'manager' then 2 else 3 end,
             m.created_at;
end;
$$;

create or replace function public.admin_add_coachingos_member(
  _institute_id uuid,
  _email text,
  _role text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text;
  target_user_id uuid;
  new_role text := lower(trim(_role));
begin
  select m.role into caller_role
  from public.institute_members m
  where m.institute_id = _institute_id and m.user_id = (select auth.uid());

  if coalesce(caller_role,'') not in ('owner','admin') then
    raise exception 'Only institute owner or admin can add staff'
      using errcode = '42501';
  end if;
  if new_role not in ('admin','manager','teacher','accountant','receptionist','staff') then
    raise exception 'Invalid staff role';
  end if;
  if caller_role = 'admin' and new_role = 'admin' then
    raise exception 'Only the owner can appoint another admin'
      using errcode = '42501';
  end if;
  if coalesce(length(trim(_email)),0) < 5 then
    raise exception 'Enter a valid registered account email';
  end if;

  select u.id into target_user_id
  from auth.users u
  where lower(u.email) = lower(trim(_email))
  limit 1;

  if target_user_id is null then
    raise exception 'No account found for this email. The person must sign up first.';
  end if;
  if exists (
    select 1 from public.institute_members m
    where m.institute_id = _institute_id and m.user_id = target_user_id
  ) then
    raise exception 'This user is already a member of the institute';
  end if;

  insert into public.institute_members(institute_id,user_id,role)
  values (_institute_id,target_user_id,new_role);

  return target_user_id;
end;
$$;

create or replace function public.admin_update_coachingos_member_role(
  _institute_id uuid,
  _user_id uuid,
  _role text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text;
  target_role text;
  new_role text := lower(trim(_role));
begin
  select m.role into caller_role
  from public.institute_members m
  where m.institute_id = _institute_id and m.user_id = (select auth.uid());

  if coalesce(caller_role,'') not in ('owner','admin') then
    raise exception 'Only institute owner or admin can change staff roles'
      using errcode = '42501';
  end if;
  if new_role not in ('admin','manager','teacher','accountant','receptionist','staff') then
    raise exception 'Invalid staff role';
  end if;

  select m.role into target_role
  from public.institute_members m
  where m.institute_id = _institute_id and m.user_id = _user_id;

  if target_role is null then raise exception 'Member not found'; end if;
  if target_role = 'owner' then raise exception 'The owner role cannot be changed'; end if;
  if caller_role = 'admin' and (target_role = 'admin' or new_role = 'admin') then
    raise exception 'Admins cannot change admin-level memberships'
      using errcode = '42501';
  end if;

  update public.institute_members
  set role = new_role
  where institute_id = _institute_id and user_id = _user_id;
  return true;
end;
$$;

create or replace function public.admin_remove_coachingos_member(
  _institute_id uuid,
  _user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text;
  target_role text;
begin
  select m.role into caller_role
  from public.institute_members m
  where m.institute_id = _institute_id and m.user_id = (select auth.uid());

  if coalesce(caller_role,'') not in ('owner','admin') then
    raise exception 'Only institute owner or admin can remove staff'
      using errcode = '42501';
  end if;

  select m.role into target_role
  from public.institute_members m
  where m.institute_id = _institute_id and m.user_id = _user_id;

  if target_role is null then raise exception 'Member not found'; end if;
  if target_role = 'owner' then raise exception 'The owner cannot be removed'; end if;
  if caller_role = 'admin' and target_role = 'admin' then
    raise exception 'Admins cannot remove another admin'
      using errcode = '42501';
  end if;

  delete from public.institute_members
  where institute_id = _institute_id and user_id = _user_id;
  return true;
end;
$$;

revoke all on function public.get_coachingos_institute_members(uuid) from public;
revoke all on function public.admin_add_coachingos_member(uuid,text,text) from public;
revoke all on function public.admin_update_coachingos_member_role(uuid,uuid,text) from public;
revoke all on function public.admin_remove_coachingos_member(uuid,uuid) from public;

grant execute on function public.get_coachingos_institute_members(uuid) to authenticated;
grant execute on function public.admin_add_coachingos_member(uuid,text,text) to authenticated;
grant execute on function public.admin_update_coachingos_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.admin_remove_coachingos_member(uuid,uuid) to authenticated;
