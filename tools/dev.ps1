$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Platform = if ($args.Count -ge 1) { $args[0] } else { "" }
$Action = if ($args.Count -ge 2) { $args[1] } else { "" }
$Version = if ($env:MD4A_DEV_VERSION) { $env:MD4A_DEV_VERSION } else { "0.0.0-dev" }
$BuildNumber = if ($env:MD4A_DEV_BUILD_NUMBER) { $env:MD4A_DEV_BUILD_NUMBER } else { "1" }
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

function Fail([string]$Message) { throw $Message }
function Need([string]$Command, [string]$Guidance) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { Fail $Guidance }
}
function Initialize-Submodules {
    Need "git" "git is required. Install it from https://git-scm.com/downloads and retry."
    & git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { Fail "git submodule initialization failed." }
}
function Validate-Inputs {
    if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') { Fail "VERSION must contain only letters, numbers, dots, underscores, and hyphens, and must start with a letter or number." }
    if ($BuildNumber -notmatch '^[1-9][0-9]*$') { Fail "BUILD_NUMBER must be a positive integer." }
    if ([System.Numerics.BigInteger]::Parse($BuildNumber) -gt 2100000000) { Fail "BUILD_NUMBER must not exceed Android's versionCode limit (2100000000)." }
}
function Show-Artifact([string]$Path, [string]$Status) {
    Write-Host "Artifact: $Path ($Status)"
}

