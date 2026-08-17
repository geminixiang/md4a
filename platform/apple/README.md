# Apple apps

Native Swift applications with separate macOS and iOS targets. Both use SwiftUI's native `DocumentGroup` lifecycle for open, create, edit, and save, and `WKWebView` for the rendered preview. macOS and iPad use native split views; iPhone uses native Edit/Preview tabs.

The Apple targets share document, renderer, and preview code only. No Apple UI or application state is shared with another platform.

The Apple apps now use an app-owned incremental piece tree and viewport-only native editor instead of placing the full document in TextKit. On iPhone and iPad, tap places the caret; long-press selects a word, dragging extends the selection, and the standard edit menu provides Copy, Cut, Paste, and Select All. Clipboard operations materialize only the selected range, except an explicit Select All copy as requested by the user.

Preview HTML is written beneath the app cache root in an isolated per-session directory. The pipeline excludes these files from backup, uses complete file protection on iOS, removes stale session directories at startup without touching active sessions, and removes the current session on normal teardown. `WKWebView` receives read access only to the individual HTML file being loaded.

## Generate and build

From the repository root, use the cross-platform Task interface (Task installation is documented in the root README):

```sh
task macos:init
task macos:build VERSION=0.2.0 BUILD_NUMBER=42
task ios:init
task ios:build VERSION=0.2.0 BUILD_NUMBER=42
```

These commands require macOS, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). `init` checks prerequisites and generates the project without installing tools or accepting Xcode licenses. macOS `build` runs tests and packages an unsigned universal app zip. iOS `build` packages an unsigned Simulator-only app zip. Local artifacts are under `out/artifacts`.

Native fallback (the checked-in source of truth is `project.yml`):

```sh
cd platform/apple
xcodegen generate
xcodebuild -project md4a.xcodeproj -scheme md4aMac -destination 'platform=macOS' build test
xcodebuild -project md4a.xcodeproj -scheme md4aiOS -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build
```

`project.yml` compiles `../../core/src/md4a.c` and md4c's three C translation units directly into each target and exposes `../../core/include/md4a/md4a.h` through `Shared/md4a-Bridging-Header.h`. This avoids a generated binary dependency while keeping the existing C interface and semantics unchanged. A release build may replace those C source entries with an XCFramework that exports the same header.

The generated `md4a.xcodeproj` is intentionally not authoritative; regenerate it after changing `project.yml`. The targets require macOS 14 / iOS 17 or newer.
