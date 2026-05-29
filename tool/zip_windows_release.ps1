param(
    [string]$Version = "",
    [switch]$Build
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$ReleasesDir = Join-Path $ProjectRoot "releases"
$SetupPs1Source = Join-Path $PSScriptRoot "setup_windows_release.ps1"
$SetupBatSource = Join-Path $PSScriptRoot "setup_windows_release.bat"

if ([string]::IsNullOrWhiteSpace($Version)) {
    if (-not (Test-Path $PubspecPath)) {
        throw "pubspec.yaml not found: $PubspecPath"
    }

    $VersionLine = Get-Content $PubspecPath | Where-Object { $_ -match "^\s*version\s*:" } | Select-Object -First 1
    if (-not $VersionLine) {
        throw "No version line found in pubspec.yaml. Example: version: 1.0.0+1"
    }

    $Version = ($VersionLine -replace "^\s*version\s*:\s*", "").Trim()
    $Version = ($Version -split "\+")[0]
}

$ZipName = "leave_management_windows_release_$Version.zip"
$ZipPath = Join-Path $ReleasesDir $ZipName

Set-Location $ProjectRoot

if ($Build) {
    Write-Host "Building Windows release..." -ForegroundColor Cyan
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Windows release build failed. Release zip was not created."
    }
}

if (-not (Test-Path $ReleaseDir)) {
    throw "Release folder not found: $ReleaseDir. Run flutter build windows --release first, or run this script with -Build."
}

$RequiredItems = @(
    "leave_management.exe",
    "flutter_windows.dll",
    "data",
    "stored_procedure",
    "config.ini"
)

foreach ($Item in $RequiredItems) {
    $Path = Join-Path $ReleaseDir $Item
    if (-not (Test-Path $Path)) {
        throw "Required release item missing: $Path"
    }
}

Copy-Item -LiteralPath $SetupPs1Source -Destination (Join-Path $ReleaseDir "setup.ps1") -Force
Copy-Item -LiteralPath $SetupBatSource -Destination (Join-Path $ReleaseDir "setup.bat") -Force

if (-not (Test-Path $ReleasesDir)) {
    New-Item -ItemType Directory -Path $ReleasesDir | Out-Null
}

if (Test-Path $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

Write-Host "Creating release zip: $ZipPath" -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $ZipPath -Force

$Zip = Get-Item $ZipPath
$SizeMb = [math]::Round($Zip.Length / 1MB, 2)

Write-Host "Done: $($Zip.FullName) ($SizeMb MB)" -ForegroundColor Green
