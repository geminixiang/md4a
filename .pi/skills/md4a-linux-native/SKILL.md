---
name: md4a-linux-native
summary: Native Linux GTK4, GtkSourceView, WebKitGTK, GApplication file activation, desktop MIME integration, packaging, and release verification for md4a.
description: Use whenever reading, writing, reviewing, debugging, packaging, or releasing md4a's Linux C/GTK4 application. Enforces GApplication open semantics, GTK main-thread rules, WebKitGTK lifecycle, freedesktop desktop/MIME policy, and real build/package smoke tests.
license: MIT
---

# md4a Linux Native

Use this skill for every change under `platform/linux/`, Linux portions of `tools/dev.sh`, and Linux release workflow work.

## Required context

Read before editing:

- `platform/linux/README.md`
- `platform/linux/CMakeLists.txt`
- `platform/linux/src/main.c`
- `platform/linux/app.md4a.Md4a.desktop`
- `docs/research/default-app-and-signing.md` for file associations or release work

Use primary GTK, GLib/GIO, GtkSourceView, WebKitGTK, CMake, and freedesktop specifications for API decisions. Do not infer GTK behavior from web or Electron apps.

## Application lifecycle invariants

- Use `GtkApplication`/`GApplication`; preserve the stable application ID `app.md4a.Md4a`.
- File-manager activation must use `G_APPLICATION_HANDLES_OPEN` and the `open` signal. A desktop entry with `%F` is not sufficient unless the process consumes the files.
- No-argument activation opens a normal app/window flow. Opening one or more Markdown paths must open those Documents, not an unrelated Untitled document.
- All GTK widget mutation stays on the GTK main context. Long file I/O, Markdown rendering, and expensive transforms belong in worker tasks; publish only the latest revision back to GTK.
- Cancellation/stale-result suppression is mandatory for Preview updates. A debounce that still performs full rendering on the main thread is not sufficient.
- Close timers, cancellables, files, buffers, WebKit objects, and signal handlers explicitly in destruction paths.

## Editor and Preview

- `GtkTextView`/`GtkSourceView` are native controls but are not proof of large-document performance. Benchmark the exact 8,841,392-byte acceptance fixture.
- Treat syntax highlighting, line numbers, and word wrap as measured costs. Do not disable large-document editing as a substitute for solving performance.
- Preserve UTF-8 exactly, including CRLF and multilingual/emoji text. IME composition must not publish duplicate or intermediate committed content.
- Never execute untrusted Markdown JavaScript. Preserve the no-JavaScript WebKit policy, navigation restrictions, and raw-HTML policy.
- Separate measurements for text snapshot, md4c, HTML assembly, WebKit navigation, app memory, and WebKit child-process memory.

## Default Markdown handler policy

- The desktop file advertises Markdown only (`text/markdown`, `text/x-markdown`), not `text/plain`.
- Installation may install the desktop entry and icons but must not modify `mimeapps.list` or silently claim defaults.
- Ask explicitly at runtime. Only after consent may the app call:

```sh
xdg-mime default app.md4a.Md4a.desktop text/markdown
xdg-mime default app.md4a.Md4a.desktop text/x-markdown
```

- Query and verify the result; show desktop-environment guidance on failure. Keep a menu action to retry.

## Build and verification

On Ubuntu 24.04 or the CI image:

```sh
task linux:init
task linux:build VERSION=0.0.0-dev BUILD_NUMBER=1
```

Also run when available:

```sh
desktop-file-validate platform/linux/app.md4a.Md4a.desktop
```

A successful compiler invocation is not completion. Verify:

1. packaged `usr/bin/md4a_linux` starts under a graphical session or Xvfb/Wayland test environment;
2. `%F`/`G_APPLICATION_HANDLES_OPEN` opens a UTF-8 Markdown fixture;
3. window remains alive;
4. Preview reaches load-finished;
5. save/reopen bytes match;
6. desktop file/icon paths exist in staged install;
7. no installer-time default hijack.

Use job timeouts for apt and build steps. If dependency installation stalls, cancel and isolate Linux rather than blocking verified platform releases.

## Packaging and trust

- A host-specific tarball is unsigned and depends on host GTK/WebKitGTK libraries; label it honestly.
- Prefer Flatpak/Flathub or distribution-native `.deb`/`.rpm` for production. Sign repository metadata/commits according to that ecosystem; Linux has no single universal app-signing mechanism.
- Do not claim production trust from a checksum alone.
