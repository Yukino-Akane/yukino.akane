param(
    [Parameter(Mandatory=$true)][string]$SourceManifestPath,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$AuditPath,
    [string]$DisplayName = "Yukino"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-YukinoFileSha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function ConvertTo-YukinoRelativePath([string]$Root, [string]$Path) {
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
    $normalizedPath = [IO.Path]::GetFullPath($Path)
    if (-not $normalizedPath.StartsWith($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside root. Root=$normalizedRoot Path=$normalizedPath"
    }
    return $normalizedPath.Substring($normalizedRoot.Length).TrimStart([char[]]@('\', '/')).Replace("\", "/")
}

function Get-YukinoInventory([string]$Root) {
    $inventory = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object {
        $relative = ConvertTo-YukinoRelativePath $Root $_.FullName
        $inventory[$relative] = [ordered]@{
            path = $relative
            sha256 = Get-YukinoFileSha256 $_.FullName
            bytes = $_.Length
        }
    }
    return $inventory
}

function Test-YukinoPattern([string]$Path, [string[]]$Patterns) {
    foreach ($pattern in $Patterns) {
        if ($Path -like $pattern) {
            return $true
        }
    }
    return $false
}

$sourceManifest = Get-Content -LiteralPath $SourceManifestPath -Raw | ConvertFrom-Json
$output = (Resolve-Path -LiteralPath $OutputRoot -ErrorAction Stop).Path
$outputInventory = Get-YukinoInventory $output

$sourceByPath = @{}
foreach ($artifact in $sourceManifest.artifacts) {
    $sourceByPath[$artifact.path] = $artifact
}

$expectedAddedPatterns = @(
    "app/$DisplayName.exe",
    "Assets/*",
    "app/resources/icon.ico",
    "app/resources/scripts/*",
    "app/resources/app.asar.unpacked/*"
)
$expectedChangedPatterns = @(
    "AppxManifest.xml",
    "app/resources/app.asar",
    "app/resources/icon.ico",
    "app/resources/plugins/*",
    "Assets/*"
)
$expectedRemovedPatterns = @(
    "app/Codex.exe",
    "AppxBlockMap.xml",
    "AppxSignature.p7x",
    "AppxMetadata/*",
    "microsoft.system.package.metadata/*"
)

$expectedAdded = New-Object System.Collections.Generic.List[string]
$unexpectedAdded = New-Object System.Collections.Generic.List[string]
$expectedChanged = New-Object System.Collections.Generic.List[string]
$unexpectedChanged = New-Object System.Collections.Generic.List[string]
$expectedRemoved = New-Object System.Collections.Generic.List[string]
$unexpectedRemoved = New-Object System.Collections.Generic.List[string]

foreach ($path in ($outputInventory.Keys | Sort-Object)) {
    if (-not $sourceByPath.ContainsKey($path)) {
        if (Test-YukinoPattern $path $expectedAddedPatterns) {
            $expectedAdded.Add($path)
        }
        else {
            $unexpectedAdded.Add($path)
        }
        continue
    }

    if ($outputInventory[$path].sha256 -ne $sourceByPath[$path].sha256) {
        if (Test-YukinoPattern $path $expectedChangedPatterns) {
            $expectedChanged.Add($path)
        }
        else {
            $unexpectedChanged.Add($path)
        }
    }
}

foreach ($path in ($sourceByPath.Keys | Sort-Object)) {
    if (-not $outputInventory.ContainsKey($path)) {
        if (Test-YukinoPattern $path $expectedRemovedPatterns) {
            $expectedRemoved.Add($path)
        }
        else {
            $unexpectedRemoved.Add($path)
        }
    }
}

$staleMetadata = @($outputInventory.Keys | Where-Object { $_ -eq "AppxSignature.p7x" -or $_ -eq "AppxBlockMap.xml" -or $_ -like "AppxMetadata/*" -or $_ -like "microsoft.system.package.metadata/*" })
if ($staleMetadata.Count -gt 0) {
    $unexpectedAdded.AddRange([string[]]$staleMetadata)
}

$audit = [ordered]@{
    status = "passed"
    generatedAt = [DateTime]::UtcNow.ToString("o")
    sourceManifestPath = (Resolve-Path -LiteralPath $SourceManifestPath).Path
    outputRoot = $output
    expectedAdded = @($expectedAdded | Sort-Object -Unique)
    unexpectedAdded = @($unexpectedAdded | Sort-Object -Unique)
    expectedChanged = @($expectedChanged | Sort-Object -Unique)
    unexpectedChanged = @($unexpectedChanged | Sort-Object -Unique)
    expectedRemoved = @($expectedRemoved | Sort-Object -Unique)
    unexpectedRemoved = @($unexpectedRemoved | Sort-Object -Unique)
}

if ($audit.unexpectedAdded.Count -gt 0 -or $audit.unexpectedChanged.Count -gt 0 -or $audit.unexpectedRemoved.Count -gt 0) {
    $audit.status = "failed"
}

$auditDir = Split-Path -Parent $AuditPath
if (-not (Test-Path -LiteralPath $auditDir)) {
    New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
}
[IO.File]::WriteAllText($AuditPath, ($audit | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))

if ($audit.status -ne "passed") {
    throw "Yukino build audit failed. Unexpected added: $($audit.unexpectedAdded -join ', '); unexpected changed: $($audit.unexpectedChanged -join ', '); unexpected removed: $($audit.unexpectedRemoved -join ', ')"
}

Write-Host "Wrote Yukino build audit: $AuditPath"
