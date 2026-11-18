# CoachingOS Multi-Tenant Security Audit — 2026-11-18

## Scope and safety
- Target: production Supabase project `ebbmcgbaxqkdzvpzopfl` (Coachings).
- This audit was read-only. No production schema, policy, data, Auth, or deployment settings were changed.
- No customer records or personal data were queried.
- A separate staging project and real two-institute account test are not available yet.

## Verified results

### RLS coverage
- All 12 public base tables have Row Level Security enabled.
- The primary tenant data table `coachingos_records` has SELECT, INSERT, UPDATE, and DELETE policies.
- Its policies call role-aware helper functions and scope by `institute_id` and `record_type`.
- Membership and institute access are controlled by authenticated-user policies.
- Five tables have RLS enabled but no direct RLS policies:
  - `institute_invitations`
  - `institute_notifications`
  - `institute_portal_links`
  - `institute_staff_audit_logs`
  - `institute_staff_invitations`
- This is currently a deliberate private-table/RPC pattern: direct SELECT/INSERT/UPDATE/DELETE privileges for both `anon` and `authenticated` are absent on those five tables. Access is mediated by narrowly scoped SECURITY DEFINER RPCs and/or triggers. Do not add broad policies to silence the linter.

### Anonymous and non-member checks
Read-only simulated checks were run inside rolled-back transactions:
- Anonymous role saw 0 rows from `coachingos_records`, `institute_members`, `institutes`, and `subscription_plans`.
- A simulated authenticated UUID with no institute membership received `false` from both record view/manage helpers and saw 0 rows from records, memberships, and institutes.
- These are negative-access smoke tests only; they do not replace tests with two real authenticated institute accounts.

### SECURITY DEFINER functions
- Supabase Security Advisor reports 29 SECURITY DEFINER functions executable by `authenticated`.
- The reviewed function metadata shows an empty `search_path` on these functions.
- The exposed RPCs are intentionally callable by signed-in users, with internal membership/role, recipient, invitation-token, or platform-admin checks depending on the function.
- Anonymous execution was false for the reviewed SECURITY DEFINER function set.
- The Advisor warning remains useful: each RPC must continue to enforce authorization internally. Do not blanket-revoke authenticated EXECUTE privileges because the application uses these RPCs.

### Other Security Advisor finding
- Leaked Password Protection is disabled. This is an Auth dashboard configuration item and was not changed during this read-only audit. An authorized project owner should enable it after reviewing Auth settings.

## Remaining verification
1. Test with two separate synthetic institute accounts: cross-institute SELECT, INSERT, UPDATE, and DELETE must all be denied.
2. Test each role (owner, admin, manager, teacher, accountant, receptionist, staff) against the intended record-type permissions.
3. Test portal account linking and confirm each student/guardian sees only explicitly linked student data.
4. Test staff invitation create/accept/revoke flows, including expired and wrong-contact invitations.
5. Review all 29 SECURITY DEFINER RPCs again whenever their definitions or grants change.
6. Enable Leaked Password Protection through the authorized project owner's Auth settings.

## Current conclusion
The production schema currently has RLS enabled on every public table inspected, and the read-only negative-access smoke tests passed. The five no-policy tables are private by grants, not open tables. The Security Advisor's 29 SECURITY DEFINER warnings are not proof of a bypass, but remain items for ongoing authorization review. Full tenant-isolation acceptance is **not yet certified** until two real synthetic institute accounts complete the cross-tenant test matrix.
