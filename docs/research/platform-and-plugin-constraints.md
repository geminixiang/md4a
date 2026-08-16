# Native platform and downloadable-renderer constraints

This note scopes a minimal Markdown editor/viewer whose native shells share MD4C, and whose optional renderers (for example Mermaid) are downloaded separately. Sources are first-party project, platform-vendor, or distribution documentation.

## Recommended baseline

| Target | Native UI shell | MD4C integration | Preview surface |
|---|---|---|---|
| Windows | WinUI 3 / Windows App SDK | Build MD4C as C and call its C ABI from the C++/WinRT app | WebView2 for generated HTML and renderer JavaScript |
| macOS | SwiftUI, using AppKit only where document-window/editor integration requires it | Compile MD4C into the app as a C module and import it into Swift | `WKWebView` |
| iPhone/iPad | SwiftUI | Same compiled-in C module as macOS | `WKWebView` |
| Android | Jetpack Compose | NDK/CMake native library called through JNI | Android `WebView` |
| Linux | GTK 4 | Link MD4C directly as C | WebKitGTK `WebView` |

The platform choices above deliberately keep controls, menus, file pickers, typography, accessibility, and window behavior native. SwiftUI declares UI across Apple platforms; Microsoft directs new Windows apps to WinUI; Android describes Compose as its recommended modern native UI toolkit; and GTK 4 is the maintained GTK application API.[^swiftui][^winappsdk][^compose][^gtk]

## MD4C facts that shape the design

MD4C is a portable C Markdown parser, implemented as one parser source/header pair with only the C standard library as a dependency. Its parser entry point is `md_parse()`. Parsing uses a push/callback model: the host receives block/span start and end events plus text. The repository also supplies `md4c-html`, whose `md_html()` entry point emits HTML through an output callback.[^md4c-readme][^md4c-api][^md4c-html]

The upstream CMake build produces the parser and, unless disabled, the HTML renderer and command-line tool. For this product, vendor a pinned upstream revision and compile the parser/HTML renderer into every app rather than treating MD4C itself as a downloadable plugin.[^md4c-cmake]

MD4C defaults to UTF-8. It has a Windows-only `MD4C_USE_UTF16` parser mode, but the supplied HTML renderer does **not** support that mode. A single UTF-8 core across all five targets therefore avoids a platform-specific renderer fork.[^md4c-readme]

Built-in flags already cover tables, strikethrough, task lists, permissive autolinks, LaTeX math spans, wiki links, and other extensions. Mermaid is not one of these: preserve fenced-code metadata during conversion, then let a separately versioned renderer transform designated nodes in the preview.[^md4c-api]

## Native interop

- **Apple:** Swift imports C-family APIs through Clang modules; expose the pinned MD4C headers with a module map (or an Xcode bridging header) and compile the C sources into the application target. This keeps all executable native code in the signed app bundle.[^swift-import]
- **Android:** Android Studio/Gradle compiles C/C++ sources into a native library packaged in the APK/AAB; Kotlin/Java calls it through JNI. Android Studio supports CMake specifically for cross-platform projects.[^android-native][^jni]
- **Windows and Linux:** MD4C already supports Windows and POSIX systems and exposes an ordinary C ABI, so the native shell can link it directly. Keep a small host-owned adapter around allocation, callbacks, UTF-8 input, and generated-byte ownership rather than exposing callbacks throughout UI code.[^md4c-readme]

## Downloadable plugins: policy boundary

### Apple App Store (iOS, iPadOS, and Mac App Store)

Apple guideline 2.5.2 says apps must be self-contained and may not download, install, or execute code that introduces or changes app features/functionality (with a narrow educational-app exception). Therefore a post-review downloaded dylib, framework, native plugin, WASM module, or general-purpose code plugin is not a defensible App Store design merely because it is signed by this app.[^apple-review]

Guideline 2.5.6 separately requires apps that browse the web to use the appropriate WebKit framework and WebKit JavaScript (outside specific alternative-engine entitlements). WebKit exposes `WKWebView`, user scripts, and JavaScript evaluation, so JavaScript execution in the preview is technically supported.[^apple-review][^wkwebview][^wkuserscript]

However, **WebKit support is not an exemption from 2.5.2**. Downloaded JavaScript that adds Mermaid rendering is still code that changes functionality, so Apple review acceptance cannot be asserted from the published rules. The lowest-risk App Store plan is:

1. bundle approved renderer code (including Mermaid) in each submitted app version; or
2. download only declarative data/themes/templates interpreted by capabilities already present in the reviewed binary.

If remotely downloaded renderer JavaScript is a hard requirement, obtain written App Review guidance before making it the product contract. Sandboxing, signatures, and a restricted bridge improve security but do not negate 2.5.2. A directly distributed/notarized macOS build can have a different plugin policy, but that policy must not leak into the Mac App Store build.

### Google Play / Android

