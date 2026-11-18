# CoachingOS Supabase configuration & secret recovery inventory

Captured: 2026-11-18
Project: `Coachings`
Project ref: `ebbmcgbaxqkdzvpzopfl`
Project URL: https://ebbmcgbaxqkdzvpzopfl.supabase.co
Region: `ap-northeast-1`

## Secret-handling rules

- This file records variable names and purpose only. It intentionally contains no secret values.
- Never commit service-role keys, SMS API keys, database passwords, access tokens, SMTP passwords, or recovery codes.
- Do not paste secret values into ChatGPT, issues, pull requests, source files, or logs.
- Store values in the Supabase project's secret store / Edge Function secrets and GitHub Actions Secrets only when required by the actual deployment method.
- Keep an owner-controlled copy in a reputable password manager with MFA and recovery access. Limit access to the authorized project owner/adult administrator.
- Rotate a credential immediately if it is exposed; update the secure store and redeploy/restart the dependent service.
- Frontend variables are public by design. Only publishable/anon keys may be used in browser code; never put a service-role or secret key in frontend HTML or a `NEXT_PUBLIC_*` variable.

## Variable inventory

| Variable name | Used by | Classification / handling |
|---|---|---|
| `SUPABASE_URL` | Edge Function runtime | Project URL; configuration value, not a password |
| `SUPABASE_PUBLISHABLE_KEY` | Frontend `index.html` | Public browser key; safe for client use when RLS is correct |
| `SUPABASE_ANON_KEY` | Edge Function source | Public/anon client key; not a service credential |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function source | **Highly sensitive**; server-side secret only |
| `SMS_GATEWAY_URL` | Guardian SMS Edge Function | Provider endpoint configuration; keep in function secrets/config |
| `SMS_GATEWAY_API_KEY` | Guardian SMS Edge Function | **Highly sensitive**; provider credential |
| `SMS_SENDER_ID` | Guardian SMS Edge Function | Provider sender identity/configuration; may require provider approval |

The frontend source currently references `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. The Edge Function source references the runtime variables listed above. Confirm actual configured values/names in the Supabase Dashboard before a restore; source references do not prove a secret is currently configured.

## Supabase dashboard recovery checklist

Capture these settings manually from the authorized project dashboard. The connected tools did not export dashboard-level configuration.

- [ ] Authentication → URL Configuration: Site URL and allowed redirect URLs.
- [ ] Authentication → Providers: enabled providers and their non-secret configuration.
- [ ] Authentication → Email: templates, sender configuration, SMTP provider choice (credentials stored separately).
- [ ] Authentication → Security and sessions: password policy, leaked-password protection state, JWT/session lifetime settings.
- [ ] API / Data API: exposed schemas and any custom API configuration.
- [ ] Database: extensions required by migrations/functions, connection settings, and backup/PITR availability.
- [ ] Storage: bucket names, public/private status, size limits, MIME restrictions, and object policies. Object bytes require a separate export/backup.
- [ ] Edge Functions: deployed function names, versions, JWT verification settings, and required secret variable names.
- [ ] Network / CORS / allowed origins: capture configured origins and restrictions.
- [ ] Billing / plan: record the plan and backup/PITR retention capability; do not assume plan features.
- [ ] GitHub Pages: capture publishing source and domain/HTTPS settings in the deployment recovery document.
- [ ] SMS provider: record provider, sender ID approval, and account recovery route with the account owner. Do not put credentials here.

## Recovery order

1. Secure owner access to GitHub and Supabase accounts (MFA and recovery methods).
2. Restore frontend source and deployment settings.
3. Restore schema from reviewed migrations/snapshot into a separate test project.
4. Restore Edge Function source and configure its runtime secrets securely.
5. Restore Auth, Storage, API, and other dashboard settings from the owner-maintained checklist.
6. Run smoke/security tests in the isolated test project.
7. Only then plan a production recovery with explicit owner approval.

## Explicit exclusions

This is a product configuration inventory, not a copy of any institution's student/teacher operational records. It does not contain secret values, Auth users, Storage object bytes, SMS provider account data, or a complete project export.
