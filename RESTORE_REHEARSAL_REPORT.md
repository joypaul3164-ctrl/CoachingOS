# CoachingOS restore rehearsal report

Date: 2026-11-18
Target: isolated restore rehearsal plan for product source/configuration
Production project: `ebbmcgbaxqkdzvpzopfl`

## Checks completed (read-only)

- [x] Backup branch exists and was inspected.
- [x] Frontend entry file `index.html` is present in the backup branch.
- [x] SQL source files and schema snapshot are present.
- [x] 25 SQL migration source files were counted in the repository tree.
- [x] Live Supabase migration history was queried and returned 15 applied entries.
- [x] Edge Function source is present in GitHub.
- [x] Live `guardian-attendance-notify` function reports ACTIVE version 5 and `verify_jwt=true`.
- [x] Production project metadata was read: ACTIVE_HEALTHY, PostgreSQL 17.11.0.019, region ap-northeast-1.
- [x] Secret names and their consumers were inventoried without retrieving secret values.
- [x] Deployment/recovery gaps were documented.

## Restore test status

**NOT RUN — full restore is not yet safely testable with the currently available setup.**

No isolated Supabase staging project or separate Pages preview deployment was identified. Replaying schema/migrations against production would be unsafe and is explicitly not part of this test. No end-to-end restore has been claimed.

## Blocking prerequisites

- [ ] Authorized owner creates/provides an isolated Supabase staging project.
- [ ] Confirm the intended restore baseline and reconcile the 25 repository SQL migration files with the 15 migration-history entries in production. Do not blindly replay all files.
- [ ] Confirm required extensions, roles/grants, Auth settings, Storage buckets/policies, and Edge Function secrets.
- [ ] Recover the actual GitHub Pages publishing source; the repository currently contains no `.github/workflows/` directory.
- [ ] Set secrets directly in the staging project's secure secret store; never send them through chat or commit them.
- [ ] Use synthetic test records only. Keep SMS provider unset or mocked so no real messages can be sent.

## Staging restore acceptance criteria

- [ ] Frontend builds/serves at the preview URL with no JavaScript syntax errors.
- [ ] Login, logout, password-reset UI, and protected-route behavior pass with test accounts.
- [ ] Database schema, indexes, constraints, RLS policies, grants, functions, and triggers match the approved snapshot/migration baseline.
- [ ] Tenant isolation test confirms one test institute cannot read or mutate another test institute's records.
- [ ] Subscription gating and record/member/branch limits pass safe synthetic tests.
- [ ] Edge Function rejects missing/invalid JWT and unauthorized institute membership.
- [ ] Edge Function queues/no-ops when SMS provider secrets are absent; no live SMS is sent.
- [ ] Storage access and Auth redirect settings match the dashboard checklist.
- [ ] Recovery from a deliberately broken staging deployment is demonstrated using the documented rollback path.

## Result

Source/configuration inventory and recovery documentation are saved in the backup branch. **Disaster recovery readiness remains partial until an isolated staging restore passes every acceptance criterion.**
