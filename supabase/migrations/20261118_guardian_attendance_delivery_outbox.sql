-- Secure outbox table for guardian attendance delivery.
-- The SMS-only function and trigger are created in the following migration.

CREATE TABLE IF NOT EXISTS public.guardian_delivery_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institute_id uuid NOT NULL REFERENCES public.institutes(id) ON DELETE CASCADE,
  attendance_record_id uuid NOT NULL,
  student_record_id uuid,
  event_key text NOT NULL,
  channel text NOT NULL CHECK (channel IN ('email','sms')),
  recipient_masked text,
  status text NOT NULL CHECK (
    status IN ('queued','processing','sent','failed','blocked','skipped_consent','skipped_no_contact')
  ),
  provider text,
  provider_message_id text,
  error_message text,
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  UNIQUE (event_key, channel)
);

CREATE INDEX IF NOT EXISTS guardian_delivery_logs_institute_created_idx
  ON public.guardian_delivery_logs (institute_id, created_at DESC);
CREATE INDEX IF NOT EXISTS guardian_delivery_logs_attendance_idx
  ON public.guardian_delivery_logs (attendance_record_id);

ALTER TABLE public.guardian_delivery_logs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.guardian_delivery_logs FROM anon, PUBLIC;
GRANT SELECT ON public.guardian_delivery_logs TO authenticated;
GRANT ALL ON public.guardian_delivery_logs TO service_role;

DROP POLICY IF EXISTS guardian_delivery_logs_read_admin ON public.guardian_delivery_logs;
CREATE POLICY guardian_delivery_logs_read_admin
ON public.guardian_delivery_logs
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.institute_members m
    WHERE m.institute_id = guardian_delivery_logs.institute_id
      AND m.user_id = (SELECT auth.uid())
      AND m.role IN ('owner','admin','manager','receptionist')
  )
);
