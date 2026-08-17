#define AppName "md4a"
#define AppPublisher "md4a"
#define AppExeName "Md4a.Windows.exe"

[Setup]
AppId={{A3A570B2-EEA0-4C12-84A4-5B28EFB4DA41}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\md4a
DefaultGroupName=md4a
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=md4a-{#AppVersion}-windows-x64-setup
SetupIconFile=assets\md4a.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\Md4a.Windows.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Md4a.Windows.pri"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Microsoft.WindowsAppRuntime.Bootstrap.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\assets\md4a.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "{#RuntimeInstaller}"; DestDir: "{tmp}"; DestName: "WindowsAppRuntimeInstall.exe"; Flags: deleteafterinstall
Source: "{#WebViewInstaller}"; DestDir: "{tmp}"; DestName: "MicrosoftEdgeWebview2Setup.exe"; Flags: deleteafterinstall

[Icons]
Name: "{autoprograms}\md4a"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\assets\md4a.ico"
Name: "{autodesktop}\md4a"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\assets\md4a.ico"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{tmp}\WindowsAppRuntimeInstall.exe"; Parameters: "--quiet"; StatusMsg: "Installing Windows App Runtime…"; Flags: waituntilterminated runhidden
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "Installing Microsoft Edge WebView2 Runtime…"; Flags: waituntilterminated runhidden
Filename: "{app}\{#AppExeName}"; Description: "Launch md4a"; Flags: nowait postinstall skipifsilent
