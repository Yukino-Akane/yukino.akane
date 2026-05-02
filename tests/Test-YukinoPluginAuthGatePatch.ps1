param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$buildScript = Join-Path $ProjectRoot "build-yukino.ps1"
$verifyScript = Join-Path $ProjectRoot "verify-yukino.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $buildScript) "Missing build script: $buildScript"
Assert-True (Test-Path -LiteralPath $verifyScript) "Missing verify script: $verifyScript"

$scriptText = [IO.File]::ReadAllText($buildScript)
Assert-True $scriptText.Contains("skills-page-*.js") "Plugin auth gate patch should scan the new skills-page bundle used by current Codex Desktop builds."
Assert-True $scriptText.Contains('s&&!m') "Plugin auth gate patch should recognize the current skills page API-key guard shape."
Assert-True $scriptText.Contains('s&&!1') "Plugin auth gate patch should disable the current skills page API-key guard without disabling the whole page."
Assert-True $scriptText.Contains("gradient-*.js") "Plugin auth gate patch should retain the older gradient bundle patch for older Codex Desktop builds."
Assert-True $scriptText.Contains("pluginsAuthBlockedToast.title") "Plugin auth gate patch should anchor the current bundle patch near the plugin auth blocked toast."
Assert-True $scriptText.Contains("index-*.js") "Plugin auth gate patch should scan the main webview bundle for the sidebar Plugins nav gate."
Assert-True $scriptText.Contains("pluginsDisabledTooltip") "Plugin auth gate patch should anchor the sidebar patch near the disabled Plugins tooltip."
Assert-True $scriptText.Contains('authMethod:') "Plugin auth gate patch should recognize the current sidebar auth method guard shape."
Assert-True $scriptText.Contains('533078438') "Plugin auth gate patch should anchor the sidebar auth guard near the current Plugins feature flag."
Assert-True $scriptText.Contains('${prefix}${gate}=!1') "Plugin auth gate patch should force the sidebar plugin auth-block flag false."
Assert-True $scriptText.Contains('$sidebarRegex.Replace') "Plugin auth gate patch should use the Regex instance replace overload for evaluator replacement."

$verifyText = [IO.File]::ReadAllText($verifyScript)
Assert-True $verifyText.Contains('installed-plugin-auth-gate') "Verification should check whether the installed app.asar still has the sidebar Plugins auth gate."
Assert-True $verifyText.Contains('$sidebarPluginGateRegex') "Verification should recognize the stale installed sidebar Plugins auth gate."
Assert-True $verifyText.Contains('$sidebarPluginGatePatchedRegex') "Verification should recognize the patched installed sidebar Plugins auth gate."

Write-Host "Yukino plugin auth gate patch test passed."
