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

From the `md4a` repository root:

```sh
cmake -S . -B build -DMD4A_BUILD_LINUX_APP=ON
cmake --build build --target md4a_linux
./build/platform/linux/md4a_linux
```

The Linux target is opt-in so core-only builds remain possible on systems without the GUI development packages. The app uses `GtkFileDialog`, window-scoped `GAction` actions, and the system application menu and keyboard shortcuts.
