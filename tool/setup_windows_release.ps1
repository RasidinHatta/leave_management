param(
    [string]$InstallPath = "",
    [switch]$DesktopShortcut
)

$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppExe = "leave_management.exe"
$AppName = "HR Leave Management"
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

Write-Host ""
Write-Host "Installing to: $InstallPath" -ForegroundColor Cyan

$ExcludedNames = @("setup.ps1", "setup.bat")
Get-ChildItem -LiteralPath $SourceDir -Force | Where-Object {
    $ExcludedNames -notcontains $_.Name
} | ForEach-Object {
    $Destination = Join-Path $InstallPath $_.Name
    if ($_.PSIsContainer) {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    } else {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Force
    }
}

$InstalledExe = Join-Path $InstallPath $AppExe
if (-not (Test-Path $InstalledExe)) {
    throw "Install failed: $InstalledExe was not copied."
}

if ($DesktopShortcut) {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $ShortcutPath = Join-Path $DesktopPath "$AppName.lnk"
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $InstalledExe
    $Shortcut.WorkingDirectory = $InstallPath
    $Shortcut.IconLocation = $InstalledExe
    $Shortcut.Save()
    Write-Host "Desktop shortcut created: $ShortcutPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Install complete." -ForegroundColor Green
Write-Host "Run: $InstalledExe"
