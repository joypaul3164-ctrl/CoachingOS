# CoachingOS pre-security backup

- Repository: joypaul3164-ctrl/CoachingOS
- Source branch: main
- Source commit: 20a621335cec8a38b69cdce330a4cfa59ee0b432
- Backup branch: backup/pre-security-2026-11-18
- Supabase project: ebbmcgbaxqkdzvpzopfl (Coachings)
- Database schema snapshot: supabase/backups/pre-security-2026-11-18-public-schema.json
- Snapshot captured: 2026-11-18T13:17:35.504751+00:00
- Public tables: 12
- Public functions captured: 38
- RLS policies captured: 14
- Triggers captured: 8

## Supabase migration versions present
20261118073629 final_security_portal_reconciliation
20261118075355 notification_rpc_membership_scope
20261118075506 narrow_student_selector_rpc
20261118081012 20261118_minimize_portal_personal_data
20261118081456 20261118_guardian_attendance_delivery_outbox
20261118081536 20261118_guardian_delivery_retry_rpc
20261118081632 20261118_guardian_delivery_atomic_claim
20261118081803 20261118_guardian_trigger_old_record_safety
20261118083422 coachingos_subscription_write_and_limits
20261118083436 coachingos_subscription_enforcement_all_writes
20261118083523 coachingos_subscription_helper_privileges_and_concurrency
20261118084553 coachingos_subscription_lifecycle_reconcile
20261118084627 revoke_service_role_subscription_reconcile
20261118092844 guardian_sms_only_queue
20261118104705 guardian_sms_retry_queue_foundation

## Recovery limitations
This Git backup preserves the source tree at the recorded commit and the SQL snapshot preserves public database structure (tables/columns, policies, functions, triggers, constraints, indexes, extensions). It is NOT a full live-data backup. It excludes student/guardian records, auth users/sessions, storage file bytes, project secrets, and SMS provider credentials. Full point-in-time data recovery must rely on Supabase managed backups/PITR or an authorized database export. Never commit secrets or personal records to GitHub.

## Product-source inventory verified on 2026-11-18

- Backup branch contains all 30 files currently present on `main`, plus the two backup artifacts above (32 files total).
- Frontend/source HTML files: `index.html` (137,722 bytes; 2,223 lines) and `Chochings` (legacy-looking HTML file; retained unchanged pending owner review).
- Supabase SQL source: `supabase/schema.sql`, `supabase/FINAL_SETUP.sql`, and 25 files under `supabase/migrations/`.
- Edge Function source: `supabase/functions/guardian-attendance-notify/index.ts`.
- Live Edge Function inspected: `guardian-attendance-notify`, ACTIVE version 5, JWT verification enabled. Its source is present in GitHub.
- The live database migration history currently reports 15 applied migration entries. This is a separate count from the 25 SQL migration source files in the repository; do not assume every source file corresponds one-to-one with a currently recorded migration version.
- No `.github/workflows/` files, `supabase/config.toml`, package manifest/lockfile, or separate frontend asset directory were found in the current repository tree. The app appears to keep its main UI/code in the HTML file; this should be reviewed before claiming the deployment can be rebuilt from source alone.
- The public-schema snapshot is structural only. It does not contain tenant operational records or auth users, and it is not a complete Supabase project export.

## Recovery items not exportable through the connected read-only tools

- GitHub Actions secrets and Supabase project secrets (values) were not retrieved and must never be committed here. Only variable names/configuration references may be documented.
- Supabase dashboard-level Auth, API, Storage, network, billing, and project settings were not exported.
- Storage object bytes and any external provider account/configuration are not included.
- No independent restore test has been performed. This is a source/schema preservation checkpoint, not a verified full disaster-recovery package.


## Recovery documentation added on 2026-11-18

- `DEPLOYMENT_RECOVERY.md`: GitHub Pages and Edge Function deployment recovery checklist, verified facts, and deployment gaps.
- `SUPABASE_RECOVERY_AND_SECRETS.md`: Supabase dashboard configuration checklist and environment variable names/purpose only. No secret values are stored.
- `RESTORE_REHEARSAL_REPORT.md`: read-only verification results, blockers, and isolated staging restore acceptance criteria.
- These three documents are recovery instructions/inventory, not proof of a completed end-to-end restore.
- Full restore test remains pending an isolated staging Supabase project and confirmed GitHub Pages publishing configuration.
