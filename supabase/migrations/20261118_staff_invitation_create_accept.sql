-- CoachingOS Staff Invitation: secure creation and acceptance
-- Raw tokens are generated in the browser and never stored in the database.
-- The database stores only a SHA-256 token hash.

create or replace function public.admin_create_coachingos_staff_invitation(
  _institute_id uuid,
  _email text,
  _phone text,
  _role text,
  _token_hash text
)
returns table(id uuid, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text;
  clean_email text;
  clean_phone text;
begin
  select m.role into caller_role
  from public.institute_members m
  where m.institute_id = _institute_id
    and m.user_id = (select auth.uid());

  if coalesce(caller_role,'') not in ('owner','admin') then
    raise exception 'Only institute owner or admin can create invitations'
      using errcode = '42501';
  end if;

  if _role not in ('admin','manager','teacher','accountant','receptionist','staff') then
    raise exception 'Invalid staff role' using errcode = '22023';
  end if;

  if _role = 'admin' and caller_role <> 'owner' then
    raise exception 'Only the institute owner can invite an admin'
      using errcode = '42501';
  end if;

  clean_email := nullif(lower(trim(coalesce(_email,''))), '');
  clean_phone := nullif(trim(coalesce(_phone,'')), '');

  if clean_email is null and clean_phone is null then
    raise exception 'Email or phone is required' using errcode = '22023';
  end if;

  if clean_email is not null and clean_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Invalid email address' using errcode = '22023';
  end if;

  if clean_phone is not null and clean_phone !~ '^[+][1-9][0-9]{7,14}$' then
    raise exception 'Phone must use E.164 format' using errcode = '22023';
  end if;

  if coalesce(_token_hash,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid invitation token hash' using errcode = '22023';
  end if;

  return query
  insert into public.institute_staff_invitations(
    institute_id,email,phone,role,token_hash,created_by,expires_at
  )
  values(
    _institute_id,clean_email,clean_phone,_role,_token_hash,
    (select auth.uid()),now()+interval '7 days'
  )
  returning institute_staff_invitations.id,
            institute_staff_invitations.expires_at;
end;
$$;

create or replace function public.accept_coachingos_staff_invitation(
  _token_hash text
)
returns table(institute_id uuid, role text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  invite_row public.institute_staff_invitations%rowtype;
  account_row record;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in before accepting an invitation'
      using errcode = '42501';
  end if;

  if coalesce(_token_hash,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid invitation link' using errcode = '22023';
  end if;

  select i.* into invite_row
  from public.institute_staff_invitations i
  where i.token_hash = _token_hash
  for update;

  if not found then
    raise exception 'Invitation not found or invalid';
  end if;

  if invite_row.status <> 'pending' then
    raise exception 'This invitation is no longer pending';
  end if;

  if invite_row.expires_at <= now() then
    raise exception 'This invitation has expired';
  end if;

  select u.email,u.phone,u.email_confirmed_at,u.phone_confirmed_at
    into account_row
  from auth.users u
  where u.id = (select auth.uid());

  if invite_row.email is not null and (
    account_row.email_confirmed_at is null
    or lower(coalesce(account_row.email,'')) <> lower(invite_row.email)
  ) then
    raise exception 'Sign in with the verified email address this invitation was sent to'
      using errcode = '42501';
  end if;

  if invite_row.phone is not null and (
    account_row.phone_confirmed_at is null
    or coalesce(account_row.phone,'') <> invite_row.phone
  ) then
    raise exception 'Sign in with the verified phone number this invitation was sent to'
      using errcode = '42501';
  end if;

  insert into public.institute_members(institute_id,user_id,role)
  values(invite_row.institute_id,(select auth.uid()),invite_row.role)
  on conflict (institute_id,user_id) do nothing;

  if not found then
    raise exception 'This account is already a member of the institute';
  end if;

  update public.institute_staff_invitations
  set status='accepted',
      accepted_by=(select auth.uid()),
      accepted_at=now()
  where id=invite_row.id;

  return query select invite_row.institute_id,invite_row.role;
end;
$$;

revoke all on function public.admin_create_coachingos_staff_invitation(uuid,text,text,text,text) from public;
revoke all on function public.accept_coachingos_staff_invitation(text) from public;
grant execute on function public.admin_create_coachingos_staff_invitation(uuid,text,text,text,text) to authenticated;
grant execute on function public.accept_coachingos_staff_invitation(text) to authenticated;
