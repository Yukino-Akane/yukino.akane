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
        return
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
$targetPlugin = Join-Path $chromeCacheRoot $PluginVersion
New-Item -ItemType Directory -Path $targetPlugin -Force | Out-Null

foreach ($relative in @(".codex-plugin", "assets", "scripts", "skills")) {
    $source = Join-Path $sourcePlugin $relative
    if (Test-Path -LiteralPath $source) {
        Copy-DirectoryContent -Source $source -Destination (Join-Path $targetPlugin $relative)
    }
}

$targetHost = Join-Path $targetPlugin "extension-host"
if (-not (Test-Path -LiteralPath (Join-Path $targetHost "windows\x64\extension-host.exe"))) {
    $sourceHost = Resolve-ExistingPath (Join-Path $sourcePlugin "extension-host") "Chrome extension host"
    Copy-Item -LiteralPath $sourceHost -Destination $targetHost -Recurse -Force
}

Patch-ChromeNativeHostName -PluginRoot $targetPlugin -HostName $NativeHostName
Ensure-LatestLink -ChromeCacheRoot $chromeCacheRoot -TargetPath $targetPlugin

[pscustomobject]@{
    Status = "repaired"
    PluginRoot = $targetPlugin
    Latest = (Join-Path $chromeCacheRoot "latest")
    NativeHostName = $NativeHostName
}
