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
$TemplatesSource = Join-Path $ProjectRoot "templates"
$ManualSource = Join-Path $ProjectRoot "docs\HR_Leave_Management_User_Manual.docx"

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

$TemplatesDestination = Join-Path $ReleaseDir "templates"
if (Test-Path $TemplatesDestination) {
    Remove-Item -LiteralPath $TemplatesDestination -Recurse -Force
}
Copy-Item -LiteralPath $TemplatesSource -Destination $TemplatesDestination -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $ReleaseDir "docs") -Force | Out-Null
Copy-Item -LiteralPath $ManualSource -Destination (Join-Path $ReleaseDir "docs\HR_Leave_Management_User_Manual.docx") -Force

$RequiredItems = @(
    "leave_management.exe",
    "flutter_windows.dll",
    "data",
    "stored_procedure",
    "templates",
    "docs",
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

Write-Host "Creating release zip: $ZipPath" -ForegroundColor Cyan

# Writing directly to a .zip lets antivirus/indexing tools map the archive
# before Compress-Archive has finished it. On Windows that can make Dispose()
# fail with "a file with a user-mapped section open" and leave a corrupt zip.
# Create an unrecognised temporary file first, validate it, then publish it.
$TempZipPath = Join-Path $ReleasesDir (".{0}.{1}.tmp" -f $ZipName, [guid]::NewGuid().ToString("N"))

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $ReleaseDir,
        $TempZipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    $Archive = [System.IO.Compression.ZipFile]::OpenRead($TempZipPath)
    try {
        if ($Archive.Entries.Count -eq 0) {
            throw "The generated release archive is empty."
        }
    }
    finally {
        $Archive.Dispose()
    }

    if (Test-Path $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }
    Move-Item -LiteralPath $TempZipPath -Destination $ZipPath
}
finally {
    if (Test-Path $TempZipPath) {
        Remove-Item -LiteralPath $TempZipPath -Force
    }
}

$Zip = Get-Item $ZipPath
$SizeMb = [math]::Round($Zip.Length / 1MB, 2)

Write-Host "Done: $($Zip.FullName) ($SizeMb MB)" -ForegroundColor Green
