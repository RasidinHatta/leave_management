param(
    [string]$InstallPath = "",
    [switch]$DesktopShortcut
)

$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppExe = "leave_management.exe"
$AppName = "SmartLMS"
$InstallFolderName = "SmartLMS"
$DefaultInstallPath = Join-Path $env:LOCALAPPDATA "Programs\$InstallFolderName"

Write-Host ""
Write-Host "HR Leave Management installer" -ForegroundColor Cyan
Write-Host "Source: $SourceDir"
Write-Host ""

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InputPath = Read-Host "Install parent folder [$DefaultInstallPath]"
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $InstallPath = $DefaultInstallPath
    } else {
        $InstallPath = $InputPath.Trim('"')
    }
}

if ((Split-Path -Leaf $InstallPath) -ne $InstallFolderName) {
    $InstallPath = Join-Path $InstallPath $InstallFolderName
}

if (-not $DesktopShortcut) {
    $ShortcutAnswer = Read-Host "Create desktop shortcut? [Y/n]"
    $DesktopShortcut = [string]::IsNullOrWhiteSpace($ShortcutAnswer) -or
        $ShortcutAnswer.Trim().ToLowerInvariant().StartsWith("y")
}

$SourceExe = Join-Path $SourceDir $AppExe
if (-not (Test-Path $SourceExe)) {
    throw "Cannot find $AppExe beside setup.ps1. Extract the release zip first, then run setup.ps1 from the extracted folder."
}

if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath | Out-Null
}

$InstalledExe = Join-Path $InstallPath $AppExe
$IsUpdate = Test-Path $InstalledExe

if ($IsUpdate) {
    Write-Host ""
    Write-Host "Existing installation found. Updating installed files..." -ForegroundColor Yellow

    $RunningProcesses = Get-Process -Name "leave_management" -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -eq $InstalledExe
    }

    if ($RunningProcesses) {
        $StopAnswer = Read-Host "SmartLMS is currently running. Close it now so files can be replaced? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($StopAnswer) -or $StopAnswer.Trim().ToLowerInvariant().StartsWith("y")) {
            $RunningProcesses | Stop-Process -Force
            Start-Sleep -Seconds 1
        } else {
            throw "Install cancelled because SmartLMS is still running."
        }
    }
}

Write-Host ""
if ($IsUpdate) {
    Write-Host "Updating: $InstallPath" -ForegroundColor Cyan
} else {
    Write-Host "Installing to: $InstallPath" -ForegroundColor Cyan
}

& robocopy $SourceDir $InstallPath /E /XF setup.ps1 setup.bat /R:2 /W:1 | Out-Host
$RoboCopyExitCode = $LASTEXITCODE
if ($RoboCopyExitCode -ge 8) {
    throw "Install file copy failed. Robocopy exit code: $RoboCopyExitCode"
}

if (-not (Test-Path $InstalledExe)) {
    throw "Install failed: $InstalledExe was not copied."
}

if ($DesktopShortcut) {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $ShortcutPath = Join-Path $DesktopPath "$AppName.lnk"
    if (Test-Path $ShortcutPath) {
        Remove-Item -LiteralPath $ShortcutPath -Force
    }
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $InstalledExe
    $Shortcut.WorkingDirectory = $InstallPath
    $Shortcut.IconLocation = $InstalledExe
    $Shortcut.Save()
    Write-Host "Desktop shortcut created: $ShortcutPath" -ForegroundColor Green
}

Write-Host ""
if ($IsUpdate) {
    Write-Host "Update complete." -ForegroundColor Green
} else {
    Write-Host "Install complete." -ForegroundColor Green
}
Write-Host "Run: $InstalledExe"
