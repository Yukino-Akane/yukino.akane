param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Repo = "Yukino-Akane/yukino.akane",
    [string]$Tag = "",
    [string]$PackageName = "yukino.akane",
    [switch]$SkipLaunch,
    [switch]$SkipBrowserSmoke,
    [switch]$KeepDownloadedAssets
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-ReleaseTag([string]$ExplicitTag, [string]$ProjectRoot, [string]$Repo) {
    if ($ExplicitTag) {
        return $ExplicitTag
    }

    Push-Location $ProjectRoot
    try {
        $latest = & gh release list --repo $Repo --limit 1 --json tagName | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $latest -or -not $latest[0].tagName) {
            throw "Unable to resolve latest release tag for $Repo."
        }
        return $latest[0].tagName
    }
    finally {
        Pop-Location
    }
}

function Get-Sha256FromFile([string]$Path) {
    $checksumText = [IO.File]::ReadAllText($Path)
    $expected = ([regex]::Match($checksumText, "(?i)\b[a-f0-9]{64}\b")).Value.ToUpperInvariant()
    if (-not $expected) {
        throw "No SHA256 hash found in $Path"
    }
    return $expected
}

function Resolve-DownloadedAsset([string]$Directory, [string]$Pattern, [string]$Description) {
    $asset = Get-ChildItem -LiteralPath $Directory -File -Filter $Pattern |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $asset) {
        throw "Missing downloaded $Description matching $Pattern in $Directory."
    }
    return $asset.FullName
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "gh CLI is required to download private release assets."
}

$project = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path
$verifyScript = Join-Path $project "verify-yukino.ps1"
if (-not (Test-Path -LiteralPath $verifyScript)) {
    throw "Missing verification script: $verifyScript"
}
$browserSmokeScript = Join-Path $project "scripts\Test-YukinoPostInstallBrowserSmoke.ps1"
if (-not (Test-Path -LiteralPath $browserSmokeScript)) {
    throw "Missing post-install Browser smoke script: $browserSmokeScript"
}

$releaseTag = Resolve-ReleaseTag -ExplicitTag $Tag -ProjectRoot $project -Repo $Repo
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("yukino-release-install-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    Write-Host "Release : $releaseTag"
    Write-Host "Repo    : $Repo"
    Write-Host "TempDir : $tempDir"

    Push-Location $project
    try {
        & gh release download $releaseTag --repo $Repo --dir $tempDir --clobber
        if ($LASTEXITCODE -ne 0) {
            throw "gh release download failed for $Repo $releaseTag."
        }
    }
    finally {
        Pop-Location
    }

    $msix = Resolve-DownloadedAsset -Directory $tempDir -Pattern "$PackageName*_x64.msix" -Description "MSIX"
    $checksum = Resolve-DownloadedAsset -Directory $tempDir -Pattern "SHA256SUMS.txt" -Description "checksum file"
    $installer = Resolve-DownloadedAsset -Directory $tempDir -Pattern "Install-YukinoRelease.ps1" -Description "installer"
    [void](Resolve-DownloadedAsset -Directory $tempDir -Pattern "Yukino.cer" -Description "certificate")

    $expectedHash = Get-Sha256FromFile -Path $checksum
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $msix).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA256 mismatch for downloaded MSIX. Expected $expectedHash, got $actualHash."
    }
    Write-Host "SHA256 verified: $actualHash"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -PackageName $PackageName
    if ($LASTEXITCODE -ne 0) {
        throw "Install-YukinoRelease.ps1 failed with exit code $LASTEXITCODE."
    }

    $pkg = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $pkg) {
        throw "Package $PackageName was not found after installation."
    }

    Write-Host "Installed package: $($pkg.PackageFullName)"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ProjectRoot $project -PackageName $PackageName
    if ($LASTEXITCODE -ne 0) {
        throw "verify-yukino.ps1 failed after release installation."
    }

    if (-not $SkipLaunch) {
        $exe = Join-Path $pkg.InstallLocation "app\Yukino.exe"
        if (-not (Test-Path -LiteralPath $exe)) {
            throw "Installed executable not found: $exe"
        }
        $launchStart = Get-Date
        $process = Start-Process -FilePath $exe -PassThru
        Start-Sleep -Seconds 8
        $running = @(Get-Process -Name "Yukino" -ErrorAction SilentlyContinue)
        if ($running.Count -eq 0) {
            throw "Yukino did not remain running after launch smoke."
        }
        Write-Host "Launch smoke: started process $($process.Id); running Yukino process count $($running.Count)."

        if (-not $SkipBrowserSmoke) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $browserSmokeScript -ProjectRoot $project -PackageName $PackageName -MinLogTime $launchStart
            if ($LASTEXITCODE -ne 0) {
                throw "Test-YukinoPostInstallBrowserSmoke.ps1 failed after release installation."
            }
        }
    }
    elseif (-not $SkipBrowserSmoke) {
        Write-Host "Post-install Browser smoke skipped because -SkipLaunch was set."
    }

    [pscustomobject]@{
        Tag = $releaseTag
        Repo = $Repo
        Msix = $msix
        MsixSha256 = $actualHash
        PackageFullName = $pkg.PackageFullName
        InstallLocation = $pkg.InstallLocation
        TempDir = $tempDir
    }
}
finally {
    if (-not $KeepDownloadedAssets -and (Test-Path -LiteralPath $tempDir)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
        Write-Host "Removed $tempDir"
    }
    elseif ($KeepDownloadedAssets) {
        Write-Host "Kept downloaded assets in $tempDir"
    }
}
