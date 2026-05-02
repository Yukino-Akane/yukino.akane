param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$buildScript = Join-Path $ProjectRoot "build-yukino.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $buildScript) "Missing build script: $buildScript"

$scriptText = [IO.File]::ReadAllText($buildScript)
Assert-True $scriptText.Contains("skills-page-*.js") "Plugin auth gate patch should scan the new skills-page bundle used by current Codex Desktop builds."
Assert-True $scriptText.Contains('s&&!m') "Plugin auth gate patch should recognize the current skills page API-key guard shape."
Assert-True $scriptText.Contains('s&&!1') "Plugin auth gate patch should disable the current skills page API-key guard without disabling the whole page."
Assert-True $scriptText.Contains("gradient-*.js") "Plugin auth gate patch should retain the older gradient bundle patch for older Codex Desktop builds."
Assert-True $scriptText.Contains("pluginsAuthBlockedToast.title") "Plugin auth gate patch should anchor the current bundle patch near the plugin auth blocked toast."

Write-Host "Yukino plugin auth gate patch test passed."
