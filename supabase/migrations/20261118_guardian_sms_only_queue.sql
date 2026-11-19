create or replace function public.enqueue_guardian_attendance_delivery()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  student_id uuid;
  student_data jsonb;
  guardian_phone text;
  consent text;
  event_token text;
  sms_status text;
begin
  if new.record_type <> 'attendance' or coalesce(new.record_data->>'status','') <> 'Present' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.record_type = 'attendance'
     and coalesce(old.record_data->>'status','') = 'Present' then
    return new;
  end if;

  student_id := nullif(new.record_data->>'student_record_id','')::uuid;
  event_token := new.id::text || ':' || coalesce(new.updated_at, new.created_at, pg_catalog.now())::text;
  if student_id is not null then
    select s.record_data into student_data from public.coachingos_records s
    where s.id = student_id and s.institute_id = new.institute_id
      and s.record_type = 'students' limit 1;
  end if;

  guardian_phone := nullif(pg_catalog.btrim(coalesce(student_data->>'guardian_phone','')), '');
  consent := lower(pg_catalog.btrim(coalesce(student_data->>'guardian_report_consent','')));
  sms_status := case when student_data is null then 'blocked'
    when consent <> 'yes' then 'skipped_consent'
    when guardian_phone is null then 'skipped_no_contact' else 'queued' end;

  insert into public.guardian_delivery_logs(
    institute_id, attendance_record_id, student_record_id, event_key,
    channel, recipient_masked, status, error_message
  ) values
  (new.institute_id,new.id,student_id,event_token,'email',null,'blocked','email_notifications_disabled'),
  (new.institute_id,new.id,student_id,event_token,'sms',
    case when guardian_phone is null then null else '***'||pg_catalog.right(regexp_replace(guardian_phone,'[^0-9]','','g'),4) end,
    sms_status,
    case when student_data is null then 'student_record_not_found'
      when consent <> 'yes' then 'guardian_consent_not_yes'
      when guardian_phone is null then 'guardian_phone_missing' else null end)
  on conflict (event_key,channel) do nothing;
  return new;
end;
$function$;

drop trigger if exists coachingos_guardian_attendance_delivery on public.coachingos_records;
create trigger coachingos_guardian_attendance_delivery
after insert or update of record_data on public.coachingos_records
for each row execute function public.enqueue_guardian_attendance_delivery();

create or replace function public.retry_coachingos_guardian_delivery(_log_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare
  target_institute uuid;
  target_attendance uuid;
  caller_role text;
begin
  select l.institute_id into target_institute from public.guardian_delivery_logs l
  where l.id = _log_id and l.channel = 'sms';
  if target_institute is null then raise exception 'SMS delivery log not found'; end if;

  select m.role into caller_role from public.institute_members m
  where m.institute_id = target_institute and m.user_id = (select auth.uid()) limit 1;
  if coalesce(caller_role,'') not in ('owner','admin','manager','receptionist') then
    raise exception 'Not authorized to retry guardian delivery' using errcode = '42501';
  end if;

  update public.guardian_delivery_logs l
  set status = 'queued', error_message = null, updated_at = pg_catalog.now()
  where l.id = _log_id and l.channel = 'sms'
    and l.status in ('failed','blocked') and l.attempt_count < 3
  returning l.attendance_record_id into target_attendance;
  if target_attendance is null then raise exception 'SMS delivery is not retryable or retry limit reached'; end if;
  return target_attendance;
end;
$function$;

revoke all on function public.enqueue_guardian_attendance_delivery() from public, anon, authenticated;
revoke all on function public.retry_coachingos_guardian_delivery(uuid) from public, anon;
grant execute on function public.retry_coachingos_guardian_delivery(uuid) to authenticated;