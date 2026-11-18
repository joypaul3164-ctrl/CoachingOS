-- Restrict notification RPCs to current active institute members.
-- Non-destructive: no notification or institute data is changed or deleted.
create or replace function public.get_coachingos_notifications(_institute_id uuid)
returns table(
  id uuid,
  category text,
  title text,
  message text,
  actor_user_id uuid,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.institute_members m
    join public.institutes i on i.id = m.institute_id
    where m.institute_id = _institute_id
      and m.user_id = (select auth.uid())
      and i.status = 'active'
  ) then
    raise exception 'Active institute membership required' using errcode = '42501';
  end if;

  return query
  select n.id, n.category, n.title, n.message, n.actor_user_id,
         n.entity_id, n.read_at, n.created_at
  from public.institute_notifications n
  where n.institute_id = _institute_id
    and n.recipient_user_id = (select auth.uid())
  order by n.created_at desc
  limit 100;
end;
$$;

create or replace function public.get_coachingos_unread_notification_count(_institute_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.institute_members m
    join public.institutes i on i.id = m.institute_id
    where m.institute_id = _institute_id
      and m.user_id = (select auth.uid())
      and i.status = 'active'
  ) then
    raise exception 'Active institute membership required' using errcode = '42501';
  end if;

  return (
    select count(*)::integer
    from public.institute_notifications n
    where n.institute_id = _institute_id
      and n.recipient_user_id = (select auth.uid())
      and n.read_at is null
  );
end;
$$;

create or replace function public.mark_all_coachingos_notifications_read(_institute_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.institute_members m
    join public.institutes i on i.id = m.institute_id
    where m.institute_id = _institute_id
      and m.user_id = (select auth.uid())
      and i.status = 'active'
  ) then
    raise exception 'Active institute membership required' using errcode = '42501';
  end if;

  update public.institute_notifications
  set read_at = now()
  where institute_id = _institute_id
    and recipient_user_id = (select auth.uid())
    and read_at is null;

  get diagnostics changed_count = row_count;
  return changed_count;
end;
$$;

revoke all on function public.get_coachingos_notifications(uuid) from public, anon;
revoke all on function public.get_coachingos_unread_notification_count(uuid) from public, anon;
revoke all on function public.mark_all_coachingos_notifications_read(uuid) from public, anon;
grant execute on function public.get_coachingos_notifications(uuid) to authenticated;
grant execute on function public.get_coachingos_unread_notification_count(uuid) to authenticated;
grant execute on function public.mark_all_coachingos_notifications_read(uuid) to authenticated;
