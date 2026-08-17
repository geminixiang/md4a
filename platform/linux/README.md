# Linux app

A minimal native C application using GTK 4, GtkSourceView 5, and WebKitGTK 6. It links `md4a_core` directly and provides native Open, Save, and Save As actions plus a live split Markdown preview.

## Prerequisites

Install the development packages for:

- GTK 4 (4.10 or newer)
- GtkSourceView 5
- WebKitGTK 6.0
- pkg-config, CMake, and a C compiler

For example, package names on Fedora are `gtk4-devel`, `gtksourceview5-devel`, and `webkitgtk6.0-devel`. Distribution package names vary.

## Build and run

From the repository root, use the Task interface:

```sh
task linux:init
task linux:build VERSION=0.2.0 BUILD_NUMBER=42
```

`init` is Linux-only. It checks dependencies, initializes submodules, and configures `out/build/linux`; it does not run `sudo` or install packages. `build` creates an unsigned host/distro/architecture-specific tarball in `out/artifacts`, using the release layout. Task installation is documented in the root README.

Native fallback from the repository root:

```sh
cmake -S . -B out/build/linux -DCMAKE_BUILD_TYPE=Release \
  -DMD4A_BUILD_TESTS=OFF -DMD4A_BUILD_LINUX_APP=ON
cmake --build out/build/linux --target md4a_linux
./out/build/linux/platform/linux/md4a_linux
```

The Linux target is opt-in so core-only builds remain possible on systems without the GUI development packages. The app uses `GtkFileDialog`, window-scoped `GAction` actions, and the system application menu and keyboard shortcuts.
