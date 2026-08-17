# Android app

A native Kotlin Android application for opening, creating, editing, previewing, and saving Markdown documents.

## Native stack

- Kotlin and one Android `ComponentActivity`.
- Jetpack Compose with Material 3 controls and an MIT, repository-owned virtualized text editor.
- A persistent piece-tree document session: interactive edits, selection, and undo/redo do not flatten the full document.
- `LargeDocumentView` renders only visible plain-text lines and integrates directly with Android IME and clipboard APIs.
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

`init` checks JDK 17 and the required Android SDK components, initializes submodules, and restores with the checked-in Gradle 8.9 wrapper. It does not install SDK components or accept licenses. `build` runs unit tests and writes a debug-signed APK to `out/artifacts`; this artifact is for local development only and is never a product beta.

Production-signed packaging uses a separate command and never falls back to the debug key:

```sh
export MD4A_ANDROID_KEYSTORE_FILE=/absolute/path/to/md4a-upload.jks
export MD4A_ANDROID_STORE_PASSWORD='...'
export MD4A_ANDROID_KEY_ALIAS='md4a-upload'
export MD4A_ANDROID_KEY_PASSWORD='...'
task android:release VERSION=0.2.0 BUILD_NUMBER=42
```

All four variables are required. `signedBeta` packaging fails with a clear error if any is missing or the keystore path is invalid. Successful output is a universal signed APK and a signed AAB:

```text
out/artifacts/md4a-0.2.0-android.apk
out/artifacts/md4a-0.2.0-android.aab
```

Never commit the keystore or passwords.

Native fallback from this directory:

```sh
./gradlew testDebugUnitTest assembleDebug
# With all MD4A_ANDROID_* signing variables configured:
./gradlew assembleSignedBeta bundleSignedBeta
```

On Windows use `gradlew.bat`. Set `sdk.dir` in an untracked `local.properties` when `ANDROID_HOME` is not configured.

## Behavior

The single screen starts with an editable new document. **Open** uses Android's system document picker, **Save** overwrites the current document URI or asks for a new one, and **Preview** renders through md4a over JNI into a locked-down WebView. Android document URIs are the only file authority used by the app.

Open and save run away from the UI thread. UTF-8 input and original CRLF sequences are retained. Save streams an immutable piece-tree snapshot and clears dirty state only when the exact revision written is still current. Preview also captures an immutable snapshot; the complete Markdown string is created only at the existing JNI boundary, never for each key press. Switching between Edit and Preview retains the editor session and selection. There is no document-size gate or reduced large-file editing mode.

## Markdown default handler

After the first screen is visible, md4a asks once whether the user wants to prefer it for Markdown. Android does not expose an arbitrary Markdown `RoleManager` role and the app never changes defaults itself. **Open settings** opens the platform's Open by default page when available (otherwise App info); the user can then choose md4a/Always from Android's chooser. The prompt state is persisted, while the toolbar's **Defaults** action remains available later.

The manifest claims Markdown MIME types and common Markdown filename extensions. It intentionally does **not** claim broad `text/plain`, which would make md4a a candidate for unrelated text files.

## Play App Signing and CI secrets

1. In Play Console, create the app with package `app.md4a`, enable **Play App Signing**, and retain Google's app-signing certificate details.
2. Create one long-lived upload keystore (`keytool -genkeypair ...`), back it up securely, and export its public upload certificate (`keytool -exportcert -rfc ...`). Register that upload certificate in Play Console.
3. Record the upload certificate SHA-256 with:

   ```sh
   keytool -list -v -keystore md4a-upload.jks -alias md4a-upload
   ```

4. Create a protected GitHub Environment named `android-production`, require reviewers as appropriate, and add environment secrets:
   - `MD4A_ANDROID_KEYSTORE_BASE64` — base64 of the binary keystore (single line)
   - `MD4A_ANDROID_STORE_PASSWORD`
   - `MD4A_ANDROID_KEY_ALIAS`
   - `MD4A_ANDROID_KEY_PASSWORD`
   - `MD4A_ANDROID_UPLOAD_CERT_SHA256` — the upload certificate digest, with or without colons
5. Upload the CI-produced `.aab` to Play internal testing. The standalone APK is signed by the same upload key for direct controlled testing; Play-distributed APKs are signed by Google's app-signing key and therefore have a different certificate.

CI decodes the keystore only into runner temporary storage, verifies the APK with `apksigner`, compares its certificate digest, installs and launches it on an emulator, repeats installation with `-r` to verify the same-certificate upgrade path, and removes the temporary keystore. No signing material belongs in the repository.
