-- Keep the opt-in MFA policy independent of direct authenticated reads
-- from Supabase Auth's protected mfa_factors table.
-- A user without a verified TOTP factor may use AAL1. Once a verified factor
-- exists, all authenticated access to RLS-protected public tables requires AAL2.

CREATE SCHEMA IF NOT EXISTS coachingos_private;
REVOKE ALL ON SCHEMA coachingos_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA coachingos_private TO authenticated;

CREATE OR REPLACE FUNCTION coachingos_private.mfa_access_allowed()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN (SELECT auth.uid()) IS NULL THEN false
    WHEN EXISTS (
      SELECT 1
      FROM auth.mfa_factors f
      WHERE f.user_id = (SELECT auth.uid())
        AND f.status = 'verified'::auth.factor_status
    )
    THEN COALESCE((SELECT auth.jwt() ->> 'aal') = 'aal2', false)
    ELSE COALESCE((SELECT auth.jwt() ->> 'aal') IN ('aal1', 'aal2'), false)
  END;
$function$;

ALTER FUNCTION coachingos_private.mfa_access_allowed() OWNER TO postgres;
REVOKE ALL ON FUNCTION coachingos_private.mfa_access_allowed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION coachingos_private.mfa_access_allowed() TO authenticated;

DO $coachingos_mfa_rls_policies$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS coachingos_mfa_optin_aal2 ON public.%I',
      t.relname
    );
    EXECUTE format(
      'CREATE POLICY coachingos_mfa_optin_aal2 ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING ((SELECT coachingos_private.mfa_access_allowed())) WITH CHECK ((SELECT coachingos_private.mfa_access_allowed()))',
      t.relname
    );
  END LOOP;
END;
$coachingos_mfa_rls_policies$;
