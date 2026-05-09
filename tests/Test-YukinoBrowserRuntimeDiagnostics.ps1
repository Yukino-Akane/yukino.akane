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
Assert-True (Test-Path -LiteralPath $verifyScript) "Missing verification script: $verifyScript"
Assert-True (Test-Path -LiteralPath $localStateScript) "Missing local state diagnostic script: $localStateScript"
Assert-True (Test-Path -LiteralPath $testRunner) "Missing test runner: $testRunner"

$buildText = [IO.File]::ReadAllText($buildScript)
Assert-True $buildText.Contains("workspace_dependencies") "Unsupported feature patch should explicitly handle workspace_dependencies."
Assert-True $buildText.Contains("Get-ChildItem -LiteralPath `$AssetsDir -File -Filter `"*.js`"") "Unsupported feature patch should scan current hashed webview JS bundles, not only index-*.js."
Assert-True $buildText.Contains("new Set([") "Unsupported feature patch should handle the current Set-based feature filter bundle shape."
Assert-True $buildText.Contains("unsupported experimental feature") "Unsupported feature patch should keep a clear maintenance log message."

$verifyText = [IO.File]::ReadAllText($verifyScript)
Assert-True $verifyText.Contains("unsupported-feature-sync-patch") "Verification should check latest build assets for unsupported feature sync patching."
Assert-True $verifyText.Contains("installed-unsupported-feature-sync-patch") "Verification should check installed app.asar assets for unsupported feature sync patching."
Assert-True $verifyText.Contains("workspace_dependencies") "Verification should require the workspace_dependencies sync issue to stay patched."

$localStateText = [IO.File]::ReadAllText($localStateScript)
Assert-True $localStateText.Contains("browser-use native pipe listening") "Local diagnostics should inspect Browser runtime native pipe startup logs."
Assert-True $localStateText.Contains("BrowserUseThreadConfig") "Local diagnostics should inspect BrowserUseThreadConfig runtime path logs."
Assert-True $localStateText.Contains("browser-use-runtime-log") "Local diagnostics should emit a named browser-use runtime log check."
Assert-True $localStateText.Contains("session-node-repl-tool") "Local diagnostics should report whether the current session exposes the browser execution tool."
Assert-True $localStateText.Contains("latest session metadata") "Local diagnostics should distinguish stale session metadata from current runtime evidence."
Assert-True $localStateText.Contains("live Yukino node_repl runtime is present") "Local diagnostics should use live Yukino node_repl as Browser runtime evidence."
Assert-True $localStateText.Contains("node_repl.exe") "Local diagnostics should inspect live node_repl.exe process ownership."

$runnerText = [IO.File]::ReadAllText($testRunner)
Assert-True $runnerText.Contains("Test-YukinoBrowserRuntimeDiagnostics.ps1") "The test suite should include the browser runtime diagnostic contract test."

Write-Host "Yukino browser runtime diagnostics contract test passed."
