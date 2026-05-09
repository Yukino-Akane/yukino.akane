param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$verifyScript = Join-Path $ProjectRoot "verify-yukino.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $verifyScript) "Missing verification script: $verifyScript"

$verifyText = [IO.File]::ReadAllText($verifyScript)

Assert-True $verifyText.Contains("settingsPageSectionMapRegex") "Verification should recognize current settings-page bundles where plugins-settings and skills-settings are present in the section map without the old extension/electron gate."
Assert-True $verifyText.Contains("method=config/") "Verification log scanning should only treat config method errors as config conflicts, not every errorCode=-32600 line from unrelated methods."
Assert-True $verifyText.Contains("No config batchWrite evidence in latest") "Verification should mark missing batchWrite evidence as informational instead of a release warning."

Write-Host "Yukino verification warning contract test passed."
