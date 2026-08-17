# Default Markdown handler and production signing/distribution research

_Status: 2026-04-20. Scope: Android 8–15/16, iOS/iPadOS, macOS, Windows 10/11, and Linux. Sources are first-party platform documentation/specifications only._

## Executive decision

md4a should **register as capable of opening Markdown everywhere**, then make any first-run request a dismissible, one-time explanation. It must never silently overwrite a user's existing default.

| Platform | Can md4a ask? | Exact recommended UX |
|---|---|---|
| Android | Yes, but there is no Markdown “role” or direct set-default API. | Register `ACTION_VIEW`; show “Make md4a your Markdown app?” once, with **Try it** (launch an `.md` through `ACTION_VIEW` so Android's resolver/chooser owns the choice) and **Not now**. Optionally offer **Open Default apps settings**, explaining the user may need to open a Markdown file and select md4a → **Always**. |
| iOS/iPadOS | No arbitrary document-default facility exists. | Do **not** ask to become the default. Say “Open Markdown with md4a” and teach Files: Share/Open In → md4a. Declare Markdown document types so md4a is offered. |
| macOS | Yes; the supported user-facing route is Finder's **Get Info → Open with → Change All**. macOS 12+ also has an AppKit API for changing a content type's default, but explicit informed consent is essential. | Prefer a one-time dialog with **Show me how** (open/reveal a sample `.md`, then concise Finder steps) and **Not now**. A direct **Make Default** button may call `NSWorkspace.setDefaultApplication(...toOpenContentType...)` only after this explicit click; report errors and provide Finder fallback. |
| Windows | Yes, but Windows 10/11 require the user to make the choice in system UI. | Register `.md`/ProgID or MSIX association. One-time dialog: **Open Default Apps** and **Not now**. Deep-link to md4a's Default Apps page where supported; otherwise `ms-settings:defaultapps`. Tell the user to choose md4a for `.md`. |
| Linux | Technically yes via `xdg-mime default`, but desktop behavior/policy varies. | Register the desktop file/MIME capability. Ask once with **Make Default**, **Open system settings** (when available), **Not now**. If the user explicitly clicks Make Default, `xdg-mime default md4a.desktop text/markdown` is acceptable; first query and disclose the current handler, verify afterward, and provide DE instructions on failure. |

The prompt must not block document opening, repeatedly nag, preselect consent deceptively, or claim success without querying/verifying the resulting association.

## Android 8 through 15/16

### Capability and system-owned choice

An exported activity can advertise `ACTION_VIEW`, `CATEGORY_DEFAULT`, and MIME types in an `<intent-filter>`. Data tests are combined within one filter, so separate filters should be used when combinations differ. Android's documentation recommends MIME type plus URI when possible; `content:` and `file:` are inferred when only a MIME type is present. Register the real Markdown MIME types (`text/markdown`, legacy aliases if interoperability testing justifies them) and extension-aware URI patterns, while recognizing that providers often report `.md` as `text/plain` or `application/octet-stream`. Broad `text/plain` registration makes md4a a candidate for every text file and should only be retained if the app truly supports that contract.

Source: [Intents and intent filters](https://developer.android.com/training/basics/intents/filters) and [`<data>` manifest element](https://developer.android.com/guide/topics/manifest/data-element).

When several activities match an implicit intent, Android presents its resolver. `Intent.createChooser()` explicitly forces chooser UI and does not itself establish md4a as default. Android's user-visible **Always/Just once** affordance is the compliant ownership boundary; exact behavior varies by release and device vendor.

Source: [Sending the user to another app](https://developer.android.com/training/basics/intents/sending) and [`Intent.createChooser`](https://developer.android.com/reference/android/content/Intent#createChooser(android.content.Intent,%20java.lang.CharSequence)).

`RoleManager` does **not** define an arbitrary-document/MIME-handler role. Its predefined roles include browser, dialer, home, SMS, notes, wallet, etc.; a role request requires a defined/available role and user consent. Therefore md4a must not misuse `ROLE_NOTES` or another role to claim Markdown.

Source: [`RoleManager`](https://developer.android.com/reference/android/app/role/RoleManager).

Settings entry points:

* `Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS` (API 24+) opens the general Default apps screen.
* `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` (API 9+) opens app details for `package:<id>` but is not a promise of a Markdown association control.
* `Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS` concerns supported web links/open-by-default behavior, not arbitrary document MIME defaults; do not present it as the `.md` solution.
* Settings intents may lack a matching activity, so guard resolution/failure.

Source: [`Settings` actions](https://developer.android.com/reference/android/provider/Settings).

**Prohibited/avoid:** no unsupported role request; no package-manager hacks; no clearing another app's defaults; no automatic chooser loop; no claim that the app can force itself as default. Do not use `ACTION_OPEN_DOCUMENT` as a default-setting mechanism—it is a picker contract.

### Signing and Play release

Every APK must be signed. For Google Play, use Play App Signing: Google protects the app-signing key used for distributed APKs, while the developer signs uploads with a separate upload key. New apps publish with Android App Bundles; keep the upload key secret and backed up, and configure release signing outside source control. An APK signed with a different certificate cannot update an installed package with the same application ID, explaining a common immediate “App not installed” result when moving between debug and release builds.

Sources: [Sign your app](https://developer.android.com/studio/publish/app-signing) and [About Android App Bundles](https://developer.android.com/guide/app-bundle).

Release recommendation: Play production/internal testing via AAB + Play App Signing; separately distributed APKs must use one stable production/beta signing lineage, be tested with `apksigner verify`, and be install/upgrade-smoke-tested from the prior public build.

## iOS and iPadOS

Apple's current Default Apps settings enumerate specific features (browser, email, calling, messaging, keyboards, passwords, translation, and region-specific categories). **Arbitrary document types are not a default-app category**, so no API or Settings route can make md4a the global `.md` default.

Source: [Apple Support: Change your default apps for features on iPhone and iPad](https://support.apple.com/en-us/121430).

md4a should declare imported/exported Markdown UTTypes and `CFBundleDocumentTypes`, implement document opening, and support Files/document-browser workflows. This makes md4a available through Files/Open In/share flows but does not grant default status.

Sources: [`CFBundleDocumentTypes`](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes), [Defining file and data types for your app](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app), and [Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories).

**Exact UX:** never display “Make md4a default.” A help item may say: “To open a Markdown file in md4a, in Files touch and hold the file, choose Share, then md4a” (wording should be validated on supported OS versions). Do not redirect to the Default Apps screen for `.md`; it cannot fulfill the promise.

### Signing and distribution

Distribution through TestFlight/App Store requires Apple Developer Program membership, App Store Connect records, signing identities/certificates, an explicit App ID/provisioning, and an uploaded archive/build. TestFlight builds are beta-reviewed as applicable and expire after 90 days. Use automatic signing in CI only with appropriately scoped App Store Connect credentials; protect distribution certificates/keys and test install/launch through TestFlight, not an unsigned IPA.

Sources: [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [Distribute an app using TestFlight](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), and [Certificates overview](https://developer.apple.com/help/account/certificates/certificates-overview/).

## macOS

Declare Markdown UTTypes and `CFBundleDocumentTypes`; Launch Services uses these declarations to know the app can open the type. `LSHandlerRank` describes suitability (Owner/Default/Alternate/None), but capability declaration is not permission to replace the user's selection.

Sources: [`CFBundleDocumentTypes`](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledocumenttypes), [Launch Services keys](https://developer.apple.com/documentation/bundleresources/information-property-list/lsitemcontenttypes), and [Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers).

Apple's public user workflow is Finder: select a file → **File > Get Info** → **Open with** → choose the app → **Change All**. This should be md4a's most conservative, review-friendly guidance.

Source: [Apple Support: Choose an app to open a file on Mac](https://support.apple.com/guide/mac-help/choose-an-app-to-open-a-file-on-mac-mh35597/mac).

On macOS 12+, public AppKit APIs include `NSWorkspace.setDefaultApplication(at:toOpenContentType:completionHandler:)` (and per-file variants). Thus a direct change is technically supported. Use it only as the immediate result of a clearly labeled user action that states it changes all files of that type; never on install/launch/update. If App Store review interpretation is uncertain, ship Finder guidance first and raise the direct-flow behavior with App Review before relying on it. Older `LSSetDefaultRoleHandlerForContentType` is a Launch Services API, but the modern AppKit API is preferable on supported OS versions.

Sources: [`NSWorkspace`](https://developer.apple.com/documentation/appkit/nsworkspace) and [`LSSetDefaultRoleHandlerForContentType`](https://developer.apple.com/documentation/coreservices/1442948-lssetdefaultrolehandlerforcontent).

**Prohibited/avoid:** silently writing LaunchServices preference databases; shelling out to undocumented tools; changing associations during install; claiming `LSHandlerRank=Owner` makes md4a default. Mac App Store rules require apps to use public APIs and respect user consent/privacy, so retain a user-driven flow.

Source: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

### Signing/distribution

Two formal channels:

* **Mac App Store:** App Store distribution certificate/provisioning, App Sandbox/entitlements, App Store Connect review/distribution.
* **Outside the Store:** sign all nested code with **Developer ID Application**, enable hardened runtime as required for notarization, submit to Apple's notary service, then staple the ticket to the distributable. Installer packages use the appropriate Developer ID Installer signing identity.

Sources: [Create Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Signing a daemon with a restricted entitlement](https://developer.apple.com/documentation/security/code-signing-services), and [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox).

CI must verify `codesign --verify`, Gatekeeper assessment, notarization/stapling, and install→launch on a clean supported macOS version.

## Windows 10 and 11

A classic installer should register an application-specific ProgID, `.md` capability, `RegisteredApplications`, verbs/icon, and open command. MSIX should declare `uap:FileTypeAssociation`. Registration makes md4a eligible; it must not seize the current user's association.

Sources: [File types and file associations](https://learn.microsoft.com/en-us/windows/win32/shell/fa-file-types), [Registering an application for use with Default Programs](https://learn.microsoft.com/en-us/windows/win32/shell/default-programs), and [`uap:FileTypeAssociation`](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-uap-filetypeassociation).

Windows 8 deprecated programmatic default-association APIs, and Windows 10 changed defaults further. Modern Windows protects the user's choice (the `UserChoice` mechanism); installers/apps must not write or reverse-engineer its hash. The supported flow is system UI.

Sources: [Default Programs](https://learn.microsoft.com/en-us/windows/win32/shell/default-programs) and [Windows 10 default apps announcement](https://blogs.windows.com/windowsexperience/2015/05/20/announcing-windows-10-insider-preview-build-10122-for-pcs/).

Launch `ms-settings:defaultapps`. On updated Windows 11, deep-link directly to md4a using the applicable URI parameter:

* `registeredAppMachine=<escaped RegisteredApplications name>`
* `registeredAppUser=<escaped RegisteredApplications name>`
* `registeredAUMID=<escaped AUMID>` for packaged apps

Fall back to the general page on Windows 10/unsupported builds. The Settings page, not md4a, commits the choice.

Sources: [Launch the Default Apps settings page](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-default-apps-settings) and [Launch Windows Settings](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings).

**Exact UX:** after md4a is successfully registered, ask once: “Use md4a by default for Markdown files?” Buttons: **Open Default Apps** / **Not now**. Before opening Settings, state: “Find `.md` and choose md4a.” Provide a persistent Preferences action for later. Never modify `UserChoice`, delete another ProgID, simulate clicks, or repeatedly relaunch Settings.

### Signing/distribution

* **MSIX:** the package must be signed; the signing certificate subject must match the manifest Publisher. A trusted certificate is required for installation outside Store-managed trust. Timestamp release signatures so validation can survive certificate expiry. Microsoft Store handles Store package signing/distribution after submission.
* **EXE/MSI/bootstrapper:** Authenticode-sign every user-facing installer and shipped executable/library, use a publicly trusted code-signing certificate for normal internet distribution, and timestamp signatures. Avoid embedding stale prerequisite installers; validate/download official prerequisites and make failures visible.

Sources: [MSIX package signing overview](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview), [Sign an app package using SignTool](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool), [Introduction to code signing](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/authenticode), and [Windows App SDK deployment guide](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps).

CI should verify signatures/trust, install on clean Windows 10 and 11 VMs, launch, open a `.md`, upgrade from the prior release, and uninstall cleanly.

## Linux (freedesktop desktops)

Install a desktop entry whose `MimeType=` includes `text/markdown`, install/update the Shared MIME database if md4a supplies MIME definitions, and let desktop MIME association machinery discover it. Defaults are resolved from `mimeapps.list` across config/data locations with desktop-specific precedence.

Sources: [Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/), [Shared MIME-info specification](https://specifications.freedesktop.org/shared-mime-info-spec/latest/), and [MIME Applications Associations specification](https://specifications.freedesktop.org/mime-apps/latest/).

`xdg-mime query default text/markdown` queries the current desktop file; `xdg-mime default md4a.desktop text/markdown` requests a per-user default. The tool is intended for desktop-session use and behavior can depend on the DE. Therefore an explicit button may invoke it, but installation/post-install scripts must not do so automatically. Preserve the previous choice and verify the result; if the desktop ignores it, direct users to that DE's Default Applications/File Properties UI.

Source: [`xdg-mime` manual](https://portland.freedesktop.org/doc/xdg-mime.html).

**Prohibited/avoid:** no unconditional edits to `~/.config/mimeapps.list`; no root-owned per-user association; no overwriting system/vendor defaults; no assumption that `text/plain` is equivalent to Markdown. A package may add an association capability without making it default.

### Signing/distribution

Linux has no single universal application-signing authority; formal trust is distribution-format-specific:

* Debian/Ubuntu repositories authenticate signed repository metadata; `.deb` installation and repository publication should follow Debian archive/repository signing practices.
* RPM ecosystems use package/repository signatures according to the target distribution.
* Flatpak uses OSTree repository signatures and distribution through a trusted remote such as Flathub; follow Flathub submission/build infrastructure for that channel.
* AppImage supports optional embedded signatures; publish detached checksums/signatures and a documented verification path if distributing directly.

Primary references: [Debian repository format: Release signatures](https://wiki.debian.org/DebianRepository/Format#A.22Release.22_files), [Debian package/archive signing](https://www.debian.org/doc/manuals/securing-debian-manual/deb-pack-sign.en.html), [Fedora package signing](https://docs.fedoraproject.org/en-US/package-maintainers/Package_Signing/), [Flatpak under the hood: OSTree](https://docs.flatpak.org/en/latest/under-the-hood.html), [Flathub app submission](https://docs.flathub.org/docs/for-app-authors/submission), and [AppImage signatures](https://docs.appimage.org/packaging-guide/optional/signatures.html).

Release artifacts must be reproducibly versioned, checksummed, tested from each advertised package/remote on clean supported distributions, and upgraded from the prior release. Do not call an unsigned ad-hoc archive a formally trusted package.

## Cross-platform product acceptance checklist

1. The prompt appears only after capability registration succeeds, never interrupts opening the user's file, includes **Not now**, and can be invoked later from Preferences.
2. iOS/iPadOS uses different copy: **Open Markdown with md4a**, never “default.”
3. Android and Windows delegate final selection to OS-owned resolver/Settings UI.
4. macOS direct mutation, if shipped, occurs only from a deliberate **Make Default** click through public API and has Finder fallback.
5. Linux queries before changing and executes `xdg-mime default` only after an explicit click.
6. Automated tests verify md4a is offered for `.md`; tests must not destroy a developer/test user's existing defaults. Use disposable accounts/VMs.
7. Release pipelines separate development/debug credentials from stable distribution credentials, never store private keys in the repository, sign all final nested artifacts, timestamp/notarize where applicable, and perform clean-machine install→open `.md`→upgrade tests.

## Important uncertainty to keep explicit

Platform UI labels and resolver behavior can change across Android OEMs/releases and Linux desktop environments. Apple's public APIs establish technical capability on macOS, but the App Review Guidelines do not provide a Markdown-specific approval statement for changing defaults. The conservative product baseline is therefore user instruction/system UI; any direct macOS change should be explicit, reversible, use only public API, and be validated during App Store review.
