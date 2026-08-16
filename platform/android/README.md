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

From this directory, using an installed Gradle 8.9 or a generated Gradle wrapper:

```sh
gradle testDebugUnitTest
gradle assembleDebug
```

Set `sdk.dir` in an untracked `local.properties` when `ANDROID_HOME` is not configured.

## Behavior

The single screen starts with an editable new document. **Open** uses Android's system document picker, **Save** overwrites the current document URI or asks for a new one, and **Preview** renders through md4a over JNI into a locked-down WebView. Android document URIs are the only file authority used by the app.
