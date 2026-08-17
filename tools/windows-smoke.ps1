param(
    [Parameter(Mandatory = $true)][string]$SetupPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$env:MD4A_SKIP_DEFAULT_APP_PROMPT = "1"
$InstallDir = Join-Path $env:ProgramFiles "md4a"
$AppPath = Join-Path $InstallDir "Md4a.Windows.exe"
$LogPath = Join-Path $env:RUNNER_TEMP "md4a-setup.log"

function Show-Diagnostics {
    Write-Host "--- setup log ---"
    if (Test-Path $LogPath) { Get-Content $LogPath -Tail 300 }
    Write-Host "--- recent Application event log ---"
    Get-WinEvent -FilterHashtable @{ LogName = "Application"; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -in @("Application Error", "Windows Error Reporting", ".NET Runtime") -or $_.Message -match "Md4a|md4a" } |
        Select-Object -First 50 TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Format-List
}

try {
    $Install = Start-Process -FilePath $SetupPath -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG=$LogPath" -Wait -PassThru
    if ($Install.ExitCode -ne 0) { throw "Installer exited with code $($Install.ExitCode)." }
    if (-not (Test-Path $AppPath)) { throw "Installed executable was not found: $AppPath" }

    $App = Start-Process -FilePath $AppPath -PassThru
    $Deadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $App.Refresh()
        if ($App.HasExited) { throw "md4a exited during launch with code $($App.ExitCode)." }
    } until ($App.MainWindowHandle -ne 0 -or (Get-Date) -ge $Deadline)
    if ($App.MainWindowHandle -eq 0) { throw "md4a did not create a top-level window within 30 seconds." }
    Start-Sleep -Seconds 5
    $App.Refresh()
    if ($App.HasExited) { throw "md4a exited before the five-second survival gate." }
    Stop-Process -Id $App.Id -Force

    $Uninstaller = Get-ChildItem $InstallDir -Filter "unins*.exe" | Select-Object -First 1
    if (-not $Uninstaller) { throw "Uninstaller was not created." }
    $Uninstall = Start-Process -FilePath $Uninstaller.FullName -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART" -Wait -PassThru
    if ($Uninstall.ExitCode -ne 0) { throw "Uninstaller exited with code $($Uninstall.ExitCode)." }
    if (Test-Path $AppPath) { throw "Application executable remains after uninstall." }
    Write-Host "Windows install, launch, window survival, and uninstall smoke test passed."
} catch {
    Show-Diagnostics
    throw
}
