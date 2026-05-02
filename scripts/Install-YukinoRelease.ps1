param(
    [string]$MsixPath = "",
    [string]$CertPath = "",
    [string]$Sha256Path = "",
    [string]$PackageName = "yukino.akane",
    [switch]$UninstallExisting
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-ReleaseFile([string]$ExplicitPath, [string]$Pattern, [string]$Description) {
    if ($ExplicitPath) {
        $resolved = Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop
        return $resolved.Path
    }

    $candidate = Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter $Pattern |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }

    $parentCandidate = Get-ChildItem -LiteralPath (Split-Path -Parent $PSScriptRoot) -File -Filter $Pattern |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($parentCandidate) {
        return $parentCandidate.FullName
    }

    throw "Cannot find $Description. Pass an explicit path or place a matching $Pattern file beside this script."
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Import-YukinoCertificate([string]$Path) {
    $storeRoot = if (Test-Administrator) { "LocalMachine" } else { "CurrentUser" }
    foreach ($store in @("Root", "TrustedPeople")) {
        $storePath = "Cert:\$storeRoot\$store"
        Write-Host "Importing certificate into $storePath"
        Import-Certificate -FilePath $Path -CertStoreLocation $storePath | Out-Null
    }
}

function Test-Sha256File([string]$FilePath, [string]$ChecksumPath) {
    if (-not $ChecksumPath) {
        return
    }

    if (-not (Test-Path -LiteralPath $ChecksumPath)) {
        throw "SHA256 file not found: $ChecksumPath"
    }

    $checksumText = [IO.File]::ReadAllText($ChecksumPath)
    $expected = ([regex]::Match($checksumText, "(?i)\b[a-f0-9]{64}\b")).Value.ToUpperInvariant()
    if (-not $expected) {
        throw "No SHA256 hash found in $ChecksumPath"
    }

    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $FilePath).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "SHA256 mismatch for $FilePath. Expected $expected, got $actual."
    }

    Write-Host "SHA256 verified: $actual"
}

$msix = Resolve-ReleaseFile -ExplicitPath $MsixPath -Pattern "$PackageName*_x64.msix" -Description "Yukino MSIX package"
$cert = Resolve-ReleaseFile -ExplicitPath $CertPath -Pattern "Yukino.cer" -Description "Yukino certificate"
if (-not $Sha256Path) {
    $nearbySha = @(
        "$msix.sha256",
        (Join-Path (Split-Path -Parent $msix) "SHA256SUMS.txt")
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($nearbySha) {
        $Sha256Path = $nearbySha
    }
}

Write-Host "MSIX : $msix"
Write-Host "Cert : $cert"

Test-Sha256File -FilePath $msix -ChecksumPath $Sha256Path
Import-YukinoCertificate -Path $cert

Get-Process -Name "Yukino" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if ($UninstallExisting) {
    $existing = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Removing existing package $($existing.PackageFullName)"
        Remove-AppxPackage -Package $existing.PackageFullName
    }
}

Write-Host "Installing Yukino package..."
Add-AppxPackage -Path $msix -ForceApplicationShutdown -ForceUpdateFromAnyVersion
Write-Host "Yukino package installed."
