#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

platform=${1:-}
action=${2:-}
version=${MD4A_DEV_VERSION:-0.0.0-dev}
build_number=${MD4A_DEV_BUILD_NUMBER:-1}

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$2"; }
submodules() {
  need git "git is required. Install it from https://git-scm.com/downloads and retry."
  git submodule update --init --recursive
}
validate_inputs() {
  [[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || fail "VERSION must contain only letters, numbers, dots, underscores, and hyphens, and must start with a letter or number."
  [[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "BUILD_NUMBER must be a positive integer."
  ((10#$build_number <= 2100000000)) || fail "BUILD_NUMBER must not exceed Android's versionCode limit (2100000000)."
}
artifact() { printf 'Artifact: %s (%s)\n' "$1" "$2"; }
require_darwin() { [[ $(uname -s) == Darwin ]] || fail "$platform:$action requires macOS (Darwin)."; }
require_linux() { [[ $(uname -s) == Linux ]] || fail "$platform:$action requires Linux."; }

case "$platform:$action" in
  core:init)
    submodules
    need cmake "CMake 3.20+ is required. Install it from https://cmake.org/download/ and retry."
    cmake -S . -B out/build/core -DMD4A_BUILD_TESTS=ON -DMD4A_BUILD_LINUX_APP=OFF
    ;;
  core:build)
    validate_inputs
    cmake --build out/build/core
    ctest --test-dir out/build/core --output-on-failure
    printf 'Core build and tests complete; no distributable artifact is produced.\n'
    ;;
  macos:init|ios:init)
    require_darwin
    submodules
    need xcodebuild "Xcode is required. Install it from the Mac App Store, run 'sudo xcodebuild -license' yourself, then retry."
    need xcodegen "XcodeGen is required. Install it with 'brew install xcodegen' or see https://github.com/yonaskolb/XcodeGen#installing."
    xcodegen generate --spec platform/apple/project.yml
    ;;
  macos:build)
    require_darwin
    validate_inputs
    rm -rf out/build/macos out/stage/macos
    mkdir -p out/build/macos out/stage/macos out/artifacts
    xcodebuild -project platform/apple/md4a.xcodeproj -scheme md4aMac \
      -configuration Release -destination 'generic/platform=macOS' \
      -derivedDataPath "$ROOT/out/build/macos" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
      MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
      CODE_SIGNING_ALLOWED=NO build
    xcodebuild -project platform/apple/md4a.xcodeproj -scheme md4aMac \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$ROOT/out/build/macos/tests" \
      MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
      CODE_SIGNING_ALLOWED=NO test
    app=out/build/macos/Build/Products/Release/md4a.app
    [[ -d "$app" ]] || fail "macOS build output not found: $app"
    cp -R "$app" out/stage/macos/
    output="$ROOT/out/artifacts/md4a-${version}-macos-universal-unsigned.zip"
    rm -f "$output"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$output"
    artifact "$output" "unsigned local-test package"
    ;;
  ios:build)
    require_darwin
    validate_inputs
    rm -rf out/build/ios out/stage/ios
    mkdir -p out/build/ios out/stage/ios out/artifacts
    xcodebuild -project platform/apple/md4a.xcodeproj -scheme md4aiOS \
      -configuration Release -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$ROOT/out/build/ios" \
      MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
      CODE_SIGNING_ALLOWED=NO build
    app=out/build/ios/Build/Products/Release-iphonesimulator/md4a.app
    [[ -d "$app" ]] || fail "iOS Simulator build output not found: $app"
    cp -R "$app" out/stage/ios/
    output="$ROOT/out/artifacts/md4a-${version}-ios-simulator-unsigned.zip"
    rm -f "$output"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$output"
    artifact "$output" "unsigned Simulator-only local-test package"
    ;;
  android:init)
    submodules
    need java "JDK 17 is required. Install Temurin 17 from https://adoptium.net/ and retry."
    java_version=$(java -version 2>&1 | head -n 1 || true)
    [[ "$java_version" == *'"17.'* || "$java_version" == *'"17"'* ]] || fail "JDK 17 is required (found: $java_version). Install Temurin 17 from https://adoptium.net/ and set JAVA_HOME."
    sdk_root=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
    local_sdk=
    if [[ -f platform/android/local.properties ]]; then
      local_sdk=$(sed -n 's/^sdk\.dir=//p' platform/android/local.properties | tail -n 1 | sed 's/\\:/:/g; s/\\\\/\\/g')
    fi
    sdk_root=${sdk_root:-$local_sdk}
    [[ -n "$sdk_root" && -d "$sdk_root" ]] || fail "Android SDK is required. Install Android Studio from https://developer.android.com/studio, install Platform 35, Build Tools 35.0.0, NDK 27.2.12479018, and CMake 3.22.1, then set ANDROID_HOME or platform/android/local.properties."
    [[ -d "$sdk_root/platforms/android-35" ]] || fail "Android SDK Platform 35 is missing. Install it with sdkmanager 'platforms;android-35'."
    [[ -d "$sdk_root/build-tools/35.0.0" ]] || fail "Android Build Tools 35.0.0 are missing. Install them with sdkmanager 'build-tools;35.0.0'."
    [[ -d "$sdk_root/ndk/27.2.12479018" ]] || fail "Android NDK 27.2.12479018 is missing. Install it with sdkmanager 'ndk;27.2.12479018'."
    [[ -d "$sdk_root/cmake/3.22.1" ]] || fail "Android CMake 3.22.1 is missing. Install it with sdkmanager 'cmake;3.22.1'."
    platform/android/gradlew -p platform/android --no-daemon help >/dev/null
    ;;
  android:build)
    validate_inputs
    mkdir -p out/build/android out/stage/android out/artifacts
    MD4A_VERSION_NAME="$version" MD4A_VERSION_CODE="$build_number" \
      platform/android/gradlew -p platform/android --no-daemon \
      -Pmd4aBuildDir="$ROOT/out/build/android" testDebugUnitTest assembleDebug assembleRelease bundleRelease
    debug=out/build/android/outputs/apk/debug/app-debug.apk
    release_apk=out/build/android/outputs/apk/release/app-release-unsigned.apk
    release_aab=out/build/android/outputs/bundle/release/app-release.aab
    for file in "$debug" "$release_apk" "$release_aab"; do [[ -f "$file" ]] || fail "Android build output not found: $file"; done
    cp "$debug" "out/artifacts/md4a-${version}-android-debug.apk"
    cp "$release_apk" "out/artifacts/md4a-${version}-android-unsigned.apk"
    cp "$release_aab" "out/artifacts/md4a-${version}-android-unsigned.aab"
    cp "$debug" "$release_apk" "$release_aab" out/stage/android/
    artifact "$ROOT/out/artifacts/md4a-${version}-android-debug.apk" "debug-signed local-test package"
    artifact "$ROOT/out/artifacts/md4a-${version}-android-unsigned.apk" "unsigned release package"
    artifact "$ROOT/out/artifacts/md4a-${version}-android-unsigned.aab" "unsigned release package"
    ;;
  linux:init)
    require_linux
    submodules
    need cmake "CMake 3.20+ is required. Install it with your distribution package manager and retry."
    need pkg-config "pkg-config is required. Install it with your distribution package manager and retry."
    need cc "A C compiler is required. Install your distribution's C development toolchain and retry."
    pkg-config --atleast-version=4.10 gtk4 || fail "GTK 4.10+ development files are required (Ubuntu 24.04: sudo apt-get install libgtk-4-dev)."
    pkg-config --exists gtksourceview-5 || fail "GtkSourceView 5 development files are required (Ubuntu 24.04: sudo apt-get install libgtksourceview-5-dev)."
    pkg-config --exists webkitgtk-6.0 || fail "WebKitGTK 6 development files are required (Ubuntu 24.04: sudo apt-get install libwebkitgtk-6.0-dev)."
    cmake -S . -B out/build/linux -DCMAKE_BUILD_TYPE=Release -DMD4A_BUILD_TESTS=OFF -DMD4A_BUILD_LINUX_APP=ON
    ;;
  linux:build)
    require_linux
    validate_inputs
    cmake --build out/build/linux --target md4a_linux
    . /etc/os-release
    host=$(printf '%s%s' "${ID:-linux}" "${VERSION_ID:+${VERSION_ID}}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
    arch=$(uname -m)
    root="md4a-${version}-linux-${host}-${arch}"
    rm -rf out/stage/linux
    mkdir -p "out/stage/linux/$root" out/artifacts
    DESTDIR="$ROOT/out/stage/linux/$root" cmake --install out/build/linux --prefix /usr --strip
    cp README.md LICENSE "out/stage/linux/$root/"
    output="$ROOT/out/artifacts/${root}.tar.gz"
    tar -C out/stage/linux -czf "$output" "$root"
    artifact "$output" "unsigned; requires host GTK/WebKitGTK libraries"
    ;;
  *) fail "unsupported command: $platform:$action" ;;
esac
