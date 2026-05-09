param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$buildScript = Join-Path $ProjectRoot "build-yukino.ps1"
$verifyScript = Join-Path $ProjectRoot "verify-yukino.ps1"
$localStateScript = Join-Path $ProjectRoot "scripts\Test-YukinoLocalState.ps1"
$testRunner = Join-Path $ProjectRoot "tests\Run-YukinoTests.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $buildScript) "Missing build script: $buildScript"
Assert-True (Test-Path -LiteralPath $verifyScript) "Missing verify script: $verifyScript"
Assert-True (Test-Path -LiteralPath $localStateScript) "Missing local state diagnostic script: $localStateScript"
Assert-True (Test-Path -LiteralPath $testRunner) "Missing test runner: $testRunner"

$buildText = [IO.File]::ReadAllText($buildScript)
Assert-True $buildText.Contains("Patch-ChromeNativeHostCompatibility") "Build script should explicitly preserve Chrome native-host compatibility."
Assert-True $buildText.Contains("com.openai.codexextension") "Chrome Web Store extension requires the public native-host name."
Assert-True $buildText.Contains("openai-bundled\plugins\chrome\scripts\extension-id.json") "Build script should patch the bundled Chrome extension-id.json explicitly."

$verifyText = [IO.File]::ReadAllText($verifyScript)
Assert-True $verifyText.Contains("chrome-plugin-build-cache") "Verification should check the latest build's bundled Chrome plugin metadata."
Assert-True $verifyText.Contains("installed-chrome-plugin-cache") "Verification should check the user's installed Chrome plugin cache."
Assert-True $verifyText.Contains("chrome-native-host-yukino-target") "Verification should ensure Chrome's native host manifest points at Yukino's cache."
Assert-True $verifyText.Contains("plugin_cache_windows_file_lock") "Verification should detect the Windows plugin cache lock failure in recent logs."
Assert-True $verifyText.Contains("Historical/recovered") "Verification should distinguish recovered Chrome plugin cache lock evidence from active cache damage."
Assert-True $verifyText.Contains("chrome-plugin-cache-pending-cleanup") "Verification should report delayed Chrome plugin cache cleanup state."
Assert-True $verifyText.Contains("pending-delete.jsonl") "Verification should inspect the delayed Chrome plugin cleanup manifest."

$localStateText = [IO.File]::ReadAllText($localStateScript)
Assert-True $localStateText.Contains("chrome@openai-bundled") "Local diagnostics should inspect the bundled Chrome plugin setting."
Assert-True $localStateText.Contains("installed-chrome-plugin-cache") "Local diagnostics should report whether the Chrome plugin cache is complete."
Assert-True $localStateText.Contains("Repair-YukinoChromePluginCache.ps1") "Local diagnostics should try to repair an incomplete Chrome plugin cache."
Assert-True $localStateText.Contains("chrome-native-host-yukino-target") "Local diagnostics should report whether the native host points to Yukino."
Assert-True $localStateText.Contains("plugin_cache_windows_file_lock") "Local diagnostics should surface recent Chrome plugin cache lock failures."
Assert-True $localStateText.Contains("Historical/recovered") "Local diagnostics should distinguish recovered Chrome plugin cache lock evidence from active cache damage."
Assert-True $localStateText.Contains("chrome-plugin-cache-pending-cleanup") "Local diagnostics should report delayed Chrome plugin cache cleanup state."
Assert-True $localStateText.Contains("pending-delete.jsonl") "Local diagnostics should inspect the delayed Chrome plugin cleanup manifest."

$runnerText = [IO.File]::ReadAllText($testRunner)
Assert-True $runnerText.Contains("Test-YukinoChromePluginDiagnostics.ps1") "The test suite should include the Chrome plugin diagnostic contract test."

Write-Host "Yukino Chrome plugin diagnostics contract test passed."
