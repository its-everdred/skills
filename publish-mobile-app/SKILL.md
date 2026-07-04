---
name: publish-mobile-app
description: Bootstrap an app-agnostic set of deploy scripts into an Expo React Native + web project and run the full lifecycle of publishing a mobile app to both the Apple App Store (TestFlight) and Google Play, plus store-screenshot capture.
---

# Publish Mobile App

A skillset for every step of shipping a mobile app to **both** the Apple App
Store and Google Play. It generalizes a working set of deploy/screenshot scripts
(originally from an Expo React Native + Vite web monorepo) into reusable,
app-agnostic form, and ships an `install.sh` that drops them into any project and
wires the npm commands.

All app identity is **derived at runtime** from the project's `app.json`
(`expo.name`, `expo.slug`, `expo.ios.bundleIdentifier`, `expo.android.package`,
`expo.ios.appleTeamId`) and from `.env` — nothing app-specific is hardcoded. The
Android upload keystore is namespaced per app slug so two apps never collide on
one key.

## Use when

- The developer wants to set up App Store / TestFlight and Google Play publishing
  for an Expo React Native app (typically in a `mobile/` subdirectory of a web
  monorepo), from scratch or on a new machine.
- They ask to build and upload an iOS TestFlight build or a signed Android `.aab`.
- They want to capture App Store / Play Store marketing screenshots from a web
  `?shot=1` mode.
- They want to bump the app version / build numbers before a release.

## Procedure

The lifecycle runs from `install` → `.env` → per-platform setup+upload →
screenshots → version bumps. The scripts are interactive and safe to re-run.

1. **Install into the project.** From the target project root:

   ```bash
   /path/to/publish-mobile-app/install.sh --mobile-dir mobile
   ```

   Preview first with `--dry-run`. This copies the deploy scripts into
   `<project>/mobile/scripts/`, the screenshot runner into `<project>/scripts/`,
   a `.env.example` into `<project>/mobile/` (only if absent), and adds npm
   scripts (`setup:env`, `setup:ios`, `setup:android`, `ios`, `upload:ios`,
   `upload:android` to the mobile package; `shots` to the root package) without
   clobbering existing scripts. It is idempotent.

2. **Fill in `.env`.** From the mobile dir:

   ```bash
   cd mobile && npm run setup:env   # creates .env from .env.example
   ```

   Then edit `.env`. The **account-level** Apple values
   (`APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_PATH`,
   `APPLE_TEAM_ID`) are the same for every app and can be copied from a sibling
   project. The **app-level** Android keystore is unique per app — leave its
   password fields empty to have it generated automatically. See
   `/path/to/publish-mobile-app/references/store-setup.md` for obtaining the
   Apple API key. Confirm `app.json` has `expo.name`, `expo.slug`,
   `expo.ios.bundleIdentifier`, `expo.android.package`, and
   `expo.ios.appleTeamId`.

3. **iOS: setup + upload.** iOS builds require macOS + Xcode.

   ```bash
   npm run setup:ios      # toolchain preflight, expo prebuild, optional signing
   npm run upload:ios     # bump, archive, export, upload to TestFlight
   ```

   `setup:ios` runs `doctor-ios.sh` (installs missing simulator platforms),
   generates the native `ios/` project, and optionally walks through Xcode
   signing (needed only for device/TestFlight, not the Simulator). `upload:ios`
   bumps the version, cleans+prebuilds, generates `ExportOptions.plist` from the
   runtime Team ID + bundle id, archives with `xcodebuild`, and uploads with
   `xcrun altool`. The build will **not** go live until you submit it in App
   Store Connect.

4. **Android: setup + upload.**

   ```bash
   npm run setup:android  # create Play app, (optional) service account, keystore
   npm run upload:android # bump, prebuild, sign, build .aab, print upload steps
   ```

   `setup:android` opens the Play Console, documents the corrected Google Cloud
   service-account flow (optional; Play uploads here are manual), and generates
   the per-app upload keystore at
   `~/.private_keys/android/<app-slug>-upload-keystore.jks`, writing its random
   passwords back into `.env`. `upload:android` builds a signed `.aab` into
   `releases/` and prints step-by-step Play Console upload instructions. Play
   uploads are **manual** — no Google service-account key is required.

5. **Store screenshots.** With the app's `?shot=1` web build served locally, from
   the project root:

   ```bash
   npm run shots
   ```

   The runner (`shots.mjs`) drives `?shot=1&screen=..&theme=..&accent=..&layout=..`
   and writes on-spec PNGs to `store-screenshots/`. The shot list is read from an
   optional `shots.config.json`; the app-side shot mode is app-specific. See
   `/path/to/publish-mobile-app/references/screenshots.md`.

