# TestFlight release setup

TestFlight uploads are intentionally isolated in `.github/workflows/testflight.yml`. The workflow:

- runs only through `workflow_dispatch`;
- requires typing `UPLOAD`;
- targets the protected `apple-testflight-production` environment;
- relies on environment approval and secrets;
- never runs for pushes, tags, or pull requests.

## One-time Apple setup

1. Enroll the organization in the Apple Developer Program.
2. Create the iOS App ID `app.md4a.ios` and an App Store Connect app using the same bundle ID.
3. Confirm the app supports both iPhone and iPad.
4. In App Store Connect, create an API key with the minimum role needed to upload builds. Download its `.p8` once.
5. Configure automatic signing for the CI Apple team and accept any pending agreements.
6. Create the GitHub environment `apple-testflight-production`, add required reviewers, prevent self-review if appropriate, and restrict deployment branches/tags.
7. Add these **environment secrets** (never repository files):

   - `APPLE_TEAM_ID`
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_P8` (complete `.p8` text)

## Upload

Open **Actions → TestFlight (manual) → Run workflow**, enter a marketing version, type `UPLOAD`, then approve the protected environment deployment. The GitHub run number becomes `CFBundleVersion`, keeping every upload monotonically unique.

After processing in App Store Connect:

1. Complete export-compliance questions. md4a declares `ITSAppUsesNonExemptEncryption = NO` because it does not implement non-exempt encryption.
2. Complete App Privacy using the checked-in `PrivacyInfo.xcprivacy` as the source of truth. It declares no tracking/collected data and records the UserDefaults required-reason API used for local preferences.
3. Add internal testers first, then submit external beta review if needed.
4. Verify Files/Open In activation for `.md` and `.markdown` on physical iPhone and iPad. iOS does not support selecting md4a as the default app for arbitrary Markdown files, and md4a must not claim otherwise.

## Versioning

`MARKETING_VERSION` comes from the manual workflow input. `CURRENT_PROJECT_VERSION` comes from `github.run_number`. The defaults in `project.yml` are local-development placeholders only.
