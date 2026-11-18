# CoachingOS Disaster Recovery Package
**Prepared:** 2026-11-18  
**Status:** Recovery documentation package created; full live-data backup and restore rehearsal are NOT complete.

## Purpose
This package is the recovery index for CoachingOS. It records where the existing source/schema snapshots live, what is still missing, and the safe recovery order. It is not itself a copy of the live database, user records, Storage objects, Auth users, or project secrets.

## Project reference
- Repository: `joypaul3164-ctrl/CoachingOS`
- Production Supabase project ref: `ebbmcgbaxqkdzvpzopfl`
- Production URL: `https://ebbmcgbaxqkdzvpzopfl.supabase.co`
- Production must not be used as a restore target.
- Production branch/deployment must not be changed as part of a rehearsal.

## Existing recovery assets
Use the immutable snapshot branch `backup/pre-security-2026-11-18` as the source for the pre-security baseline:
- `BACKUP_PRE_SECURITY_2026-11-18.md` — backup manifest.
- `DEPLOYMENT_RECOVERY.md` — frontend/source recovery notes.
- `SUPABASE_RECOVERY_AND_SECRETS.md` — Supabase recovery and secret-handling notes.
- `RESTORE_REHEARSAL_REPORT.md` — records that a real restore rehearsal has not been completed.
- `STAGING_RESTORE_BACKUP_PLAN.md` — staging and restore plan.
- `MULTITENANT_SECURITY_AUDIT_2026-11-18.md` — security audit notes.
- `supabase/schema.sql`, `supabase/FINAL_SETUP.sql` — checked-in schema/setup SQL where present.
- `supabase/backups/pre-security-2026-11-18-public-schema.json` — public schema snapshot (recorded in the backup manifest).
- `supabase/functions/guardian-attendance-notify/index.ts` — Edge Function source where present.

The backup branch is a source snapshot, not a verified point-in-time backup of all production data.

## What is not included yet
The following must be completed before claiming a full disaster-recovery backup:
1. A fresh export of production database data (not just schema), stored outside the production project.
2. A verified Storage object export/backup.
3. An Auth configuration and user-recovery plan. Do not export or commit password hashes, tokens, signing secrets, service-role keys, or other credentials into Git.
4. A secure, owner-controlled inventory/backup of required project settings and secrets. Keep actual secret values in an approved password manager or secure secret store, never in this repository or chat.
5. A second independent backup copy outside this GitHub repository/account.
6. A separate staging Supabase project or isolated restore target, with cost/owner approval as required.
7. A restore rehearsal into staging, followed by checks of schema, row counts, RLS, functions, Storage, Auth flows, and application connectivity.
8. A post-restore backup and a dated report containing results and limitations.

## Safe restore sequence
1. Confirm the target is a separate staging project. Never point restore commands at production.
2. Confirm the selected source commit/branch and record its SHA.
3. Restore schema and migrations first, then restore data using a supported Supabase backup/export workflow appropriate to the project's plan and database version.
4. Restore Storage objects and required Edge Functions separately.
5. Recreate project configuration from the secure owner-controlled inventory. Enter secrets directly in the provider dashboard/secret manager; do not paste them into GitHub or ChatGPT.
6. Verify RLS and grants before connecting any test account.
7. Use synthetic test data only. Verify tenant A cannot read or change tenant B data.
8. Verify login, password reset, core create/update flows, scheduled/Edge Functions, and Storage access.
9. Record failures and fix them in staging. Do not deploy or merge to production as part of this rehearsal.
10. Take a fresh backup of the successfully restored staging environment and record its location and checksum.

## Recovery acceptance checklist
- [ ] Full production database data export exists and checksum verified.
- [ ] Schema and migrations restore successfully.
- [ ] Storage files restore and can be read.
- [ ] Auth configuration is recreated safely; no secrets committed.
- [ ] Edge Functions and required schedules are restored.
- [ ] RLS/grants reviewed; cross-tenant isolation test passes with two isolated test tenants.
- [ ] Login, password reset, create/update, and critical workflows pass.
- [ ] Independent second backup copy exists.
- [ ] Staging restore report and post-restore backup are recorded.
- [ ] Owner approves any production recovery action separately.

## Security rules
- Never put passwords, OTPs, JWTs, database connection strings, Supabase service-role keys, GitHub tokens, or signing secrets in this repository, issues, logs, or chat.
- Never use production as a restore sandbox.
- Never delete or overwrite production data to test recovery.
- Do not claim recovery readiness until the checklist is completed and a restore rehearsal has passed.

## Current honest status
A source/schema/documentation baseline exists on `backup/pre-security-2026-11-18`. This package improves discoverability and gives a repeatable recovery checklist. It does **not** mean that live database records, Auth users, Storage objects, project secrets, or a second off-site copy have been backed up, and no staging restore has been verified yet.
