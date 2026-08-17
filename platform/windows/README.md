# Windows app

A minimal native C++/WinRT desktop application using Windows App SDK WinUI 3 and its WebView2 control. It has one document window with a native text editor and live Preview, plus **New**, **Open**, **Save**, and **Save As** commands and standard shortcuts. Files remain ordinary UTF-8 Markdown documents.

`Md4aCore.vcxproj` compiles and statically links the shared C API and the pinned md4c sources directly. There is no .NET layer or cross-platform framework.

## Prerequisites

- Windows 10 version 1809 or later
- Visual Studio 2022 with **Desktop development with C++**
- Windows 10/11 SDK
- Visual Studio NuGet support or the standalone `nuget.exe` CLI
- WebView2 Runtime (included with current Windows versions; otherwise install Microsoft's Evergreen Runtime)
- The repository cloned with submodules: `git submodule update --init --recursive`

The project deliberately uses native `packages.config` restoration and the packages' `build/native` imports, matching Microsoft's unpackaged C++/WinUI 3 project model. Do not convert it to SDK-style `PackageReference` or add .NET/UAP `TargetFramework` properties: under current MSBuild/NuGet this produces incompatible `native` versus `UAP,Version=v10.0` asset resolution.

The project pins Windows App SDK `1.5.240311000`. Package restore supplies C++/WinRT headers, WinUI 3, bootstrap support, and the WebView2 SDK used by the WinUI control.

## Build

From a Developer PowerShell for Visual Studio at the repository root, use the Task interface:

```powershell
task windows:init
task windows:build VERSION=0.2.0 BUILD_NUMBER=42
```

`init` checks prerequisites, initializes submodules, and restores NuGet packages without installing software. `build` creates an unsigned x64 unpackaged zip in `out/artifacts`. Task can be installed with `winget install Task.Task`; see the root README for all Task installation options.

Native fallback from this directory:

```powershell
msbuild .\md4a-windows.sln /restore /p:Configuration=Debug /p:Platform=x64
```

Or open `md4a-windows.sln` in Visual Studio, allow NuGet package restore, select `x64` or `ARM64`, and build/run `Md4a.Windows`.

This is an unpackaged WinUI 3 application. Startup follows the generated C++ WinUI structure: `App.xaml` owns `XamlControlsResources`, generated `AppT<App>` initializes XAML resources, and `App::OnLaunched` retains the programmatic `MainWindow`. The local `task windows:build` command also creates a small web installer. It contains only md4a; when required, setup downloads the official Windows App Runtime 1.5 x64 and WebView2 Evergreen installers from Microsoft. Local outputs are explicitly named `*-setup-unsigned.exe`, and SmartScreen may warn.

The installer registers md4a through Windows `RegisteredApplications`, a Markdown ProgID, `OpenWithProgids`, and Capabilities for `.md` and `.markdown`. It deliberately never writes the protected `UserChoice` registry value. On first launch md4a asks once before opening Windows' app-specific Default Apps settings. **Settings → Default apps…** reopens that system UI. File associations invoke md4a with the document path, which the app loads at startup.

Release builds use the static MSVC runtime and force `/APPCONTAINER:NO`; Windows App SDK bootstrap auto-initialization remains enabled by the pinned NuGet package. Startup writes stage-only diagnostics (never document paths or contents) to `%LOCALAPPDATA%\md4a\startup.log`, and displays a native message box if a startup exception reaches the process boundary. CI verifies the PE is not AppContainer-enabled, rejects PDB/import-library leakage and setup files at or above 5 MiB, then installs the app with the default-app prompt disabled, requires the generated-XAML startup to reach `startup.complete`, checks that a window survives without a new Application Error Event ID 1000, opens a UTF-8 Markdown fixture through the command-line file-activation contract, and uninstalls the app. On failure it prints setup, startup, and Windows Application Event logs.

## Authenticode signing

Production signing runs in the protected GitHub environment `windows-production`. Configure one of these approaches without committing credentials:

- PFX: environment secret `MD4A_WINDOWS_SIGNING_CERTIFICATE_BASE64` containing the base64-encoded PFX, plus `MD4A_WINDOWS_SIGNING_PASSWORD`.
- Certificate store/cloud signing agent: make the certificate available to the runner and set `MD4A_WINDOWS_SIGNING_SHA1` to its thumbprint.

Optionally set environment variable `MD4A_WINDOWS_TIMESTAMP_URL`; it defaults to DigiCert's RFC 3161 timestamp endpoint. The build signs and verifies the app before packaging, then signs and verifies setup. A cloud-signing provider may expose its certificate through the SHA-1 route after its own authenticated setup step. No certificate, token, password, or private key belongs in the repository.


- Editor and Preview are shown side by side.
- Preview updates after every editor change and is rendered by `md4a_render` with raw HTML disabled.
- Open accepts `.md` and `.markdown`; Save writes UTF-8 `.md`.
- A `.md` or `.markdown` path passed on the command line is opened, including activation through the registered Open With association.
- Ctrl+N, Ctrl+O, Ctrl+S, and Ctrl+Shift+S invoke document commands.
- The first launch asks before opening Windows Default Apps settings; the Settings menu can reopen it later.
- Preview HTML has a restrictive content security policy; HTTPS and data images are allowed, scripts are not.

The MVP does not yet prompt to save dirty changes before New/Open/close and does not implement renderer packages.
