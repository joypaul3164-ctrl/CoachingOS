-- CoachingOS: allow staff assignment by verified email and/or phone.
-- Existing staff and records are preserved. Safe to rerun.

drop function if exists public.get_coachingos_institute_members(uuid);

create function public.get_coachingos_institute_members(_institute_id uuid)
returns table(user_id uuid, email text, phone text, role text, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.has_coachingos_institute_role(_institute_id, array['owner','admin','manager']::text[]) then
    raise exception 'Institute roster access required' using errcode = '42501';
  end if;
  return query
    select m.user_id, u.email::text, nullif(u.phone, '')::text, m.role, m.created_at
    from public.institute_members m join auth.users u on u.id = m.user_id
    where m.institute_id = _institute_id
    order by case m.role when 'owner' then 0 when 'admin' then 1 when 'manager' then 2 else 3 end, m.created_at;
end;
$$;

revoke all on function public.get_coachingos_institute_members(uuid) from public;
grant execute on function public.get_coachingos_institute_members(uuid) to authenticated;

create or replace function public.admin_add_coachingos_member_by_contact(_institute_id uuid, _email text, _phone text, _role text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_role text;
  target_user_id uuid;
  new_role text := lower(trim(_role));
  email_value text := nullif(lower(trim(coalesce(_email, ''))), '');
  phone_value text := nullif(trim(coalesce(_phone, '')), '');
begin
  select m.role into caller_role from public.institute_members m
  where m.institute_id = _institute_id and m.user_id = (select auth.uid());
  if coalesce(caller_role, '') not in ('owner', 'admin') then
    raise exception 'Only institute owner or admin can add staff' using errcode = '42501';
  end if;
  if new_role not in ('admin','manager','teacher','accountant','receptionist','staff') then
    raise exception 'Invalid staff role';
  end if;
  if caller_role = 'admin' and new_role = 'admin' then
    raise exception 'Only the owner can appoint another admin' using errcode = '42501';
  end if;
  if email_value is null and phone_value is null then raise exception 'Enter an email address or phone number'; end if;
  if email_value is not null and (position('@' in email_value) < 2 or position('.' in split_part(email_value, '@', 2)) < 2) then
    raise exception 'Enter a valid email address';
  end if;
  if phone_value is not null and phone_value !~ '^[+][1-9][0-9]{7,14}$' then
    raise exception 'Use international phone format, for example +8801XXXXXXXXX';
  end if;
  select u.id into target_user_id from auth.users u
  where (email_value is null or (lower(u.email) = email_value and u.email_confirmed_at is not null))
    and (phone_value is null or (u.phone = phone_value and u.phone_confirmed_at is not null))
  limit 1;
  if target_user_id is null then raise exception 'No registered account matches the supplied verified contact details'; end if;
  if exists (select 1 from public.institute_members m where m.institute_id = _institute_id and m.user_id = target_user_id) then
    raise exception 'This user is already a member of the institute';
  end if;
  insert into public.institute_members(institute_id, user_id, role) values (_institute_id, target_user_id, new_role);
  return target_user_id;
end;
$$;

revoke all on function public.admin_add_coachingos_member_by_contact(uuid,text,text,text) from public;
grant execute on function public.admin_add_coachingos_member_by_contact(uuid,text,text,text) to authenticated;