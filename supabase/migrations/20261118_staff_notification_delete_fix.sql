-- Fix NEW record access on DELETE in staff notification trigger.
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
    if tg_op = 'DELETE' then
      inst_id := old.institute_id;
    else
      inst_id := new.institute_id;
    end if;
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