Google Play explicitly forbids downloading executable code such as dex, JAR, or `.so` files from outside Play. It explicitly excludes code running in a VM/interpreter with indirect Android API access, giving “JavaScript in a webview or browser” as an example. Runtime-loaded interpreted code must nevertheless remain policy-compliant.[^google-device]

Thus a downloaded Mermaid JavaScript package can be acceptable on Google Play **in principle**, provided it runs only inside the WebView, cannot fetch/execute native or dex plugins, and does not introduce undisclosed or policy-violating behavior. Google also calls out a WebView JavaScript interface combined with untrusted HTTP content or unverified URLs as a violation example. Do not expose a broad `addJavascriptInterface` bridge; load only verified local package files, require HTTPS for downloads, and deny arbitrary navigation/network access.[^google-device][^android-webview]

### Windows and Linux

The cited Windows Store policy imposes security, truthful-functionality, and package/update obligations, but does not state an Apple-like blanket ban on separately downloaded plugin code.[^ms-store] WebView2 officially embeds HTML, CSS, and JavaScript in native apps.[^webview2] A conservative Microsoft Store build should still use signed, versioned renderer packages and disclose downloaded functionality; native binary plugins need separate Store-certification review.

Linux has no single app-store rule. Distribution format determines the boundary. Flatpak, for example, starts with no network and very limited host-file access; permissions must be granted explicitly.[^flatpak] WebKitGTK supplies the web preview component.[^webkitgtk] Prefer JavaScript renderer packages stored under app data and run in WebKitGTK, rather than native `.so` plugins, because this keeps one extension format and a narrower capability surface across desktop targets.

## Proposed renderer-package contract

Use one **data package** format across platforms:

- manifest: id, version, compatible host API version, handled fenced-code languages, hashes, signature, and declared network requirement;
- static JavaScript/CSS/assets only; no native, dex/JAR, shell commands, or arbitrary host FFI;
- verified signature and hash before activation; atomic install; rollback and per-renderer disable switch;
- isolated web content world/context where available; no filesystem, process, clipboard, credential, or unrestricted native bridge;
- render input and output passed as bounded strings/DOM nodes; sanitize MD4C-produced HTML and renderer output; default-deny navigation and network;
- renderer crashes/timeouts must leave the Markdown document editable and fall back to a code block.

For Apple App Store builds, ship the same packages **inside the reviewed bundle** and disable remote installation unless App Review has explicitly approved it. Other stores can enable the downloader subject to their current policies. Store policies change, so re-check them before every release.

## Primary sources

[^md4c-readme]: MD4C project README, https://github.com/mity/md4c/blob/master/README.md
[^md4c-api]: MD4C parser public header, https://github.com/mity/md4c/blob/master/src/md4c.h
[^md4c-html]: MD4C HTML renderer public header, https://github.com/mity/md4c/blob/master/src/md4c-html.h
[^md4c-cmake]: MD4C top-level CMake configuration, https://github.com/mity/md4c/blob/master/CMakeLists.txt
[^swiftui]: Apple SwiftUI documentation, https://developer.apple.com/documentation/swiftui/
[^swift-import]: The Swift Programming Language, “Import Declaration” (importing C/Objective-C modules), https://docs.swift.org/swift-book/documentation/the-swift-programming-language/declarations/#Import-Declaration
[^wkwebview]: Apple `WKWebView` documentation, https://developer.apple.com/documentation/webkit/wkwebview
[^wkuserscript]: Apple `WKUserContentController.addUserScript(_:)` documentation, https://developer.apple.com/documentation/webkit/wkusercontentcontroller/adduserscript(_:)
[^apple-review]: Apple App Review Guidelines, especially 2.5.2 and 2.5.6, https://developer.apple.com/app-store/review/guidelines/
[^winappsdk]: Microsoft Windows App SDK overview, including guidance for new apps to use WinUI, https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/
[^webview2]: Microsoft WebView2 documentation, https://learn.microsoft.com/en-us/microsoft-edge/webview2/
[^ms-store]: Microsoft Store Policies, https://learn.microsoft.com/en-us/windows/apps/publish/store-policies
[^compose]: Android Developers, Jetpack Compose documentation, https://developer.android.com/develop/ui/compose/documentation
[^android-native]: Android Developers, “Add C and C++ code to your project,” https://developer.android.com/studio/projects/add-native-code
[^jni]: Android Developers, “JNI tips,” https://developer.android.com/training/articles/perf-jni
[^android-webview]: Android Developers, “Build web apps in WebView,” https://developer.android.com/develop/ui/views/layout/webapps/webview
[^google-device]: Google Play Developer Program, “Device and Network Abuse,” https://support.google.com/googleplay/android-developer/answer/9888379
[^gtk]: GTK 4 API documentation, https://docs.gtk.org/gtk4/
[^webkitgtk]: WebKitGTK `WebView` API, https://webkitgtk.org/reference/webkit2gtk/stable/class.WebView.html
[^flatpak]: Flatpak documentation, “Sandbox Permissions,” https://docs.flatpak.org/en/latest/sandbox-permissions.html
