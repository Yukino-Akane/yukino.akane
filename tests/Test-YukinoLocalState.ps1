param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$localStateScript = Join-Path $ProjectRoot "scripts\Test-YukinoLocalState.ps1"
$testRunner = Join-Path $ProjectRoot "tests\Run-YukinoTests.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $localStateScript) "Missing local state diagnostic script: $localStateScript"

$scriptText = [IO.File]::ReadAllText($localStateScript)
Assert-True $scriptText.Contains("Add-Check") "Local state diagnostic should emit PASS/WARN/FAIL checks."
Assert-True $scriptText.Contains("Get-AppxPackage -Name `$PackageName") "Local state diagnostic should inspect the installed Yukino package."
Assert-True $scriptText.Contains("Get-AppxPackage -Name `$OfficialPackageName") "Local state diagnostic should confirm the official Codex package remains separate."
Assert-True $scriptText.Contains("approval_policy") "Local state diagnostic should inspect approval_policy in .yukino config."
Assert-True $scriptText.Contains("sandbox_mode") "Local state diagnostic should inspect sandbox_mode in .yukino config."
Assert-True $scriptText.Contains("features.plugins") "Local state diagnostic should inspect the plugins feature flag."
Assert-True $scriptText.Contains("browser-use@openai-bundled") "Local state diagnostic should inspect the bundled browser-use plugin setting."
Assert-True $scriptText.Contains("Yukino\Logs") "Local state diagnostic should scan recent Yukino logs."
Assert-True $scriptText.Contains("pluginsAuthBlockedToast") "Local state diagnostic should scan logs for plugin-related failures."
Assert-True $scriptText.Contains("Get-LogLineTimestamp") "Local state diagnostic should parse log line timestamps for Browser activity checks."
Assert-True $scriptText.Contains("Find-BrowserRuntimeActivityLog") "Local state diagnostic should pair Browser activity start/end markers instead of accepting unrelated log lines."
Assert-True $scriptText.Contains("browser-runtime-activity-log") "Local state diagnostic should emit a named Browser runtime activity check."
Assert-True $scriptText.Contains("captured turn route") "Local state diagnostic should recognize Browser tool turn start markers."
Assert-True $scriptText.Contains("ended browser use turn route") "Local state diagnostic should recognize Browser tool turn end markers."
Assert-True $scriptText.Contains("turnId") "Local state diagnostic should match Browser activity markers by turnId."
Assert-True $scriptText.Contains("git status --short --branch") "Local state diagnostic should report repository sync state."
Assert-True $scriptText.Contains("gh release view") "Local state diagnostic should compare against a GitHub release when gh is available."
Assert-True $scriptText.Contains("installed-release-version") "Local state diagnostic should compare the installed package version with the release MSIX asset version."
Assert-True $scriptText.Contains("PackageFullName") "Local state diagnostic should include installed package identity in details."
Assert-True $scriptText.Contains("[switch]`$NoRepair") "Local state diagnostic should expose a no-repair mode for the in-app one-click runner."
Assert-True $scriptText.Contains("-not `$NoRepair") "Local state diagnostic should skip cache repair when no-repair mode is set."

$testRunnerText = [IO.File]::ReadAllText($testRunner)
Assert-True $testRunnerText.Contains("Test-YukinoLocalState.ps1") "The test suite should include the local state diagnostic contract test."

Write-Host "Yukino local state diagnostic test passed."
