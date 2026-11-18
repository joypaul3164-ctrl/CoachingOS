# CoachingOS Android / Google Play preparation

The web app is being prepared as an installable Progressive Web App (PWA). The Android Play Store package should use a Trusted Web Activity (TWA) so the Android app displays the same HTTPS CoachingOS application and Supabase-backed account data.

**Proposed Android application ID:** `com.joypaul3164.coachingos`

## Required before building a signed Play Store AAB

1. Publish the PWA on its final HTTPS production domain.
2. Confirm the final production URL and keep it stable.
3. Generate the Android TWA project from the published Web App Manifest with Bubblewrap or PWABuilder.
4. Create and securely store the Android upload/signing key. Never commit the keystore or passwords to Git.
5. Add the generated Digital Asset Links statement at `/.well-known/assetlinks.json` using the final package name and SHA-256 certificate fingerprint.
6. Build and test the signed Android App Bundle (AAB) on real Android devices.
7. Complete Play Console app content, privacy policy, data safety, target audience, screenshots, and testing-track requirements.
8. Upload the AAB to Play Console and submit it for review.

## Security notes

- Supabase URL and publishable/anon key may be used by the browser client; never put a Supabase service-role key in the app.
- Tenant isolation remains enforced by Supabase Row Level Security and membership-aware policies. Client-side institute filters are not a security boundary.
- The service worker caches only the static app shell. It deliberately does not cache Supabase API responses, authentication tokens, or institute records.
- A signed Play Store AAB and verified Digital Asset Links cannot be completed until the final production domain, Android package ID, and signing certificate are known.
