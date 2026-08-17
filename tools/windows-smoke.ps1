param(
    [Parameter(Mandatory = $true)][string]$SetupPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$env:MD4A_SKIP_DEFAULT_APP_PROMPT = "1"
$InstallDir = Join-Path $env:ProgramFiles "md4a"
$AppPath = Join-Path $InstallDir "Md4a.Windows.exe"
$SetupLogPath = Join-Path $env:RUNNER_TEMP "md4a-setup.log"
$StartupLogPath = Join-Path $env:LOCALAPPDATA "md4a\startup.log"
$SmokeStarted = Get-Date

function Get-NewApplicationCrashes {
    @(Get-WinEvent -FilterHashtable @{ LogName = "Application"; Id = 1000; StartTime = $SmokeStarted } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "Md4a\.Windows\.exe|md4a" })
}

function Show-Diagnostics {
    Write-Host "--- setup log ---"
    if (Test-Path $SetupLogPath) { Get-Content $SetupLogPath -Tail 300 }
    Write-Host "--- startup log ---"
    if (Test-Path $StartupLogPath) { Get-Content $StartupLogPath -Tail 300 }
    Write-Host "--- recent Application event log ---"
    Get-WinEvent -FilterHashtable @{ LogName = "Application"; StartTime = $SmokeStarted } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -in @("Application Error", "Windows Error Reporting", ".NET Runtime") -or $_.Message -match "Md4a|md4a" } |
        Select-Object -First 50 TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Format-List
}

function Wait-ForWindow([System.Diagnostics.Process]$Process, [string]$ExpectedTitle = "") {
    $Deadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $Process.Refresh()
        if ($Process.HasExited) { throw "md4a exited during launch with code $($Process.ExitCode)." }
    } until ($Process.MainWindowHandle -ne 0 -or (Get-Date) -ge $Deadline)
    if ($Process.MainWindowHandle -eq 0) { throw "md4a did not create a top-level window within 30 seconds." }
    if ($ExpectedTitle) {
        $TitleDeadline = (Get-Date).AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 250
            $Process.Refresh()
        } until ($Process.MainWindowTitle -like "*$ExpectedTitle*" -or (Get-Date) -ge $TitleDeadline)
        if ($Process.MainWindowTitle -notlike "*$ExpectedTitle*") {
            throw "md4a window title did not contain '$ExpectedTitle' (actual: '$($Process.MainWindowTitle)')."
        }
    }
}

try {
    Remove-Item $StartupLogPath -Force -ErrorAction SilentlyContinue
    $Install = Start-Process -FilePath $SetupPath -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG=$SetupLogPath" -Wait -PassThru
    if ($Install.ExitCode -ne 0) { throw "Installer exited with code $($Install.ExitCode)." }
    if (-not (Test-Path $AppPath)) { throw "Installed executable was not found: $AppPath" }

    $App = Start-Process -FilePath $AppPath -PassThru
    Wait-ForWindow $App
    Start-Sleep -Seconds 5
    $App.Refresh()
    if ($App.HasExited) { throw "md4a exited before the five-second survival gate." }

    if (-not (Test-Path $StartupLogPath)) { throw "Startup stage log was not created: $StartupLogPath" }
    $StartupLog = Get-Content $StartupLogPath -Raw
    if ($StartupLog -notmatch "startup\.complete") { throw "Startup log did not reach startup.complete." }
    if ((Get-NewApplicationCrashes).Count -ne 0) { throw "A new Application Error Event ID 1000 was recorded for md4a." }

    $Fixture = Join-Path $env:RUNNER_TEMP "md4a-smoke.md"
    Set-Content -Path $Fixture -Value "# Windows activation smoke`r`n`r`nUTF-8 中文 🚀" -Encoding utf8
    $ActivatedApp = Start-Process -FilePath $AppPath -ArgumentList $Fixture -PassThru
    Wait-ForWindow $ActivatedApp "md4a-smoke.md"
    Start-Sleep -Seconds 2
    $ActivatedApp.Refresh()
    if ($ActivatedApp.HasExited) { throw "md4a file-activation process did not survive." }
    if ((Get-NewApplicationCrashes).Count -ne 0) { throw "File activation produced an Application Error Event ID 1000." }

    Stop-Process -Id $ActivatedApp.Id -Force
    Stop-Process -Id $App.Id -Force

    $Uninstaller = Get-ChildItem $InstallDir -Filter "unins*.exe" | Select-Object -First 1
    if (-not $Uninstaller) { throw "Uninstaller was not created." }
    $Uninstall = Start-Process -FilePath $Uninstaller.FullName -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART" -Wait -PassThru
    if ($Uninstall.ExitCode -ne 0) { throw "Uninstaller exited with code $($Uninstall.ExitCode)." }
    if (Test-Path $AppPath) { throw "Application executable remains after uninstall." }
    Write-Host "Windows install, generated-XAML startup, file activation, survival, Event ID 1000, and uninstall smoke test passed."
} catch {
    Show-Diagnostics
    throw
}
