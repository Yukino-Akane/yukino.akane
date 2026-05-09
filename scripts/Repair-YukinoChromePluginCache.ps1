param(
    [string]$YukinoHome = "$env:USERPROFILE\.yukino",
    [string]$MarketplaceRoot = "",
    [string]$PluginVersion = "",
    [string]$NativeHostName = "com.openai.codexextension"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-ExistingPath([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing ${Description}: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Copy-DirectoryContent([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Get-PendingDeleteManifestPath([string]$ChromeCacheRoot) {
    return Join-Path $ChromeCacheRoot "pending-delete.jsonl"
}

function Add-PendingDeletePath([string]$ChromeCacheRoot, [string]$Path, [string]$Reason) {
    New-Item -ItemType Directory -Path $ChromeCacheRoot -Force | Out-Null
    $record = [pscustomobject]@{
        path = $Path
        reason = $Reason
        recordedAt = (Get-Date).ToUniversalTime().ToString("o")
    }
    $json = $record | ConvertTo-Json -Compress
    Add-Content -LiteralPath (Get-PendingDeleteManifestPath -ChromeCacheRoot $ChromeCacheRoot) -Value $json -Encoding UTF8
}

function Invoke-PendingDeleteCleanup([string]$ChromeCacheRoot) {
    $manifest = Get-PendingDeleteManifestPath -ChromeCacheRoot $ChromeCacheRoot
    if (-not (Test-Path -LiteralPath $manifest)) {
        return
    }

    $remaining = New-Object System.Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadLines($manifest)) {
        if (-not $line.Trim()) {
            continue
        }

        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            $path = [string]$record.path
        }
        catch {
            continue
        }

        if (-not $path) {
            continue
        }

        if (Test-Path -LiteralPath $path) {
            try {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }
            catch {
                $remaining.Add($line) | Out-Null
            }
        }
    }

    if ($remaining.Count -eq 0) {
        Remove-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue
    }
    else {
        [IO.File]::WriteAllLines($manifest, [string[]]$remaining, [Text.UTF8Encoding]::new($false))
    }
}

function Write-PluginCache([string]$SourcePlugin, [string]$TargetPlugin, [string]$NativeHostName) {
    New-Item -ItemType Directory -Path $TargetPlugin -Force | Out-Null

    foreach ($relative in @(".codex-plugin", "assets", "scripts", "skills")) {
        $source = Join-Path $SourcePlugin $relative
        if (Test-Path -LiteralPath $source) {
            Copy-DirectoryContent -Source $source -Destination (Join-Path $TargetPlugin $relative)
        }
    }

    $targetHost = Join-Path $TargetPlugin "extension-host"
    if (-not (Test-Path -LiteralPath (Join-Path $targetHost "windows\x64\extension-host.exe"))) {
        $sourceHost = Resolve-ExistingPath (Join-Path $SourcePlugin "extension-host") "Chrome extension host"
        Copy-Item -LiteralPath $sourceHost -Destination $targetHost -Recurse -Force
    }

    Patch-ChromeNativeHostName -PluginRoot $TargetPlugin -HostName $NativeHostName
}

function Patch-ChromeNativeHostName([string]$PluginRoot, [string]$HostName) {
    $extensionIdPath = Join-Path $PluginRoot "scripts\extension-id.json"
    if (Test-Path -LiteralPath $extensionIdPath) {
        $config = Get-Content -Raw -LiteralPath $extensionIdPath | ConvertFrom-Json
        $config.extensionHostName = $HostName
        $json = $config | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($extensionIdPath, ($json + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    }

    $installManifestPath = Join-Path $PluginRoot "scripts\installManifest.mjs"
    if (Test-Path -LiteralPath $installManifestPath) {
        $text = [IO.File]::ReadAllText($installManifestPath)
        $updated = [regex]::Replace($text, 'extensionHostName:"[^"]+"', ('extensionHostName:"' + $HostName + '"'))
        if ($updated -ne $text) {
            [IO.File]::WriteAllText($installManifestPath, $updated, [Text.UTF8Encoding]::new($false))
        }
    }
}

function Ensure-LatestLink([string]$ChromeCacheRoot, [string]$TargetPath) {
    $latest = Join-Path $ChromeCacheRoot "latest"
    if (Test-Path -LiteralPath $latest) {
        try {
            $current = Get-Item -LiteralPath $latest -Force
            $targetFullPath = (Resolve-Path -LiteralPath $TargetPath).Path
            if ($current.LinkType -eq "Junction" -and $current.Target -contains $targetFullPath) {
                return
            }
            Remove-Item -LiteralPath $latest -Force -Recurse -ErrorAction Stop
        }
        catch {
            Add-PendingDeletePath -ChromeCacheRoot $ChromeCacheRoot -Path $latest -Reason "latest_retarget_failed"
        }
    }

    try {
        New-Item -ItemType Junction -Path $latest -Target $TargetPath | Out-Null
    }
    catch {
        Copy-Item -LiteralPath $TargetPath -Destination $latest -Recurse -Force
    }
}

$resolvedYukinoHome = Resolve-ExistingPath $YukinoHome "Yukino home"
if (-not $MarketplaceRoot) {
    $MarketplaceRoot = Join-Path $resolvedYukinoHome ".tmp\bundled-marketplaces\openai-bundled"
}
$resolvedMarketplaceRoot = Resolve-ExistingPath $MarketplaceRoot "bundled marketplace root"
$sourcePlugin = Resolve-ExistingPath (Join-Path $resolvedMarketplaceRoot "plugins\chrome") "bundled Chrome plugin source"

$pluginJsonPath = Resolve-ExistingPath (Join-Path $sourcePlugin ".codex-plugin\plugin.json") "Chrome plugin metadata"
$pluginJson = Get-Content -Raw -LiteralPath $pluginJsonPath | ConvertFrom-Json
if (-not $PluginVersion) {
    $PluginVersion = [string]$pluginJson.version
}
if (-not $PluginVersion) {
    throw "Could not resolve Chrome plugin version from $pluginJsonPath"
}

$chromeCacheRoot = Join-Path $resolvedYukinoHome "plugins\cache\openai-bundled\chrome"
New-Item -ItemType Directory -Path $chromeCacheRoot -Force | Out-Null
Invoke-PendingDeleteCleanup -ChromeCacheRoot $chromeCacheRoot

$targetPlugin = Join-Path $chromeCacheRoot $PluginVersion
try {
    Write-PluginCache -SourcePlugin $sourcePlugin -TargetPlugin $targetPlugin -NativeHostName $NativeHostName
}
catch {
    $lockedTarget = $targetPlugin
    Add-PendingDeletePath -ChromeCacheRoot $chromeCacheRoot -Path $lockedTarget -Reason "primary_cache_update_failed"
    $recoveryName = "{0}-recovery-{1}" -f $PluginVersion, (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
    $targetPlugin = Join-Path $chromeCacheRoot $recoveryName
    Write-PluginCache -SourcePlugin $sourcePlugin -TargetPlugin $targetPlugin -NativeHostName $NativeHostName
}

Ensure-LatestLink -ChromeCacheRoot $chromeCacheRoot -TargetPath $targetPlugin

[pscustomobject]@{
    Status = "repaired"
    PluginRoot = $targetPlugin
    Latest = (Join-Path $chromeCacheRoot "latest")
    NativeHostName = $NativeHostName
}
