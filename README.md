# md4a

md4a is a small, system-native Markdown editor and viewer for Windows, macOS, iPhone/iPad, Android, and Linux. It uses [md4c](https://github.com/mity/md4c) as the shared CommonMark parser and keeps platform UI code native.

## Product scope

The first release intentionally contains only:

- open, edit, preview, and save Markdown files;
- a split editor/preview layout where the platform supports it;
- system-native document pickers, menus, keyboard shortcuts, and appearance;
- downloadable, signed renderer packages for fenced formats such as Mermaid;
- no accounts, synchronization, collaboration, or proprietary document format.

## Repository layout

- `core/` — shared C interface around md4c and renderer-package discovery.
- `platform/apple/` — separate native SwiftUI/AppKit macOS and SwiftUI/UIKit iOS app targets.
- `platform/android/` — native Kotlin/Jetpack Compose Android app.
- `platform/windows/` — native WinUI 3/C++ Windows app.
- `platform/linux/` — native GTK 4/C Linux app.
- `plugins/` — built-in and example renderer packages.
- `docs/` — architecture, package format, and research notes.

## Build status

The shared core and its tests are built with CMake:

```sh
cmake -S . -B build -G Ninja -DMD4A_BUILD_TESTS=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

Platform projects are deliberately independent because their native SDKs and packaging tools differ. See each platform directory for prerequisites and commands. Tagged builds and unsigned release artifacts are documented in [`docs/releases.md`](docs/releases.md).

## Extension safety

A renderer package is data plus sandboxed web content, not a native library. The app verifies its manifest, file hashes, and publisher signature before installation. Renderer JavaScript runs only in the preview web view with networking disabled and a narrow message interface. Remote package installation is enabled only where the platform store permits it; iOS and Mac App Store builds bundle reviewed renderers in the app instead.

See [`docs/architecture.md`](docs/architecture.md) and [`docs/plugin-packages.md`](docs/plugin-packages.md).
