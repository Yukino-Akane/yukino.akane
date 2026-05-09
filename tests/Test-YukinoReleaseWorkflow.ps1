param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$publishScript = Join-Path $ProjectRoot "scripts\Publish-YukinoRelease.ps1"
$releaseSafetyScript = Join-Path $ProjectRoot "scripts\Test-YukinoReleaseSafety.ps1"
$testRunner = Join-Path $ProjectRoot "tests\Run-YukinoTests.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $publishScript) "Missing release publishing script: $publishScript"

$scriptText = [IO.File]::ReadAllText($publishScript)
Assert-True $scriptText.Contains("[switch]`$DryRun") "Release script should support a dry-run mode that prepares assets without calling GitHub."
Assert-True $scriptText.Contains("SHA256SUMS.txt") "Release script should generate a SHA256SUMS.txt asset."
Assert-True $scriptText.Contains("Install-YukinoRelease.ps1") "Release script should include the installer asset."
Assert-True $scriptText.Contains("Get-FileHash -Algorithm SHA256") "Release script should compute the MSIX SHA256 instead of relying on stale checksums."
Assert-True $scriptText.Contains("gh release create") "Release script should create the GitHub release when not in dry-run mode."
Assert-True $scriptText.Contains("--latest") "Release script should be able to mark the new release as latest."
Assert-True $scriptText.Contains("verify-yukino.ps1") "Release script should run project verification before publishing."
Assert-True (Test-Path -LiteralPath $releaseSafetyScript) "Missing release safety script: $releaseSafetyScript"
Assert-True $scriptText.Contains("Test-YukinoReleaseSafety.ps1") "Release script should run the release safety gate before publishing."
Assert-True $scriptText.Contains("ReleaseNotesPath") "Release script should emit or accept release notes."
Assert-True (-not $scriptText.Contains("Add-AppxPackage")) "Release publishing should not install packages or close the active Yukino session."

$testRunnerText = [IO.File]::ReadAllText($testRunner)
Assert-True $testRunnerText.Contains("Test-YukinoReleaseSafety.ps1") "The test suite should include the release safety gate contract test."

Write-Host "Yukino release workflow test passed."
