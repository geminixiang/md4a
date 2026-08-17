## Downloads

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `md4a-*-macos-universal-unsigned.zip` | Universal Apple Silicon + Intel app. Unsigned and not notarized; Gatekeeper may block it. |
| Android | `md4a-*-android-debug.apk` | Installable beta APK signed with the standard Android debug key. Uninstall an older differently signed build first if Android reports a signature conflict. |
| Android | `md4a-*-android-unsigned.apk` | Unsigned release APK for signing/packaging validation; it is not directly installable. |
| Android / Play | `md4a-*-android-unsigned.aab` | Unsigned App Bundle for a later Play signing/upload flow. |
| Windows | `md4a-*-windows-x64-unpackaged.zip` | Unpackaged x64 WinUI app. Requires Windows App SDK and WebView2 Runtime. |
| Linux | `md4a-*-linux-ubuntu24.04-x86_64.tar.gz` | Ubuntu 24.04 x86_64 binary. Requires GTK 4, GtkSourceView 5, and WebKitGTK 6 runtime libraries. |
| Checksums | `SHA256SUMS.txt` | SHA-256 checksums for every attached package. |

## iPhone and iPad

There is no IPA attached. CI verifies the native iOS target, but an installable IPA requires Apple distribution signing and provisioning. A Simulator build is intentionally not published as a release package.

## Status

This is a beta release. The Android debug APK is installable for device testing; other packages remain unsigned/ad-hoc development artifacts and are not App Store, Play Store, Microsoft Store, or Linux repository submissions.
