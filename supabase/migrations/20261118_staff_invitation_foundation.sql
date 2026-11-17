-- CoachingOS Staff Invitation Foundation
-- Stores pending invitations safely. Raw invitation tokens are never stored.
-- Delivery (email/SMS) is intentionally not enabled until a server-side provider is configured.
-- Safe to rerun; existing staff memberships are untouched.

create table if not exists public.institute_staff_invitations (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes(id) on delete cascade,
  email text,
  phone text,
  role text not null check (role in ('admin','manager','teacher','accountant','receptionist','staff')),
  token_hash text not null unique,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  created_by uuid not null references auth.users(id),
  accepted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  constraint staff_invite_contact_required check (
    (nullif(trim(coalesce(email,'')),'') is not null)
    or (nullif(trim(coalesce(phone,'')),'') is not null)
  ),
  constraint staff_invite_email_format check (
    email is null or email = '' or email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  ),
  constraint staff_invite_phone_format check (
    phone is null or phone = '' or phone ~ '^[+][1-9][0-9]{7,14}$'
  ),
  constraint staff_invite_expiry_window check (
    expires_at > created_at and expires_at <= created_at + interval '7 days'
  )
);

create index if not exists institute_staff_invites_institute_created_idx
  on public.institute_staff_invitations(institute_id, created_at desc);
create index if not exists institute_staff_invites_pending_expiry_idx
  on public.institute_staff_invitations(expires_at)
  where status = 'pending';

create unique index if not exists institute_staff_invites_one_pending_email
  on public.institute_staff_invitations(institute_id, lower(email))
  where status = 'pending' and email is not null and email <> '';
create unique index if not exists institute_staff_invites_one_pending_phone
  on public.institute_staff_invitations(institute_id, phone)
  where status = 'pending' and phone is not null and phone <> '';

alter table public.institute_staff_invitations enable row level security;
revoke all on public.institute_staff_invitations from anon, authenticated;
grant all on public.institute_staff_invitations to service_role;

create or replace function public.get_coachingos_staff_invitations(_institute_id uuid)
returns table(
  id uuid, email text, phone text, role text, status text,
  created_at timestamptz, expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_coachingos_institute_role(
    _institute_id, array['owner','admin','manager']::text[]
  ) then
    raise exception 'Institute invitation access required'
      using errcode = '42501';
  end if;

  return query
    select i.id, i.email, i.phone, i.role,
      case when i.status = 'pending' and i.expires_at <= now()
        then 'expired' else i.status end,
      i.created_at, i.expires_at
    from public.institute_staff_invitations i
    where i.institute_id = _institute_id
    order by i.created_at desc
    limit 100;
end;
$$;

create or replace function public.admin_revoke_coachingos_staff_invitation(
  _institute_id uuid,
  _invitation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text;
begin
  select m.role into caller_role
  from public.institute_members m
  where m.institute_id = _institute_id
    and m.user_id = (select auth.uid());

  if coalesce(caller_role,'') not in ('owner','admin') then
    raise exception 'Only institute owner or admin can revoke invitations'
      using errcode = '42501';
  end if;

  update public.institute_staff_invitations
  set status = 'revoked', revoked_at = now()
  where id = _invitation_id
    and institute_id = _institute_id
    and status = 'pending';

  return found;
end;
$$;

revoke all on function public.get_coachingos_staff_invitations(uuid) from public;
revoke all on function public.admin_revoke_coachingos_staff_invitation(uuid,uuid) from public;
grant execute on function public.get_coachingos_staff_invitations(uuid) to authenticated;
grant execute on function public.admin_revoke_coachingos_staff_invitation(uuid,uuid) to authenticated;
