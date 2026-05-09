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
Assert-True $buildText.Contains("Copy-YukinoDiagnosticScripts") "Build script should bundle the fixed local diagnostic script with the package."
Assert-True $buildText.Contains("Patch-YukinoLocalDiagnosticsRunner") "Build script should patch a fixed app-server diagnostic runner instead of using arbitrary UI commands."
Assert-True $buildText.Contains("run-yukino-local-diagnostics") "Settings diagnostics entry should call the fixed local diagnostics app-server method."
Assert-True $buildText.Contains("yukino-diagnostics-requested") "Settings diagnostics entry should log the explicit diagnostics action."
Assert-True $buildText.Contains("Run diagnostics") "Settings diagnostics entry should expose a one-click diagnostics button."
Assert-True (-not $buildText.Contains("writeText?.(`npm run diagnose`)")) "Settings diagnostics entry should not only copy the manual command."
Assert-True $buildText.Contains("-NoRepair") "One-click local diagnostics should run in read-only mode without repairing caches."
Assert-True $buildText.Contains("maxBuffer") "One-click local diagnostics should capture bounded output."
Assert-True $buildText.Contains("settings.agent.dependencies.yukinoVersion.label") "Settings should include a quiet Yukino version row in the existing Agent dependencies maintenance section."
Assert-True $buildText.Contains("Yukino version") "Yukino version row should be visibly labeled."
Assert-True $buildText.Contains("yukino.akane") "Yukino version row should expose the package identity."
Assert-True $buildText.Contains("v26.506.3741.1-yukino.2") "Yukino version row should expose the stable release baseline."
Assert-True $buildText.Contains("%USERPROFILE%\\.yukino") "Yukino version row should expose the Yukino config home."
$visibleVersionDescription = 'defaultMessage:`Yukino | package: yukino.akane | release: v26.506.3741.1-yukino.2 | config: %USERPROFILE%\\.yukino`'
Assert-True $buildText.Contains($visibleVersionDescription) "Yukino version row should escape the visible config home so JavaScript renders the backslash."
Assert-True (-not $buildText.Contains("diagnostics-settings")) "Settings diagnostics must not add a standalone diagnostics settings route."
Assert-True (-not $buildText.Contains("/settings/diagnostics")) "Settings diagnostics must not add a visible diagnostics page."

$verifyText = [IO.File]::ReadAllText($verifyScript)
Assert-True $verifyText.Contains("settings-local-diagnostics-entry") "Verification should check the latest build for the hidden Settings diagnostics entry."
Assert-True $verifyText.Contains("yukino-local-diagnostics-runner") "Verification should check the fixed local diagnostics app-server runner."
Assert-True $verifyText.Contains("bundled-local-diagnostics-script") "Verification should check that the local diagnostic scripts are bundled with the package."
Assert-True $verifyText.Contains("settings.agent.dependencies.localDiagnostics.label") "Verification should require the local diagnostics settings label marker."
Assert-True ($verifyText.Contains("scripts\Test-YukinoLocalState.ps1") -or $verifyText.Contains("scripts/Test-YukinoLocalState.ps1")) "Verification should require the local diagnostic script marker."
Assert-True $verifyText.Contains("run-yukino-local-diagnostics") "Verification should require the fixed local diagnostics app-server method marker."
Assert-True $verifyText.Contains("settings-yukino-version-entry") "Verification should check the latest build for the hidden Yukino version entry."
Assert-True $verifyText.Contains("settings.agent.dependencies.yukinoVersion.label") "Verification should require the Yukino version settings label marker."
Assert-True $verifyText.Contains("v26.506.3741.1-yukino.2") "Verification should require the stable release baseline marker."

$runnerText = [IO.File]::ReadAllText($testRunner)
Assert-True $runnerText.Contains("Test-YukinoSettingsDiagnosticsEntry.ps1") "The test suite should include the Settings diagnostics entry contract test."

Write-Host "Yukino Settings diagnostics entry test passed."
