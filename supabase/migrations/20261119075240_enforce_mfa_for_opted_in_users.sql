DO $$
DECLARE
  t record;
  policy_sql text;
BEGIN
  FOR t IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public'
      AND c.relkind='r'
      AND c.relrowsecurity
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS coachingos_mfa_optin_aal2 ON public.%I', t.relname);
    policy_sql := format(
      'CREATE POLICY coachingos_mfa_optin_aal2 ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (array[(select auth.jwt()->>''aal'')] <@ (select case when count(id)>0 then array[''aal2''] else array[''aal1'',''aal2''] end from auth.mfa_factors where (select auth.uid())=user_id and status=''verified'')) WITH CHECK (array[(select auth.jwt()->>''aal'')] <@ (select case when count(id)>0 then array[''aal2''] else array[''aal1'',''aal2''] end from auth.mfa_factors where (select auth.uid())=user_id and status=''verified''))',
      t.relname
    );
    EXECUTE policy_sql;
  END LOOP;
END $$;
