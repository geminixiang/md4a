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

This is an unpackaged WinUI 3 application. The Windows App SDK runtime must be installed on the target machine; Visual Studio installs it for development. A release installer and package identity are intentionally outside this minimal scaffold.

## Current behavior

- Editor and Preview are shown side by side.
- Preview updates after every editor change and is rendered by `md4a_render` with raw HTML disabled.
- Open accepts `.md` and `.markdown`; Save writes UTF-8 `.md`.
- Ctrl+N, Ctrl+O, Ctrl+S, and Ctrl+Shift+S invoke document commands.
- Preview HTML has a restrictive content security policy; HTTPS and data images are allowed, scripts are not.

The MVP does not yet prompt to save dirty changes before New/Open/close and does not implement renderer packages.
