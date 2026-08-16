# Apple apps

Native Swift applications with separate macOS and iOS targets. Both use SwiftUI's native `DocumentGroup` lifecycle for open, create, edit, and save, and `WKWebView` for the rendered preview. macOS and iPad use native split views; iPhone uses native Edit/Preview tabs.

The Apple targets share document, renderer, and preview code only. No Apple UI or application state is shared with another platform.

## Generate and build

The checked-in source of truth is `project.yml`; generate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd platform/apple
xcodegen generate
xcodebuild -project md4a.xcodeproj -scheme md4aMac -destination 'platform=macOS' build test
xcodebuild -project md4a.xcodeproj -scheme md4aiOS -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build
```

`project.yml` compiles `../../core/src/md4a.c` and md4c's three C translation units directly into each target and exposes `../../core/include/md4a/md4a.h` through `Shared/md4a-Bridging-Header.h`. This avoids a generated binary dependency while keeping the existing C interface and semantics unchanged. A release build may replace those C source entries with an XCFramework that exports the same header.

The generated `md4a.xcodeproj` is intentionally not authoritative; regenerate it after changing `project.yml`. The targets require macOS 14 / iOS 17 or newer.
