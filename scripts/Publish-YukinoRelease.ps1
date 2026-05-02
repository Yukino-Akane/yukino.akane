param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Repo = "Yukino-Akane/yukino.akane",
    [string]$PackageName = "yukino.akane",
    [string]$DisplayName = "Yukino",
    [string]$Tag = "",
    [string]$Title = "",
    [string]$Target = "master",
    [string]$MsixPath = "",
    [string]$CertificatePath = "",
    [string]$InstallerPath = "",
    [string]$ChecksumPath = "",
    [string]$ReleaseNotesPath = "",
    [switch]$Latest,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-ReleaseFile([string]$ExplicitPath, [string]$Directory, [string]$Pattern, [string]$Description) {
    if ($ExplicitPath) {
        return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
    }

    $candidate = Get-ChildItem -LiteralPath $Directory -File -Filter $Pattern -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }

    throw "Cannot find $Description. Pass an explicit path or place a matching $Pattern file in $Directory."
}

function Write-AsciiFile([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text.TrimEnd() + "`r`n", [Text.ASCIIEncoding]::new())
}

$project = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path
$outDir = Join-Path $project "out"
$scriptsDir = Join-Path $project "scripts"
if (-not (Test-Path -LiteralPath $outDir)) {
    throw "Missing output directory: $outDir"
}

$msix = Resolve-ReleaseFile -ExplicitPath $MsixPath -Directory $outDir -Pattern "$PackageName*_x64.msix" -Description "Yukino MSIX package"
$certificate = Resolve-ReleaseFile -ExplicitPath $CertificatePath -Directory $outDir -Pattern "$DisplayName.cer" -Description "Yukino certificate"
$installer = if ($InstallerPath) {
    (Resolve-Path -LiteralPath $InstallerPath -ErrorAction Stop).Path
}
else {
    $sourceInstaller = Join-Path $scriptsDir "Install-YukinoRelease.ps1"
    if (-not (Test-Path -LiteralPath $sourceInstaller)) {
        throw "Missing installer template: $sourceInstaller"
    }
    $targetInstaller = Join-Path $outDir "Install-YukinoRelease.ps1"
    Copy-Item -LiteralPath $sourceInstaller -Destination $targetInstaller -Force
    $targetInstaller
}

$msixName = Split-Path -Leaf $msix
$versionMatch = [regex]::Match($msixName, "^(?<package>.+)_(?<version>\d+\.\d+\.\d+\.\d+)_x64\.msix$")
if (-not $versionMatch.Success) {
    throw "Cannot infer package version from MSIX name: $msixName"
}
$targetVersion = $versionMatch.Groups["version"].Value
if (-not $Tag) {
    $Tag = "v$targetVersion-yukino.1"
}
if (-not $Title) {
    $Title = "$DisplayName Codex $targetVersion"
}

$checksum = if ($ChecksumPath) {
    (Resolve-Path -LiteralPath $ChecksumPath -ErrorAction Stop).Path
}
else {
    Join-Path $outDir "SHA256SUMS.txt"
}
$msixHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $msix).Hash.ToUpperInvariant()
Write-AsciiFile -Path $checksum -Text "$msixHash  $msixName"

if (-not $ReleaseNotesPath) {
    $safeTag = $Tag -replace '[^\w.\-]+', '-'
    $ReleaseNotesPath = Join-Path $outDir "release-notes-$safeTag.md"
}

$notes = @"
## $Title

This private Yukino build is based on the installed OpenAI Codex Desktop package and is published from this repository's reproducible rebuild scripts.

### Included Assets

- ``$msixName``
- ``Yukino.cer``
- ``SHA256SUMS.txt``
- ``Install-YukinoRelease.ps1``

### Verification

- ``verify-yukino.ps1`` is expected to pass before publishing.
- MSIX SHA256: ``$msixHash``

### Install

Run ``Install-YukinoRelease.ps1`` from the release assets. The installer imports ``Yukino.cer``, closes any running Yukino process, and installs ``$msixName``.
"@
Write-AsciiFile -Path $ReleaseNotesPath -Text $notes

$verifyScript = Join-Path $project "verify-yukino.ps1"
if (-not (Test-Path -LiteralPath $verifyScript)) {
    throw "Missing verification script: $verifyScript"
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ProjectRoot $project -PackageName $PackageName
if ($LASTEXITCODE -ne 0) {
    throw "verify-yukino.ps1 failed; refusing to publish release."
}

$assets = @($msix, $certificate, $checksum, $installer)
foreach ($asset in $assets) {
    if (-not (Test-Path -LiteralPath $asset)) {
        throw "Missing release asset: $asset"
    }
}

Write-Host ""
Write-Host "Release assets prepared:"
foreach ($asset in $assets) {
    $item = Get-Item -LiteralPath $asset
    Write-Host ("- {0} ({1:N0} bytes)" -f $item.FullName, $item.Length)
}
Write-Host "Release notes: $ReleaseNotesPath"
Write-Host "Tag          : $Tag"
Write-Host "Target       : $Target"
Write-Host "Repo         : $Repo"

if ($DryRun) {
    Write-Host "Dry-run mode: skipping gh release create."
    return [pscustomobject]@{
        Tag = $Tag
        Title = $Title
        Msix = $msix
        ChecksumPath = $checksum
        ReleaseNotesPath = $ReleaseNotesPath
        DryRun = $true
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "gh CLI is required to publish a release."
}

$existing = & gh release view $Tag --repo $Repo --json tagName 2>$null
if ($LASTEXITCODE -eq 0 -and $existing) {
    throw "Release already exists: $Tag"
}

$arguments = @(
    "release", "create", $Tag,
    $msix, $certificate, $checksum, $installer,
    "--repo", $Repo,
    "--target", $Target,
    "--title", $Title,
    "--notes-file", $ReleaseNotesPath
)
if ($Latest) {
    $arguments += "--latest"
}

& gh @arguments
if ($LASTEXITCODE -ne 0) {
    throw "gh release create failed."
}
