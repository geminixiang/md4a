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

## Developer commands

[Task](https://taskfile.dev/) is the cross-platform command interface. Install it with `brew install go-task` on macOS, the [official Linux install script or package](https://taskfile.dev/installation/), or `winget install Task.Task` on Windows. Task does not replace the native SDKs; each `*:init` command checks them, initializes recursive submodules, and performs repository-local generation/configuration/restore. It never installs system packages, accepts licenses, or configures signing credentials.

```sh
task --list
task core:init
task core:build
task android:init
task android:build VERSION=0.2.0 BUILD_NUMBER=42
```

Available namespaces are `core`, `macos`, `ios`, `android`, `linux`, and `windows`, each with `init` and `build`. Apple commands require macOS, Linux commands require Linux, and Windows commands require Windows. `VERSION` defaults to `0.0.0-dev` and `BUILD_NUMBER` to `1`. Build artifacts go to `out/artifacts`; intermediate output uses `out/build/<platform>` and `out/stage/<platform>`. Every build reports whether its output is signed, unsigned, or debug-signed.

If Task is unavailable, use the platform-native fallback commands in each platform README. Shared core fallback:

```sh
git submodule update --init --recursive
cmake -S . -B out/build/core -DMD4A_BUILD_TESTS=ON
cmake --build out/build/core
ctest --test-dir out/build/core --output-on-failure
```

Tagged builds and release artifacts are documented in [`docs/releases.md`](docs/releases.md).

## Extension safety

A renderer package is data plus sandboxed web content, not a native library. The app verifies its manifest, file hashes, and publisher signature before installation. Renderer JavaScript runs only in the preview web view with networking disabled and a narrow message interface. Remote package installation is enabled only where the platform store permits it; iOS and Mac App Store builds bundle reviewed renderers in the app instead.

See [`docs/architecture.md`](docs/architecture.md) and [`docs/plugin-packages.md`](docs/plugin-packages.md).
