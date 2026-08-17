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

## Markdown file handling

The installed desktop entry declares only `text/markdown` and `text/x-markdown` and passes selected files with `%F`. The application uses `G_APPLICATION_HANDLES_OPEN`, so launching it from a file manager or running the following opens each supplied Markdown document:

```sh
md4a_linux notes.md another.markdown
```

After first launch, md4a asks once whether it should become the default Markdown handler. It changes the association only after explicit consent, through the desktop-standard commands:

```sh
xdg-mime default app.md4a.Md4a.desktop text/markdown
xdg-mime default app.md4a.Md4a.desktop text/x-markdown
```

It never claims `text/plain`. The prompt can be opened again from **File → Make Default for Markdown…**. Installation copies the desktop entry and icons but deliberately does not edit `mimeapps.list` or change user defaults. If a desktop environment overrides `xdg-mime`, use its Default Applications settings or a Markdown file's Properties panel.

A staged tarball is host/distro-specific and unsigned. Production Linux distribution should use one of the ecosystem-native trust paths rather than claiming a universal Linux signature:

- a Flatpak repository, signed with the repository's GPG key; or
- distribution-native `.deb`/`.rpm` repositories, signed according to that repository's metadata/package policy.

The GitHub tarball remains a transparent test artifact and depends on compatible host GTK, GtkSourceView, and WebKitGTK libraries.
