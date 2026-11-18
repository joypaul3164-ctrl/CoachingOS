# CoachingOS Local Restore Preflight — 2026-11-18

## Outcome
**Preflight inventory: PASS. Actual local PostgreSQL restore: BLOCKED / NOT RUN.**

No production database was modified. No SQL was executed against production.

## Verified backup assets
Source branch: `backup/pre-security-2026-11-18`

- `supabase/schema.sql` exists (13,444 bytes).
- `supabase/FINAL_SETUP.sql` exists (29,932 bytes).
- `supabase/backups/pre-security-2026-11-18-public-schema.json` exists (206,646 bytes).
- The schema snapshot parses as JSON and contains 12 table entries, 38 function entries, and 14 policy entries.
- Backup manifest records 25 migration source files and 15 applied migration-history entries on the live project.
- The manifest explicitly states that the structural snapshot is not a live-data backup and excludes operational records, Auth users/sessions, Storage file bytes, project secrets, and SMS credentials.

## Local runtime check
The available execution environment was checked for:
- `supabase` CLI — not installed.
- `docker` — not installed.
- `psql` — not installed.
- `pg_restore` — not installed.
- `postgres` / `initdb` — not installed.

Without a PostgreSQL engine or a disposable local Supabase stack, a real SQL restore and post-restore catalog/RLS verification cannot be executed here.

## Why migrations were not replayed
The repository contains 25 SQL migration source files while the production migration history reports 15 applied entries. They are not safe to replay blindly. Some source files may be historical, consolidated, or not represented one-to-one in the live migration history. A migration baseline reconciliation is required before replay.

## Result
- [x] Backup source branch and key files located.
- [x] Schema snapshot JSON parsed.
- [x] Table/function/policy inventory counts read.
- [x] Production untouched.
- [ ] Start isolated local PostgreSQL/Supabase runtime.
- [ ] Reconcile migration source files with migration history.
- [ ] Restore schema and migrations into disposable local database.
- [ ] Verify tables, functions, triggers, grants, RLS and policies.
- [ ] Run synthetic tenant-isolation and application smoke tests.

**Conclusion:** This is a successful preflight inventory, not a successful restore test. Full restore remains unverified.
