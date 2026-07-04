# Store account setup

One-time account/console setup for both stores. App-level values (bundle id,
package name, keystore) are derived at runtime by the scripts from `app.json`;
this doc covers the manual console steps the scripts open for you.

## Apple — App Store Connect API key (account-level)

One API key authenticates uploads for your entire Apple account — reuse it
across every app.

1. Go to https://appstoreconnect.apple.com/access/integrations/api (Users and
   Access → Integrations → App Store Connect API).
2. Create a key with the **App Manager** role (sufficient for uploads).
3. Record the **Key ID** and **Issuer ID**.
4. Download the `.p8` key file (you can only download it once). Store it at
   `~/.private_keys/AuthKey_<KEY_ID>.p8`.
5. Fill `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_PATH`, and
   `APPLE_TEAM_ID` in `.env` (Team ID is under
   https://developer.apple.com/account → Membership, and should also be set in
   `app.json` → `expo.ios.appleTeamId`).

`upload:ios` copies the `.p8` into `~/.private_keys/AuthKey_<KEY_ID>.p8` so
`xcrun altool` can find it, then uploads the archive to TestFlight. The build
does **not** go live until you submit it in App Store Connect.

## Google Play — service account / API access (corrected flow)

**The Play Console "API access" page has been REMOVED.** Service accounts are
now created and managed in **Google Cloud Console**, then granted access inside
Play Console. Uploading `.aab` files with this skill is **manual** (Play Console
web UI), so this service-account setup is only needed if you later build your own
API-based upload automation — but if you do, this is the current, correct flow:

1. **Create / select a Google Cloud project:**
   https://console.cloud.google.com/projectcreate
2. **Enable the Google Play Android Publisher API** for that project:
   https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com
   — confirm the correct project is selected, then click **Enable**.
3. **Create a service account:**
   https://console.cloud.google.com/iam-admin/serviceaccounts → **Create service
   account**. Name it e.g. `play-upload`; **Create and continue**; **skip** Cloud
   IAM roles; **Done**.
4. **Create a JSON key:** the service account → Actions (⋮) → **Manage keys** →
   **Add key** → **Create new key** → **JSON**. Save the downloaded `.json`
   somewhere safe.
5. **Grant access in Play Console** → Users and permissions
   (https://play.google.com/console/users-and-permissions) → **Invite new user**.
   Enter the service account email (`…@….iam.gserviceaccount.com`) and grant
   **least privilege**:
   - **View app information (read-only)**
   - **Release apps to testing tracks**
   - (Only if the bot must auto-publish to production: **Release to production,
     exclude devices, and use Play App Signing**.)
   Do **not** grant Admin, Manage store presence, or financial permissions.

Note: for a brand-new app the API only accepts uploads once an **initial release
exists** — upload your first release manually in the Console.

## Google Play — app + listing (app-level)

1. Create the app at https://play.google.com/console → **Create app** (name =
   `app.json` → `expo.name`, default language English, App, Free).
2. Complete the listing form. A workable answer pattern for a typical utility
   app:
   - **App category / type:** the closest matching category; App (not Game).
   - **Content rating:** complete the questionnaire honestly; most simple
     utilities land at Everyone / PEGI 3.
   - **Data safety:** declare exactly what you collect; if the app stores data
     only on-device, declare no collection/sharing.
   - **Target audience:** select the real age range; avoid "children" unless you
     intend to meet Families policy.
   - **Ads:** declare whether the app contains ads.
   - **Privacy policy:** required — provide a hosted URL.
3. Set up at least one **testing track** before the first `upload:android` (the
   script builds a signed `.aab` and walks you through uploading it).

## App-level signing (both platforms)

- **iOS:** automatic signing via Xcode + your Team ID. `setup:ios` walks through
  registering a device and enabling "Automatically manage signing".
- **Android:** a per-app upload keystore, generated automatically on first
  `upload:android` (or `setup:android`) at
  `~/.private_keys/android/<app-slug>-upload-keystore.jks`. **Back it up** — it
  cannot be regenerated, and losing it means you can only recover via Google Play
  support. Enrolling in Play App Signing (default for new apps) lets Google
  re-sign with the app signing key while you keep only the upload key.
