-- Remove nonessential table-level capabilities from API users.
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM authenticated;

-- These internal tables are intentionally accessed only through narrowly scoped SECURITY DEFINER RPCs.
REVOKE ALL PRIVILEGES ON TABLE
  public.institute_invitations,
  public.institute_notifications,
  public.institute_portal_links,
  public.institute_staff_audit_logs,
  public.institute_staff_invitations
FROM authenticated;

-- Guardian delivery history is read-only to signed-in users; writes stay in trusted server-side code.
REVOKE INSERT, UPDATE, DELETE ON TABLE public.guardian_delivery_logs FROM authenticated;

-- Staff audit logs are available only while the institute is active.
CREATE OR REPLACE FUNCTION public.get_coachingos_staff_audit_logs(_institute_id uuid)
RETURNS TABLE(
  id uuid,
  event_type text,
  actor_user_id uuid,
  target_user_id uuid,
  invitation_id uuid,
  details jsonb,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  caller_role text;
BEGIN
  SELECT m.role INTO caller_role
  FROM public.institute_members m
  JOIN public.institutes i ON i.id = m.institute_id
  WHERE m.institute_id = _institute_id
    AND m.user_id = (SELECT auth.uid())
    AND i.status = 'active';

  IF coalesce(caller_role, '') NOT IN ('owner', 'admin', 'manager') THEN
    RAISE EXCEPTION 'Not allowed to view staff audit logs' USING errcode = '42501';
  END IF;

  RETURN QUERY
  SELECT l.id, l.event_type, l.actor_user_id, l.target_user_id,
         l.invitation_id, l.details, l.created_at
  FROM public.institute_staff_audit_logs l
  WHERE l.institute_id = _institute_id
  ORDER BY l.created_at DESC
  LIMIT 100;
END;
$function$;
