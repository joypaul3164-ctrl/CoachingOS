-- CoachingOS Staff Audit Log
-- Records staff membership and invitation lifecycle events without storing secrets.

create table if not exists public.institute_staff_audit_logs (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes(id) on delete cascade,
  event_type text not null check (event_type in (
    'member_added','member_role_changed','member_removed',
    'invitation_created','invitation_accepted','invitation_revoked','invitation_expired'
  )),
  actor_user_id uuid,
  target_user_id uuid,
  invitation_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists institute_staff_audit_logs_institute_created_idx
  on public.institute_staff_audit_logs(institute_id, created_at desc);

alter table public.institute_staff_audit_logs enable row level security;
revoke all on public.institute_staff_audit_logs from anon, authenticated;
grant all on public.institute_staff_audit_logs to service_role;

create or replace function public.log_coachingos_staff_membership_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_name text;
  old_role text;
  new_role text;
  institute_key uuid;
  target_key uuid;
begin
  if tg_op = 'INSERT' then
    event_name := 'member_added';
    institute_key := new.institute_id;
    target_key := new.user_id;
    new_role := new.role;
  elsif tg_op = 'UPDATE' then
    if old.role is not distinct from new.role then
      return new;
    end if;
    event_name := 'member_role_changed';
    institute_key := new.institute_id;
    target_key := new.user_id;
    old_role := old.role;
    new_role := new.role;
  else
    event_name := 'member_removed';
    institute_key := old.institute_id;
    target_key := old.user_id;
    old_role := old.role;
  end if;

  insert into public.institute_staff_audit_logs(
    institute_id,event_type,actor_user_id,target_user_id,details
  ) values (
    institute_key,event_name,(select auth.uid()),target_key,
    jsonb_strip_nulls(jsonb_build_object('old_role',old_role,'new_role',new_role))
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists coachingos_staff_membership_audit on public.institute_members;
create trigger coachingos_staff_membership_audit
after insert or update of role or delete on public.institute_members
for each row execute function public.log_coachingos_staff_membership_change();

create or replace function public.log_coachingos_staff_invitation_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_name text;
  actor_key uuid;
begin
  if tg_op = 'INSERT' then
    event_name := 'invitation_created';
    actor_key := new.created_by;
  elsif old.status is distinct from new.status then
    if new.status = 'accepted' then
      event_name := 'invitation_accepted';
      actor_key := new.accepted_by;
    elsif new.status = 'revoked' then
      event_name := 'invitation_revoked';
      actor_key := (select auth.uid());
    elsif new.status = 'expired' then
      event_name := 'invitation_expired';
      actor_key := (select auth.uid());
    else
      return new;
    end if;
  else
    return new;
  end if;

  insert into public.institute_staff_audit_logs(
    institute_id,event_type,actor_user_id,invitation_id,details
  ) values (
    new.institute_id,event_name,actor_key,new.id,
    jsonb_strip_nulls(jsonb_build_object('email',new.email,'phone',new.phone,'role',new.role))
  );
  return new;
end;
$$;

drop trigger if exists coachingos_staff_invitation_audit on public.institute_staff_invitations;
create trigger coachingos_staff_invitation_audit
after insert or update of status on public.institute_staff_invitations
for each row execute function public.log_coachingos_staff_invitation_change();

create or replace function public.get_coachingos_staff_audit_logs(_institute_id uuid)
returns table(
  id uuid,
  event_type text,
  actor_user_id uuid,
  target_user_id uuid,
  invitation_id uuid,
  details jsonb,
  created_at timestamptz
)
language plpgsql
stable
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

  if coalesce(caller_role,'') not in ('owner','admin','manager') then
    raise exception 'Not allowed to view staff audit logs' using errcode = '42501';
  end if;

  return query
  select l.id,l.event_type,l.actor_user_id,l.target_user_id,
         l.invitation_id,l.details,l.created_at
  from public.institute_staff_audit_logs l
  where l.institute_id = _institute_id
  order by l.created_at desc
  limit 100;
end;
$$;

revoke all on function public.log_coachingos_staff_membership_change() from public;
revoke all on function public.log_coachingos_staff_invitation_change() from public;
revoke all on function public.get_coachingos_staff_audit_logs(uuid) from public;
grant execute on function public.get_coachingos_staff_audit_logs(uuid) to authenticated;
