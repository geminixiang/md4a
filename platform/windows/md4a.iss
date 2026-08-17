#ifndef ArtifactLabel
#define ArtifactLabel "unsigned"
#endif
#define AppName "md4a"
#define AppPublisher "md4a"
#define AppExeName "Md4a.exe"
#define AppProgId "md4a.Markdown"
#define RuntimeUrl "https://aka.ms/windowsappsdk/1.5/latest/windowsappruntimeinstall-x64.exe"
#define WebViewUrl "https://go.microsoft.com/fwlink/p/?LinkId=2124703"

[Setup]
AppId={{A3A570B2-EEA0-4C12-84A4-5B28EFB4DA41}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\md4a
DefaultGroupName=md4a
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=md4a-{#AppVersion}-windows-x64-setup-{#ArtifactLabel}
SetupIconFile=assets\md4a.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\Md4a.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Md4a.pri"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Microsoft.WindowsAppRuntime.Bootstrap.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\assets\md4a.ico"; DestDir: "{app}\assets"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\md4a"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\assets\md4a.ico"
Name: "{autodesktop}\md4a"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\assets\md4a.ico"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Registry]
Root: HKLM; Subkey: "Software\Classes\{#AppProgId}"; ValueType: string; ValueName: ""; ValueData: "Markdown document"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\{#AppProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\assets\md4a.ico"
Root: HKLM; Subkey: "Software\Classes\{#AppProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""
Root: HKLM; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: none; ValueName: "{#AppProgId}"; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\.markdown\OpenWithProgids"; ValueType: none; ValueName: "{#AppProgId}"; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\md4a\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "md4a"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\md4a\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Read and edit Markdown documents"
Root: HKLM; Subkey: "Software\md4a\Capabilities\FileAssociations"; ValueType: string; ValueName: ".md"; ValueData: "{#AppProgId}"
Root: HKLM; Subkey: "Software\md4a\Capabilities\FileAssociations"; ValueType: string; ValueName: ".markdown"; ValueData: "{#AppProgId}"
Root: HKLM; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "md4a"; ValueData: "Software\md4a\Capabilities"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch md4a"; Flags: nowait postinstall skipifsilent

[Code]
const
  RuntimeFile = 'WindowsAppRuntimeInstall-x64.exe';
  WebViewFile = 'MicrosoftEdgeWebview2Setup.exe';

function WindowsAppRuntimeInstalled: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -Command "if (Get-AppxPackage -AllUsers -Name Microsoft.WindowsAppRuntime.1.5 -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

function WebViewInstalled: Boolean;
var
  Version: String;
begin
  Result := RegQueryStringValue(HKLM64,
    'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7E5F6-6A72-5A2A-A7C1-59F6F4B3D24D}', 'pv', Version) or
    RegQueryStringValue(HKLM32,
    'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7E5F6-6A72-5A2A-A7C1-59F6F4B3D24D}', 'pv', Version);
end;

function InstallPrerequisite(const Name, Url, FileName, Parameters: String): Boolean;
var
  ResultCode: Integer;
  DownloadPath: String;
begin
  Result := False;
  try
    DownloadTemporaryFile(Url, FileName, '', nil);
    DownloadPath := ExpandConstant('{tmp}\' + FileName);
  except
    MsgBox('Could not download ' + Name + '. Check your internet connection and retry.' + #13#10 +
      'Installer log: ' + ExpandConstant('{log}'), mbError, MB_OK);
    Exit;
  end;
  if not Exec(DownloadPath, Parameters, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
  begin
    MsgBox('Could not start the ' + Name + ' installer.' + #13#10 + 'Installer log: ' + ExpandConstant('{log}'), mbError, MB_OK);
    Exit;
  end;
  if ResultCode <> 0 then
  begin
    MsgBox(Name + ' installation failed with exit code ' + IntToStr(ResultCode) + '.' + #13#10 +
      'Installer log: ' + ExpandConstant('{log}'), mbError, MB_OK);
    Exit;
  end;
  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not WindowsAppRuntimeInstalled then
    if not InstallPrerequisite('Windows App Runtime 1.5', '{#RuntimeUrl}', RuntimeFile, '--quiet') then
    begin
      Result := 'Windows App Runtime 1.5 is required. Installation did not complete.';
      Exit;
    end;
  if not WebViewInstalled then
    if not InstallPrerequisite('Microsoft Edge WebView2 Runtime', '{#WebViewUrl}', WebViewFile, '/silent /install') then
      Result := 'Microsoft Edge WebView2 Runtime is required. Installation did not complete.';
end;
