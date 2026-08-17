# Android app

A native Kotlin Android application for opening, creating, editing, previewing, and saving Markdown documents.

## Native stack

- Kotlin and one Android `ComponentActivity`.
- Jetpack Compose with Material 3 controls.
- Storage Access Framework (`OpenDocument` / `CreateDocument`) for document access; no broad storage permission.
- Android WebView for a local, non-JavaScript preview.
- Android NDK/CMake plus a narrow UTF-8 JNI adapter to the repository's `md4a`/md4c C sources.

No multiplatform, cross-platform UI, shared ViewModel, networking, accounts, or plugin installation is present in this MVP.

## Requirements

- JDK 17
- Android SDK Platform 35
- Android SDK Build Tools 35
- Android NDK with CMake 3.22.1

## Build and test

From the repository root, the supported developer interface uses [Task](https://taskfile.dev/):

```sh
task android:init
task android:build VERSION=0.2.0 BUILD_NUMBER=42
```

`init` checks JDK 17 and the required Android SDK components, initializes submodules, and restores with the checked-in Gradle 8.9 wrapper. It does not install SDK components or accept licenses. `build` runs unit tests and writes a debug-signed APK plus unsigned release APK/AAB to `out/artifacts`.

Native fallback from this directory:

```sh
./gradlew testDebugUnitTest assembleDebug assembleRelease bundleRelease
```

On Windows use `gradlew.bat`. Set `sdk.dir` in an untracked `local.properties` when `ANDROID_HOME` is not configured.

## Behavior

The single screen starts with an editable new document. **Open** uses Android's system document picker, **Save** overwrites the current document URI or asks for a new one, and **Preview** renders through md4a over JNI into a locked-down WebView. Android document URIs are the only file authority used by the app.
