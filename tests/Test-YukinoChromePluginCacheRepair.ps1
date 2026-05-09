param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repairScript = Join-Path $ProjectRoot "scripts\Repair-YukinoChromePluginCache.ps1"
$testRoot = Join-Path $env:TEMP ("yukino-chrome-cache-repair-test-" + [guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $repairScript) "Missing Chrome plugin cache repair script: $repairScript"

$yukinoHome = Join-Path $testRoot ".yukino"
$marketplaceRoot = Join-Path $yukinoHome ".tmp\bundled-marketplaces\openai-bundled"
$sourcePlugin = Join-Path $marketplaceRoot "plugins\chrome"
$targetVersion = Join-Path $yukinoHome "plugins\cache\openai-bundled\chrome\0.1.7"

New-Item -ItemType Directory -Path `
    (Join-Path $sourcePlugin ".codex-plugin"), `
    (Join-Path $sourcePlugin "assets"), `
    (Join-Path $sourcePlugin "scripts"), `
    (Join-Path $sourcePlugin "skills"), `
    (Join-Path $sourcePlugin "extension-host\windows\x64"), `
    (Join-Path $targetVersion "scripts"), `
    (Join-Path $targetVersion "skills"), `
    (Join-Path $targetVersion "extension-host\windows\x64") | Out-Null

@'
{"name":"chrome","version":"0.1.7"}
'@ | Set-Content -LiteralPath (Join-Path $sourcePlugin ".codex-plugin\plugin.json") -Encoding UTF8
"asset" | Set-Content -LiteralPath (Join-Path $sourcePlugin "assets\google-chrome.png") -Encoding UTF8
@'
{
  "extensionId": "hehggadaopoacecdllhhajmbjkdcmajg",
  "extensionHostName": "yukino.akaneextension"
}
'@ | Set-Content -LiteralPath (Join-Path $sourcePlugin "scripts\extension-id.json") -Encoding UTF8
'var n={extensionId:"hehggadaopoacecdllhhajmbjkdcmajg",extensionHostName:"yukino.akaneextension"};' |
    Set-Content -LiteralPath (Join-Path $sourcePlugin "scripts\installManifest.mjs") -Encoding UTF8
"host" | Set-Content -LiteralPath (Join-Path $sourcePlugin "extension-host\windows\x64\extension-host.exe") -Encoding UTF8
"skill" | Set-Content -LiteralPath (Join-Path $sourcePlugin "skills\SKILL.md") -Encoding UTF8

@'
{
  "extensionId": "hehggadaopoacecdllhhajmbjkdcmajg",
  "extensionHostName": "yukino.akaneextension"
}
'@ | Set-Content -LiteralPath (Join-Path $targetVersion "scripts\extension-id.json") -Encoding UTF8
"existing-host" | Set-Content -LiteralPath (Join-Path $targetVersion "extension-host\windows\x64\extension-host.exe") -Encoding UTF8

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $repairScript -YukinoHome $yukinoHome -MarketplaceRoot $marketplaceRoot
    Assert-True ($LASTEXITCODE -eq 0) "Chrome plugin cache repair script should exit 0."

    Assert-True (Test-Path -LiteralPath (Join-Path $targetVersion ".codex-plugin\plugin.json")) "Repair should restore .codex-plugin metadata."
    Assert-True (Test-Path -LiteralPath (Join-Path $targetVersion "assets\google-chrome.png")) "Repair should restore assets."
    Assert-True (Test-Path -LiteralPath (Join-Path $targetVersion "scripts\installManifest.mjs")) "Repair should restore scripts."
    Assert-True (Test-Path -LiteralPath (Join-Path $targetVersion "extension-host\windows\x64\extension-host.exe")) "Repair should preserve or restore extension-host."
    Assert-True (Test-Path -LiteralPath (Join-Path $yukinoHome "plugins\cache\openai-bundled\chrome\latest")) "Repair should ensure a latest cache entry exists."

    $extensionConfig = Get-Content -Raw -LiteralPath (Join-Path $targetVersion "scripts\extension-id.json") | ConvertFrom-Json
    Assert-True ($extensionConfig.extensionHostName -eq "com.openai.codexextension") "Repair should preserve the public Chrome native host name."
    $installManifest = [IO.File]::ReadAllText((Join-Path $targetVersion "scripts\installManifest.mjs"))
    Assert-True ($installManifest.Contains('extensionHostName:"com.openai.codexextension"')) "Repair should patch installManifest.mjs host name."

    $lockedHome = Join-Path $testRoot ".yukino-locked"
    $lockedMarketplaceRoot = Join-Path $lockedHome ".tmp\bundled-marketplaces\openai-bundled"
    $lockedSourcePlugin = Join-Path $lockedMarketplaceRoot "plugins\chrome"
    $lockedChromeCacheRoot = Join-Path $lockedHome "plugins\cache\openai-bundled\chrome"
    $lockedTargetVersion = Join-Path $lockedChromeCacheRoot "0.1.7"

    New-Item -ItemType Directory -Path `
        (Join-Path $lockedSourcePlugin ".codex-plugin"), `
        (Join-Path $lockedSourcePlugin "assets"), `
        (Join-Path $lockedSourcePlugin "scripts"), `
        (Join-Path $lockedSourcePlugin "skills"), `
        (Join-Path $lockedSourcePlugin "extension-host\windows\x64"), `
        (Join-Path $lockedTargetVersion "scripts") | Out-Null

@'
{"name":"chrome","version":"0.1.7"}
'@ | Set-Content -LiteralPath (Join-Path $lockedSourcePlugin ".codex-plugin\plugin.json") -Encoding UTF8
    "asset" | Set-Content -LiteralPath (Join-Path $lockedSourcePlugin "assets\google-chrome.png") -Encoding UTF8
@'
{
  "extensionId": "hehggadaopoacecdllhhajmbjkdcmajg",
  "extensionHostName": "yukino.akaneextension"
}
'@ | Set-Content -LiteralPath (Join-Path $lockedSourcePlugin "scripts\extension-id.json") -Encoding UTF8
    'var n={extensionId:"hehggadaopoacecdllhhajmbjkdcmajg",extensionHostName:"yukino.akaneextension"};' |
        Set-Content -LiteralPath (Join-Path $lockedSourcePlugin "scripts\installManifest.mjs") -Encoding UTF8
    "host" | Set-Content -LiteralPath (Join-Path $lockedSourcePlugin "extension-host\windows\x64\extension-host.exe") -Encoding UTF8
    "skill" | Set-Content -LiteralPath (Join-Path $lockedSourcePlugin "skills\SKILL.md") -Encoding UTF8

    $lockedFile = Join-Path $lockedTargetVersion "scripts\extension-id.json"
    "locked-stale" | Set-Content -LiteralPath $lockedFile -Encoding UTF8
    $stream = [IO.File]::Open($lockedFile, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $repairScript -YukinoHome $lockedHome -MarketplaceRoot $lockedMarketplaceRoot
        Assert-True ($LASTEXITCODE -eq 0) "Chrome plugin cache repair should recover when the primary version cache has a locked file."

        $lockedLatest = Join-Path $lockedChromeCacheRoot "latest"
        Assert-True (Test-Path -LiteralPath (Join-Path $lockedLatest ".codex-plugin\plugin.json")) "Locked-cache repair should switch latest to a complete recovery cache."
        Assert-True (Test-Path -LiteralPath (Join-Path $lockedLatest "assets\google-chrome.png")) "Locked-cache repair should restore assets through latest."
        Assert-True (Test-Path -LiteralPath (Join-Path $lockedLatest "extension-host\windows\x64\extension-host.exe")) "Locked-cache repair should restore extension-host through latest."

        $latestConfig = Get-Content -Raw -LiteralPath (Join-Path $lockedLatest "scripts\extension-id.json") | ConvertFrom-Json
        Assert-True ($latestConfig.extensionHostName -eq "com.openai.codexextension") "Locked-cache repair should patch the recovery cache native host name."

        $pendingManifest = Join-Path $lockedChromeCacheRoot "pending-delete.jsonl"
        Assert-True (Test-Path -LiteralPath $pendingManifest) "Locked-cache repair should record stale locked cache paths for delayed cleanup."
        $pendingRecords = @([IO.File]::ReadAllLines($pendingManifest) | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
        Assert-True (@($pendingRecords | Where-Object { $_.path -eq $lockedTargetVersion }).Count -gt 0) "Delayed cleanup manifest should include the locked primary cache path."
    }
    finally {
        $stream.Dispose()
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $repairScript -YukinoHome $lockedHome -MarketplaceRoot $lockedMarketplaceRoot
    Assert-True ($LASTEXITCODE -eq 0) "Chrome plugin cache repair should run delayed cleanup after the lock is released."
    $pendingManifestAfterCleanup = Join-Path $lockedChromeCacheRoot "pending-delete.jsonl"
    if (Test-Path -LiteralPath $pendingManifestAfterCleanup) {
        $pendingAfterRecords = @([IO.File]::ReadAllLines($pendingManifestAfterCleanup) | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
        Assert-True (@($pendingAfterRecords | Where-Object { $_.path -eq $lockedTargetVersion }).Count -eq 0) "Delayed cleanup should remove the stale cache path from the manifest after cleanup succeeds."
    }
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Yukino Chrome plugin cache repair test passed."
