param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$safetyScript = Join-Path $ProjectRoot "scripts\Test-YukinoReleaseSafety.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $safetyScript) "Missing release safety script: $safetyScript"

$scriptText = [IO.File]::ReadAllText($safetyScript)
Assert-True $scriptText.Contains("gh repo view") "Release safety should verify the GitHub repository state before publishing."
Assert-True $scriptText.Contains("isPrivate") "Release safety should require a private repository."
Assert-True $scriptText.Contains("tracked-dangerous-file") "Release safety should reject tracked local config and credential paths."
Assert-True $scriptText.Contains("tracked-secret-pattern") "Release safety should scan tracked text for high-confidence key and token patterns."
Assert-True $scriptText.Contains("tracked-cpa-skill-pattern") "Release safety should reject tracked CPA skill identifiers."
Assert-True $scriptText.Contains("msix-dangerous-path") "Release safety should inspect MSIX paths for local config and credential payloads."
Assert-True $scriptText.Contains("msix-cpa-path") "Release safety should inspect MSIX paths for CPA skill payloads."
Assert-True $scriptText.Contains("Convert-GitGrepFinding") "Release safety should redact git grep findings instead of printing matched secret text."
Assert-True (-not $scriptText.Contains('Add-Finding $Findings $Check $line')) "Release safety must not print raw git grep lines that may contain secrets."

Write-Host "Yukino release safety test passed."
