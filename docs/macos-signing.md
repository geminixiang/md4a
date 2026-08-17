# macOS Developer ID signing and notarization

`.github/workflows/macos-notarize.yml` is a manual template for outside-the-Mac-App-Store distribution. It cannot run on push or tags, requires typing `NOTARIZE`, and uses the protected `apple-developer-id-production` environment.

## One-time setup

1. Create a Developer ID Application certificate for the Apple team and export it as password-protected PKCS#12 (`.p12`).
2. Create an App Store Connect API key permitted to submit notarization requests.
3. Create the GitHub environment `apple-developer-id-production`, add required reviewers, and restrict deployment refs.
4. Add these environment secrets:
   - `APPLE_TEAM_ID`
   - `DEVELOPER_ID_CERTIFICATE_P12` (base64-encoded `.p12`)
   - `DEVELOPER_ID_CERTIFICATE_PASSWORD`
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_P8`
5. Never place certificates, private keys, or passwords in the repository.

Run **Actions → macOS Developer ID (manual)**, enter a version, type `NOTARIZE`, and approve the environment deployment. The workflow signs a universal app, submits it to Apple, staples the ticket, verifies it with Gatekeeper, and uploads a notarized ZIP artifact.

## Markdown default-app behavior

md4a registers the imported UTI `net.daringfireball.markdown` for `.md` and `.markdown`. The Welcome window offers an unobtrusive, one-time prompt. The user must press **Make Default…** and confirm before md4a calls the public macOS 12+ `NSWorkspace.setDefaultApplication` API. Settings provides the action later.

Changing a default handler can receive extra App Store review scrutiny even when the public API is used. Release notes and review notes should state that the action is user-initiated and reversible. If Launch Services rejects or does not report the change, direct users to Finder: select a Markdown file → **Get Info** → **Open with** → md4a → **Change All**. Never silently modify Launch Services or use deprecated/private APIs.
