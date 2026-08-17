## Downloads

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `md4a-*-macos-universal-unsigned.zip` | Universal Apple Silicon + Intel app. Unsigned and not notarized; Gatekeeper may block it. |
| Android | `md4a-*-android.apk` | Universal APK signed with the protected production upload key; intended for controlled direct testing. |
| Android / Play | `md4a-*-android.aab` | Upload-key-signed App Bundle for Play Console internal testing and release. |
| Windows | `md4a-*-windows-x64-setup-signed.exe` / `*-unsigned.exe` | Small x64 web installer. Downloads official Microsoft prerequisites only when missing; includes shortcuts, Markdown associations, and an uninstaller. Prefer the signed production artifact. |
| Windows portable | `md4a-*-windows-x64-unpackaged.zip` | Diagnostic unpackaged files. Requires Windows App Runtime and WebView2 Runtime; not the recommended tester download. |
| Linux | `md4a-*-linux-ubuntu24.04-x86_64.tar.gz` | Ubuntu 24.04 x86_64 binary. Requires GTK 4, GtkSourceView 5, and WebKitGTK 6 runtime libraries. |
| Checksums | `SHA256SUMS.txt` | SHA-256 checksums for every attached package. |

## iPhone and iPad

There is no IPA attached. CI verifies the native iOS target, but an installable IPA requires Apple distribution signing and provisioning. A Simulator build is intentionally not published as a release package.

## Status

This is a beta release. Android artifacts are built only inside the protected `android-production` GitHub Environment, certificate-verified, and install-smoke-tested; no debug or unsigned APK is published. Other packages remain unsigned/ad-hoc development artifacts and are not App Store, Microsoft Store, or Linux repository submissions.
