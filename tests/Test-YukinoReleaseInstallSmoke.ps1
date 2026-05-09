param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$smokeScript = Join-Path $ProjectRoot "scripts\Test-YukinoReleaseInstall.ps1"
$releaseTest = Join-Path $ProjectRoot "tests\Test-YukinoReleaseWorkflow.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $smokeScript) "Missing release install smoke script: $smokeScript"

$scriptText = [IO.File]::ReadAllText($smokeScript)
Assert-True $scriptText.Contains("gh release download") "Release install smoke should download assets from GitHub instead of using local out artifacts."
Assert-True $scriptText.Contains("SHA256SUMS.txt") "Release install smoke should verify the downloaded MSIX against SHA256SUMS.txt."
Assert-True $scriptText.Contains("Install-YukinoRelease.ps1") "Release install smoke should exercise the published installer path."
Assert-True $scriptText.Contains("verify-yukino.ps1") "Release install smoke should run installed-package verification after installing."
Assert-True $scriptText.Contains("Start-Process") "Release install smoke should perform a launch check against the installed executable."
Assert-True $scriptText.Contains("Remove-Item") "Release install smoke should clean downloaded release assets unless preservation is requested."

$releaseTestText = [IO.File]::ReadAllText($releaseTest)
Assert-True $releaseTestText.Contains("Test-YukinoReleaseInstall.ps1") "Release workflow tests should enforce the release install smoke script contract."

Write-Host "Yukino release install smoke test passed."
