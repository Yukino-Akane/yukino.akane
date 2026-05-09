param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$buildScript = Join-Path $ProjectRoot "build-yukino.ps1"
$verifyScript = Join-Path $ProjectRoot "verify-yukino.ps1"
$testRunner = Join-Path $ProjectRoot "tests\Run-YukinoTests.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $buildScript) "Missing build script: $buildScript"
Assert-True (Test-Path -LiteralPath $verifyScript) "Missing verify script: $verifyScript"
Assert-True (Test-Path -LiteralPath $testRunner) "Missing test runner: $testRunner"

$buildText = [IO.File]::ReadAllText($buildScript)
Assert-True $buildText.Contains("Patch-YukinoSettingsDiagnosticsEntry") "Build script should patch a quiet Yukino local diagnostics entry into Settings."
Assert-True $buildText.Contains("agent-settings-*.js") "Settings diagnostics patch should target the Agent Settings bundle, not the settings shell."
Assert-True $buildText.Contains("settings.agent.dependencies.localDiagnostics.label") "Settings diagnostics entry should live in the existing Agent dependencies maintenance section."
Assert-True $buildText.Contains("npm run diagnose") "Settings diagnostics entry should reference the existing maintenance command."
Assert-True ($buildText.Contains("scripts\Test-YukinoLocalState.ps1") -or $buildText.Contains("scripts/Test-YukinoLocalState.ps1")) "Settings diagnostics entry should point to the local state diagnostic script."
Assert-True $buildText.Contains("navigator.clipboard") "Settings diagnostics entry should copy the command instead of inventing an unverified one-click PowerShell runner."
Assert-True (-not $buildText.Contains("diagnostics-settings")) "Settings diagnostics must not add a standalone diagnostics settings route."
Assert-True (-not $buildText.Contains("/settings/diagnostics")) "Settings diagnostics must not add a visible diagnostics page."

$verifyText = [IO.File]::ReadAllText($verifyScript)
Assert-True $verifyText.Contains("settings-local-diagnostics-entry") "Verification should check the latest build for the hidden Settings diagnostics entry."
Assert-True $verifyText.Contains("settings.agent.dependencies.localDiagnostics.label") "Verification should require the local diagnostics settings label marker."
Assert-True ($verifyText.Contains("scripts\Test-YukinoLocalState.ps1") -or $verifyText.Contains("scripts/Test-YukinoLocalState.ps1")) "Verification should require the local diagnostic script marker."

$runnerText = [IO.File]::ReadAllText($testRunner)
Assert-True $runnerText.Contains("Test-YukinoSettingsDiagnosticsEntry.ps1") "The test suite should include the Settings diagnostics entry contract test."

Write-Host "Yukino Settings diagnostics entry test passed."