6. **Version bumps.** Both upload scripts call `bump-version.sh` automatically,
   but you can run it directly:

   ```bash
   cd mobile && bash scripts/bump-version.sh [major|minor|patch|overwrite]
   ```

   It updates `app.json` (`version`, `android.versionCode`, `ios.buildNumber` in
   lockstep) and `package.json`. `overwrite` keeps the marketing version but
   increments the build number so TestFlight accepts a rebuild.

## Scripts

Installed into `<project>/mobile/scripts/` (screenshot runner into
`<project>/scripts/`):

- `/path/to/publish-mobile-app/scripts/setup-ios.sh` — one-time iOS onboarding: toolchain preflight, `expo prebuild`, optional Xcode signing.
- `/path/to/publish-mobile-app/scripts/doctor-ios.sh` — non-interactive iOS toolchain diagnostics; auto-installs missing iOS/watchOS simulator platforms.
- `/path/to/publish-mobile-app/scripts/run-ios.sh` — dev entrypoint (`npm run ios`); first-run onboarding gate, then `expo run:ios`.
- `/path/to/publish-mobile-app/scripts/generate-export-options.sh` — writes `ios/ExportOptions.plist` from the runtime Team ID + bundle id.
- `/path/to/publish-mobile-app/scripts/upload-ios.sh` — bump → prebuild → archive → export → upload to TestFlight.
- `/path/to/publish-mobile-app/scripts/setup-android-upload.sh` — Play Console + optional service-account docs + per-app keystore generation.
- `/path/to/publish-mobile-app/scripts/upload-android.sh` — bump → prebuild → sign → build `.aab` → manual Play upload instructions.
- `/path/to/publish-mobile-app/scripts/fix-android-signing.js` — patches `android/app/build.gradle` to use the release signing config.
- `/path/to/publish-mobile-app/scripts/bump-version.sh` — bumps `app.json`/`package.json` version + build numbers.
- `/path/to/publish-mobile-app/scripts/shots.mjs` — Playwright store-screenshot capture driving `?shot=1` web mode.

Templates and references:

- `/path/to/publish-mobile-app/templates/.env.example` — account-level vs app-level deploy-credential template.
- `/path/to/publish-mobile-app/references/store-setup.md` — Apple API key + corrected Google Play service-account/API flow + listing answers.
- `/path/to/publish-mobile-app/references/screenshots.md` — the `?shot=1` pattern, `shots.config.json` shape, and store size/aspect specs.

## Dependencies

- `expo` / `eas` CLI (via `npx expo`) — prebuild and run.
- `xcodebuild`, `xcrun altool` — iOS archive/export/upload (macOS + Xcode only).
- `keytool`, `openssl` — Android upload keystore generation.
- `node` + `python3` — JSON edits in `bump-version.sh` and `install.sh`.
- `sips` — image resizing (if you post-process screenshots).
- Playwright — screenshot capture (`PLAYWRIGHT_PATH` if it lives in the npx cache).

## Notes / gotchas

- **iOS is macOS-only.** `doctor-ios.sh` aborts on non-Darwin and installs
  missing simulator platforms (`SKIP_PLATFORM_DOWNLOAD=1` to opt out). It also
  installs the watchOS platform when the app embeds an Apple Watch companion
  (detected via `withWatchApp` in `app.json` or a native `*Watch*` target).
- **The Android upload key is irreplaceable.** It is generated once at
  `~/.private_keys/android/<app-slug>-upload-keystore.jks`, its passwords are
  written to `.env`, and the scripts **never** overwrite an existing keystore.
  Back up both the file and `.env`. Losing the key means recovery only via Google
  Play support.
- **Play uploads are manual** by design — `upload:android` builds and signs the
  `.aab` and prints Play Console steps. There is no `GOOGLE_SERVICE_ACCOUNT_KEY_PATH`
  variable; the service-account docs are only for building your own automation
  later.
- **Neither store goes live automatically.** iOS must be submitted from App Store
  Connect after processing; Android needs a production release created from the
  Production track after closed testing.
- **Version/build lockstep:** `bump-version.sh` keeps `ios.buildNumber` equal to
  `android.versionCode` so an `overwrite` rebuild still uploads a unique build
  number (TestFlight rejects a reused version+build pair).
- **The screenshot harness is the least generalizable piece.** The runner is
  generic, but the `?shot=1` mode and `shots.config.json` (screens, accents,
  selectors) are app-specific and must be supplied per app.
- `install.sh` never clobbers existing npm scripts — it warns and skips any key
  already present in `package.json`.
