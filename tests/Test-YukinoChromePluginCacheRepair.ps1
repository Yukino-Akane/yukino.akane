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
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Yukino Chrome plugin cache repair test passed."
