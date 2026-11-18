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
