# Native platform applications

Every directory below is an independent native application. There is intentionally no shared UI toolkit, cross-platform application framework, shared view model, or common application lifecycle.

- `apple/`: Swift, SwiftUI, AppKit/UIKit, and WKWebView. macOS and iOS use separate app targets while sharing only Apple-specific Swift code where Apple's own frameworks make that natural.
- `android/`: Kotlin, Jetpack Compose, Android document APIs, and Android WebView.
- `windows/`: C++/WinRT, Windows App SDK (WinUI 3), and WebView2.
- `linux/`: C, GTK 4, GtkSourceView, and WebKitGTK.

The only compiled code shared across operating systems is `../core`, a C library wrapping md4c. Renderer package and catalog formats are shared protocols, not an application framework.

From the repository root, `task <platform>:init` checks and prepares a platform project, while `task <platform>:build` builds a local-test package in `out/artifacts`. Supported namespaces are `macos`, `ios`, `android`, `linux`, and `windows`; `core` provides the same interface without creating a distributable. Host restrictions, Task installation, and native fallback commands are documented in the root and platform READMEs.
