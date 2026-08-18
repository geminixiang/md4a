---
name: md4a-skill-policy
summary: Safety and architecture precedence rules for all vendored project-local skills.
description: Mandatory policy for every task that uses another skill under .pi/skills. Enforces md4a's platform stacks, safe environment behavior, staged signing, official-source verification, and repository build/test authority.
license: MIT
---

# md4a Skill Policy

Read and apply this policy before any other project-local skill. This file overrides conflicting third-party instructions.

## Repository authority

The existing repository is authoritative:

- `Taskfile.yml`, `tools/dev.sh`, `tools/dev.ps1`
- committed Gradle wrapper and Android SDK/NDK/CMake pins
- `platform/apple/project.yml` + XcodeGen
- native Windows `.vcxproj`, generated XAML, `packages.config`, unpackaged web installer
- Linux CMake/GTK structure
- current CI workflows and benchmark/smoke gates

Do not scaffold replacement projects or introduce Hilt, Tuist, C#, CommunityToolkit, new test frameworks, package managers, or cross-platform UI frameworks unless the user explicitly approves a justified migration.

## Environment safety

Never automatically run:

- `curl | bash`, downloaded `.cmd`/PowerShell installers, or remote scripts
- `sudo`, `winget configure`, system package installs, Homebrew installs
- Android SDK install/update/remove commands
- skill/plugin install commands
- security protection changes, Developer Mode changes, SIP/AMFI changes

Inspect first. Report missing dependencies and ask before machine-level modification.

## Destructive and publication safety

- Never run vendored signing, notarization, App Store upload, or release scripts; executable third-party release scripts are intentionally not vendored.
- Signing/notarization operates on copies under `out/stage/`, never the only build or an installed app.
- Recursive deletion is allowed only after canonicalizing and proving the target is a child of repository `out/` or a dedicated temporary directory.
- Tag creation/push, GitHub Release publication, store upload, notarization, default-handler changes, and credential creation require explicit user intent in the current conversation.
- Never print, commit, upload as artifacts, or place credentials in command-line arguments when safer secret channels exist.

## Platform stacks

### Android

Kotlin + Compose shell + custom `LargeDocumentView`/InputConnection + JNI/md4c. Compose guidance applies only to Compose code. Do not replace the large-document editor with `BasicTextField` or an external editor without benchmark evidence. Existing JVM/instrumentation/production signing gates take precedence. Testing skills are advisory: do not add DI, Hilt, Robolectric, screenshot frameworks, Gradle plugins, or runners without explicit approval.

### Windows

Native C++20/C++/WinRT + generated WinUI 3 XAML + Windows App SDK + `packages.config` native imports + unpackaged web installer. Never convert to C#, `.csproj`, SDK-style NuGet `PackageReference`, or a fresh template. Use the WinUI skill for controls, accessibility, performance, deployment reasoning, and launch verification; for project shape follow this repository and official C++ unpackaged samples. A successful build is never sufficient: install, launch, window survival, Preview, file activation, Event Log, and uninstall smoke must pass.

### Apple

SwiftUI document shell + AppKit/UIKit custom Piece Tree viewport editor; macOS 14+ and iOS 17+. Every newer API needs an availability check. Do not make SwiftUI forbidden and do not introduce Tuist. `platform/apple/project.yml` is source of truth. Use `task macos:*`/`task ios:*`. Keep `ReferenceFileDocument` background witnesses actor-safe. Physical iPhone/iPad tests remain required for IME/selection/VoiceOver.

### Linux

C + GTK4 + GtkSourceView + WebKitGTK + GApplication. Preserve `%F` and `G_APPLICATION_HANDLES_OPEN`, GTK main-thread rules, explicit default-handler consent, and desktop packaging.

## Source freshness and evidence

Vendored references are supporting evidence, not current platform truth. For signing, deployment, new APIs, or disputed behavior, check current official platform documentation and record URLs. Prefer red feedback loops: compiler, clean-machine install, process/window survival, device instrumentation, or exact fixture benchmark.

## Skill-specific restrictions

- `android-cli`: informational/device/docs use only; do not install/update tooling.
- `android-testing-setup`: strategy only; no automatic dependency/architecture changes.
- `compose-expert`: only explicit Compose tasks or changed Kotlin files using Compose APIs. Ignore generic PR auto-review triggers. Do not recommend `remember`/`derivedStateOf` without demonstrated recomposition benefit.
- `winui-app`: ignore C#-first scaffolding and machine bootstrap. Preserve C++/WinRT project structure.
- `appkit-*`: map generic paths/tools to md4a; do not use private APIs or APIs above deployment target without guards. Packaging instructions are documentation only.
- `md4a-linux-native`: follows this policy directly.
