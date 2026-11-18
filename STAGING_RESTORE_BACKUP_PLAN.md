# CoachingOS staging restore backup plan

Created: 2026-11-18
Purpose: preserve both the clean pre-restore baseline and the verified post-restore staging state.

## Important status

This is a backup plan and baseline reference, not a claim that a staging project already exists or that a restore has been run. No new Supabase project has been created by this task. Production project `ebbmcgbaxqkdzvpzopfl` remains untouched.

## A. Before-restore backup (baseline)

The following existing immutable/recoverable references form the pre-restore baseline:

- GitHub source branch: `backup/pre-security-2026-11-18`
- Supabase public schema snapshot: `supabase/backups/pre-security-2026-11-18-public-schema.json`
- SQL source: `supabase/schema.sql`, `supabase/FINAL_SETUP.sql`, and `supabase/migrations/`
- Edge Function source: `supabase/functions/guardian-attendance-notify/index.ts`
- Recovery docs: `DEPLOYMENT_RECOVERY.md`, `SUPABASE_RECOVERY_AND_SECRETS.md`, `RESTORE_REHEARSAL_REPORT.md`
- Baseline source commit: `20a621335cec8a38b69cdce330a4cfa59ee0b432`

Before any staging restore begins:
1. Create a separate Supabase staging project under the authorized owner account.
2. Confirm project ref and region; label it clearly as STAGING.
3. Export/capture its initial empty schema/configuration state and record timestamp/project ref.
4. Keep production credentials and SMS provider credentials out of staging unless strictly required; use synthetic data and mocked/no SMS delivery.
5. Do not run restore commands against production.

## B. After-restore backup (staging checkpoint)

Only after a staging restore succeeds:
1. Export the resulting staging schema and migration history.
2. Save a staging-specific schema snapshot under `supabase/backups/staging-<date>-schema.json`.
3. Record exact Git commit, migration versions, Edge Function names/versions, JWT verification flags, non-secret configuration, and test results.
4. Export Storage objects only if test fixtures exist and are safe to retain; do not copy customer data.
5. Create a Git tag such as `staging-restore-<date>` only after the project owner approves and the test suite passes.
6. Keep the pre-restore baseline unchanged; never overwrite it with the post-restore checkpoint.

## C. Acceptance criteria before marking post-restore backup complete

- [ ] Staging project is isolated from production.
- [ ] Source deploy succeeds from the recorded Git commit.
- [ ] Database schema, RLS, grants, functions, triggers, indexes and constraints match the approved baseline.
- [ ] Migration history is reconciled; do not blindly replay all 25 repository SQL files when production reports 15 applied migration entries.
- [ ] Tenant isolation tests pass using synthetic institutes/users.
- [ ] Subscription limits and authorization checks pass.
- [ ] Edge Function JWT and membership checks pass.
- [ ] SMS provider is mocked/disabled; no real messages are sent.
- [ ] Auth redirect, Storage policies and frontend smoke tests pass.
- [ ] Post-restore schema export and test report are committed separately.

## D. Current status

- [x] Pre-restore product baseline is preserved in the existing Git backup branch and schema snapshot.
- [x] This two-checkpoint staging backup plan is committed.
- [ ] Staging Supabase project created by authorized owner.
- [ ] Initial empty-staging checkpoint captured.
- [ ] Restore rehearsed in staging.
- [ ] Post-restore staging checkpoint exported and committed.
- [ ] Restore acceptance tests passed.

## Safety boundary

No production database restore, destructive SQL, live SMS, or production configuration change is part of this plan. Secret values and institution operational records must not be committed to GitHub.
