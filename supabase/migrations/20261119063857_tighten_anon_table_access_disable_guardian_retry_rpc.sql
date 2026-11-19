-- Applied to the live CoachingOS project on 2026-11-19.
-- Anonymous clients have no RLS policies in public; remove unused table/sequence grants.
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- Guardian SMS delivery is disabled in the free-only configuration.
-- The UI retry action is removed; block direct RPC calls from authenticated clients too.
REVOKE EXECUTE ON FUNCTION public.retry_coachingos_guardian_delivery(uuid) FROM authenticated;
