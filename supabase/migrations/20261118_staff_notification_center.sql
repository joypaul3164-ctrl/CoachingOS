-- CoachingOS Staff Notification Center
create table if not exists public.institute_notifications (
  id uuid primary key default gen_random_uuid(),
  institute_id uuid not null references public.institutes(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  category text not null check (category in ('staff','invitation','system')),
  title text not null,
  message text not null,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists institute_notifications_recipient_idx
  on public.institute_notifications (recipient_user_id, institute_id, created_at desc);
create index if not exists institute_notifications_unread_idx
  on public.institute_notifications (recipient_user_id, institute_id)
  where read_at is null;

alter table public.institute_notifications enable row level security;
revoke all on public.institute_notifications from anon, authenticated;
grant select, insert, update, delete on public.institute_notifications to service_role;

create or replace function public.get_coachingos_notifications(_institute_id uuid)
returns table (
  id uuid, category text, title text, message text,
  actor_user_id uuid, entity_id uuid, read_at timestamptz, created_at timestamptz
)
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  return query
  select n.id, n.category, n.title, n.message, n.actor_user_id,
         n.entity_id, n.read_at, n.created_at
  from public.institute_notifications n
  where n.institute_id = _institute_id
    and n.recipient_user_id = auth.uid()
  order by n.created_at desc
  limit 100;
end;
$$;

create or replace function public.get_coachingos_unread_notification_count(_institute_id uuid)
returns integer
language sql
security definer
stable
set search_path = ''
as $$
  select count(*)::integer
  from public.institute_notifications n
  where n.institute_id = _institute_id
    and n.recipient_user_id = auth.uid()
    and n.read_at is null;
$$;

create or replace function public.mark_coachingos_notification_read(_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.institute_notifications
  set read_at = now()
  where id = _notification_id
    and recipient_user_id = auth.uid()
    and read_at is null;
  return found;
end;
$$;

create or replace function public.mark_all_coachingos_notifications_read(_institute_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare changed_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.institute_notifications
  set read_at = now()
  where institute_id = _institute_id
    and recipient_user_id = auth.uid()
    and read_at is null;
  get diagnostics changed_count = row_count;
  return changed_count;
end;
$$;

create or replace function public.capture_coachingos_staff_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_title text;
  event_message text;
  target_user uuid;
  event_category text := 'staff';
  inst_id uuid;
  actor uuid := auth.uid();
begin
  if tg_table_name = 'institute_members' then
    inst_id := coalesce(new.institute_id, old.institute_id);
    if tg_op = 'INSERT' then
      target_user := new.user_id;
      event_title := 'Staff member added';
      event_message := 'You have been added to an institute with role: ' || coalesce(new.role,'staff') || '.';
      if target_user is not null and target_user is distinct from actor then
        insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
        values(inst_id,target_user,actor,'staff',event_title,event_message,new.id);
      end if;
      return new;
    elsif tg_op = 'UPDATE' then
      if old.role is distinct from new.role then
        target_user := new.user_id;
        event_title := 'Your staff role was changed';
        event_message := 'Your institute role is now: ' || coalesce(new.role,'staff') || '.';
        if target_user is not null and target_user is distinct from actor then
          insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
          values(inst_id,target_user,actor,'staff',event_title,event_message,new.id);
        end if;
      end if;
      return new;
    elsif tg_op = 'DELETE' then
      target_user := old.user_id;
      if target_user is not null and target_user is distinct from actor then
        insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
        values(inst_id,target_user,actor,'staff','Institute access removed','Your access to this institute has been removed.',old.id);
      end if;
      return old;
    end if;
  elsif tg_table_name = 'institute_staff_invitations' then
    inst_id := new.institute_id;
    if tg_op = 'INSERT' then
      insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
      select inst_id, m.user_id, actor, 'invitation', 'A staff invitation was created',
        'A new invitation was created for ' || coalesce(new.email,new.phone,'a staff member') || '.',
        new.id
      from public.institute_members m
      where m.institute_id = inst_id
        and m.role in ('owner','admin','manager')
        and m.user_id is distinct from actor;
      return new;
    elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
      if new.status = 'accepted' and new.created_by is not null and new.created_by is distinct from new.accepted_by then
        insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
        values(inst_id,new.created_by,new.accepted_by,'invitation','Staff invitation accepted',
          'The invitation for ' || coalesce(new.email,new.phone,'a staff member') || ' was accepted.',new.id);
      elsif new.status = 'revoked' then
        for target_user in
          select u.id
          from auth.users u
          where (new.email is not null and lower(u.email) = lower(new.email) and u.email_confirmed_at is not null)
             or (new.phone is not null and u.phone = new.phone and u.phone_confirmed_at is not null)
        loop
          if target_user is distinct from actor then
            insert into public.institute_notifications(institute_id,recipient_user_id,actor_user_id,category,title,message,entity_id)
            values(inst_id,target_user,actor,'invitation','Staff invitation revoked',
              'A staff invitation for your account was revoked.',new.id);
          end if;
        end loop;
      end if;
      return new;
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists coachingos_staff_member_notification on public.institute_members;
create trigger coachingos_staff_member_notification
after insert or update of role or delete on public.institute_members
for each row execute function public.capture_coachingos_staff_notification();

drop trigger if exists coachingos_staff_invitation_notification on public.institute_staff_invitations;
create trigger coachingos_staff_invitation_notification
after insert or update of status on public.institute_staff_invitations
for each row execute function public.capture_coachingos_staff_notification();

revoke all on function public.get_coachingos_notifications(uuid) from public;
revoke all on function public.get_coachingos_unread_notification_count(uuid) from public;
revoke all on function public.mark_coachingos_notification_read(uuid) from public;
revoke all on function public.mark_all_coachingos_notifications_read(uuid) from public;
grant execute on function public.get_coachingos_notifications(uuid) to authenticated;
grant execute on function public.get_coachingos_unread_notification_count(uuid) to authenticated;
grant execute on function public.mark_coachingos_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_coachingos_notifications_read(uuid) to authenticated;

revoke all on function public.capture_coachingos_staff_notification() from public, anon, authenticated;
