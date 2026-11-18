# CoachingOS deployment recovery checklist

Captured: 2026-11-18
Repository: https://github.com/joypaul3164-ctrl/CoachingOS
Recovery branch: `backup/pre-security-2026-11-18`
Production branch: `main`
Static app URL: https://joypaul3164-ctrl.github.io/CoachingOS/
Supabase project ref: `ebbmcgbaxqkdzvpzopfl`
Supabase project URL: https://ebbmcgbaxqkdzvpzopfl.supabase.co
Supabase region: `ap-northeast-1`

## Verified deployment facts

- Production Supabase project was readable and reported `ACTIVE_HEALTHY` on 2026-11-18.
- Database engine: PostgreSQL 17; reported version `17.11.0.019`.
- GitHub Pages app URL and repository are recorded above.
- The backup branch contains the source HTML, SQL schema/migrations, and the guardian SMS Edge Function source.
- Live Edge Function `guardian-attendance-notify` is ACTIVE, version 5, with JWT verification enabled.
- No `.github/workflows/` directory or workflow YAML is present in the inspected repository tree. The previously observed successful Actions run does not itself provide a reusable deployment workflow file.

## Restore frontend / GitHub Pages

1. Confirm the GitHub repository and access permissions with the project owner.
2. Preserve the current production branch before changing anything.
3. Inspect GitHub repository **Settings → Pages** and record the actual publishing source (branch/folder or Actions workflow), custom domain setting if any, and HTTPS setting. These dashboard settings were not exportable through the connected read-only tools.
4. If Pages uses branch/folder publishing, select the verified production branch and configured folder; do not assume this without checking Settings → Pages.
5. If Pages uses Actions, recover the original workflow YAML from the repository history or recreate it only after confirming the intended build/publish process. The current backup does not contain a workflow file.
6. Restore the frontend source from this branch only after review; deploy to a preview/staging target first where possible.
7. Verify the published page loads, CSS and JavaScript load without syntax errors, login and password-reset controls respond, and browser console/network requests show no unexpected failures. Do not use real customer accounts for smoke tests.
8. Promote to production only after the staging smoke test passes and an owner approves.

## Restore Supabase Edge Function

1. Confirm the target project ref is exactly `ebbmcgbaxqkdzvpzopfl`; do not deploy to any other project.
2. Review `supabase/functions/guardian-attendance-notify/index.ts` and its migration prerequisites.
3. Recreate the required function secrets in the Supabase Dashboard or secure CLI environment (see `SUPABASE_RECOVERY_AND_SECRETS.md`). Never paste secret values into chat or commit them.
4. Deploy the function source to a non-production test project first, preserving `verify_jwt=true`.
5. Test unauthorized requests are rejected and valid test-user requests are scoped to the correct institute. Do not send live SMS during restore testing.
6. Deploy to production only after the test project passes and the project owner approves.

## Deployment configuration still requiring owner capture

- GitHub Settings → Pages: publishing source, branch/folder or workflow, custom domain, HTTPS.
- GitHub Actions: workflow definitions, variables, and secret *names* (not values), if Actions is actually used.
- Supabase: Auth URL configuration, enabled providers, redirect URLs, email templates/SMTP choice, JWT/session settings, API/Data API settings, Storage buckets and policies, Edge Function settings, allowed origins/network settings, and any custom domains.
- External SMS provider: provider name, API endpoint format, sender ID registration state, account owner, and secret variable names. Do not record provider passwords/API key values here.

## Rollback / safety

- Keep the production branch and current production project unchanged during rehearsal.
- Do not run schema restore or destructive SQL against production as a test.
- If a deployment fails, restore the previously verified frontend commit and redeploy using the captured Pages publishing method.
- Database rollback must use a tested migration rollback or a separate project restore; do not blindly replay old SQL over a live database.