switch ("${Platform}:${Action}") {
    "core:init" {
        Initialize-Submodules
        Need "cmake" "CMake 3.20+ is required. Install it from https://cmake.org/download/ and retry."
        & cmake -S . -B out/build/core -DMD4A_BUILD_TESTS=ON -DMD4A_BUILD_LINUX_APP=OFF
        if ($LASTEXITCODE -ne 0) { Fail "Core CMake configure failed." }
    }
    "core:build" {
        Validate-Inputs
        & cmake --build out/build/core --config Release
        if ($LASTEXITCODE -ne 0) { Fail "Core build failed." }
        & ctest --test-dir out/build/core -C Release --output-on-failure
        if ($LASTEXITCODE -ne 0) { Fail "Core tests failed." }
        Write-Host "Core build and tests complete; no distributable artifact is produced."
    }
    "android:init" {
        Initialize-Submodules
        Need "java" "JDK 17 is required. Install Temurin 17 from https://adoptium.net/ and retry."
        $JavaVersion = (& cmd.exe /d /c "java -version 2>&1" | Select-Object -First 1).ToString()
        if ($JavaVersion -notmatch '"17(?:\.|\")') { Fail "JDK 17 is required (found: $JavaVersion). Install Temurin 17 and set JAVA_HOME." }
        $SdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $null }
        $LocalProperties = "platform/android/local.properties"
        if (-not $SdkRoot -and (Test-Path $LocalProperties)) {
            $SdkEntry = Get-Content $LocalProperties | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -Last 1
            if ($SdkEntry) { $SdkRoot = ($SdkEntry -replace '^sdk\.dir=', '') -replace '\\\\', '\' -replace '\\:', ':' }
        }
        if (-not $SdkRoot -or -not (Test-Path $SdkRoot)) {
            Fail "Android SDK is required. Install Android Studio from https://developer.android.com/studio, install Platform 35, Build Tools 35.0.0, NDK 27.2.12479018, and CMake 3.22.1, then set ANDROID_HOME or platform/android/local.properties."
        }
        $Components = @{
            "platforms/android-35" = "Android SDK Platform 35 is missing. Install it with sdkmanager 'platforms;android-35'."
            "build-tools/35.0.0" = "Android Build Tools 35.0.0 are missing. Install them with sdkmanager 'build-tools;35.0.0'."
            "ndk/27.2.12479018" = "Android NDK 27.2.12479018 is missing. Install it with sdkmanager 'ndk;27.2.12479018'."
            "cmake/3.22.1" = "Android CMake 3.22.1 is missing. Install it with sdkmanager 'cmake;3.22.1'."
        }
        foreach ($Component in $Components.Keys) {
            if (-not (Test-Path (Join-Path $SdkRoot $Component))) { Fail $Components[$Component] }
        }
        & platform/android/gradlew.bat -p platform/android --no-daemon help | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "Android Gradle restore failed; verify the required SDK components are installed." }
    }
    "android:build" {
        Validate-Inputs
        New-Item -ItemType Directory -Force out/build/android, out/stage/android, out/artifacts | Out-Null
        $env:MD4A_VERSION_NAME = $Version
        $env:MD4A_VERSION_CODE = $BuildNumber
        & platform/android/gradlew.bat -p platform/android --no-daemon "-Pmd4aBuildDir=$Root/out/build/android" testDebugUnitTest assembleDebug assembleRelease bundleRelease
        if ($LASTEXITCODE -ne 0) { Fail "Android build failed." }
        $Outputs = @{
            "out/build/android/outputs/apk/debug/app-debug.apk" = "md4a-$Version-android-debug.apk"
            "out/build/android/outputs/apk/release/app-release-unsigned.apk" = "md4a-$Version-android-unsigned.apk"
            "out/build/android/outputs/bundle/release/app-release.aab" = "md4a-$Version-android-unsigned.aab"
        }
        foreach ($Source in $Outputs.Keys) {
            if (-not (Test-Path $Source)) { Fail "Android build output not found: $Source" }
            Copy-Item $Source (Join-Path out/artifacts $Outputs[$Source]) -Force
            Copy-Item $Source out/stage/android -Force
        }
        Show-Artifact "$Root/out/artifacts/md4a-$Version-android-debug.apk" "debug-signed local-test package"
        Show-Artifact "$Root/out/artifacts/md4a-$Version-android-unsigned.apk" "unsigned release package"
        Show-Artifact "$Root/out/artifacts/md4a-$Version-android-unsigned.aab" "unsigned release package"
    }
    "windows:init" {
        Initialize-Submodules
        Need "msbuild" "MSBuild is required. Install Visual Studio 2022 with 'Desktop development with C++', Windows SDK, and NuGet support, then run from Developer PowerShell."
        Need "nuget" "NuGet CLI is required. Install it from https://www.nuget.org/downloads or run NuGet/setup-nuget in CI."
        & nuget restore platform/windows/packages.config -PackagesDirectory platform/windows/packages -NonInteractive
        if ($LASTEXITCODE -ne 0) { Fail "Windows NuGet restore failed." }
        $RequiredImports = @(
            "platform/windows/packages/Microsoft.Windows.CppWinRT.2.0.221104.6/build/native/Microsoft.Windows.CppWinRT.props",
            "platform/windows/packages/Microsoft.Windows.SDK.BuildTools.10.0.22621.756/build/Microsoft.Windows.SDK.BuildTools.props",
            "platform/windows/packages/Microsoft.WindowsAppSDK.1.5.240311000/build/native/Microsoft.WindowsAppSDK.props"
        )
        foreach ($Import in $RequiredImports) {
            if (-not (Test-Path $Import)) { Fail "Restored Windows native build import not found: $Import" }
        }
    }
    "windows:build" {
        Validate-Inputs
        & msbuild platform/windows/Md4aCore.vcxproj /m /p:Configuration=Release /p:Platform=x64
        if ($LASTEXITCODE -ne 0) { Fail "Windows core build failed." }
        & msbuild platform/windows/Md4a.Windows.vcxproj /m /p:Configuration=Release /p:Platform=x64 /p:BuildProjectReferences=false
        if ($LASTEXITCODE -ne 0) { Fail "Windows app build failed." }
        $Source = "platform/windows/x64/Release/Md4a.Windows"
        if (-not (Test-Path $Source)) { Fail "Windows app build output not found: $Source" }
        $RequiredFiles = @("Md4a.Windows.exe", "Md4a.Windows.pri", "Microsoft.WindowsAppRuntime.Bootstrap.dll", "assets/md4a.ico")
        foreach ($RequiredFile in $RequiredFiles) {
            if (-not (Test-Path (Join-Path $Source $RequiredFile))) { Fail "Windows runtime file not found: $RequiredFile" }
        }
        $Stage = "out/stage/windows/md4a-$Version-windows-x64-unpackaged"
        Remove-Item out/stage/windows -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force $Stage, out/artifacts | Out-Null
        Copy-Item "$Source/*" $Stage -Recurse -Force
        $Output = "$Root/out/artifacts/md4a-$Version-windows-x64-unpackaged.zip"
        Remove-Item $Output -Force -ErrorAction SilentlyContinue
        Compress-Archive -Path "$Stage/*" -DestinationPath $Output
        Show-Artifact $Output "unsigned unpackaged diagnostic package"

        Need "iscc" "Inno Setup Compiler is required to create the Windows beta installer. Install it with Chocolatey ('choco install innosetup') and retry."
        $Download = "$Root/out/build/windows/downloads"
        New-Item -ItemType Directory -Force $Download | Out-Null
        $RuntimeInstaller = Join-Path $Download "WindowsAppRuntimeInstall-x64.exe"
        $WebViewInstaller = Join-Path $Download "MicrosoftEdgeWebview2Setup.exe"
        if (-not (Test-Path $RuntimeInstaller)) {
            Invoke-WebRequest "https://aka.ms/windowsappsdk/1.5/latest/windowsappruntimeinstall-x64.exe" -OutFile $RuntimeInstaller
        }
        if (-not (Test-Path $WebViewInstaller)) {
            Invoke-WebRequest "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -OutFile $WebViewInstaller
        }
        & iscc "/DAppVersion=$Version" "/DSourceDir=$Root/$Source" "/DOutputDir=$Root/out/artifacts" "/DRuntimeInstaller=$RuntimeInstaller" "/DWebViewInstaller=$WebViewInstaller" platform/windows/md4a.iss
        if ($LASTEXITCODE -ne 0) { Fail "Windows installer build failed." }
        $Setup = "$Root/out/artifacts/md4a-$Version-windows-x64-setup.exe"
        if (-not (Test-Path $Setup)) { Fail "Windows installer output not found: $Setup" }
        Show-Artifact $Setup "unsigned installable beta; SmartScreen warning expected"
    }
    default { Fail "unsupported command: ${Platform}:${Action}" }
}
