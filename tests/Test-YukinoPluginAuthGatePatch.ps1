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
Assert-True $scriptText.Contains('s&&!0') "Plugin auth gate patch should keep the Plugins page entry enabled while bypassing the API-key guard."
Assert-True (-not $scriptText.Contains('s&&!1')) "Plugin auth gate patch must not replace the Plugins page entry with a permanently false condition."
Assert-True $scriptText.Contains("gradient-*.js") "Plugin auth gate patch should retain the older gradient bundle patch for older Codex Desktop builds."
Assert-True $scriptText.Contains("pluginsAuthBlockedToast.title") "Plugin auth gate patch should anchor the current bundle patch near the plugin auth blocked toast."
Assert-True $scriptText.Contains("plugin-detail-page-*.js") "Plugin auth gate patch should scan the new plugin detail bundle used by current Codex Desktop builds."
Assert-True $scriptText.Contains("pluginDeepLinkAuthBlocked") "Plugin auth gate patch should recognize the current plugin detail deep-link redirect guard."
Assert-True $scriptText.Contains('$pluginDetailRedirectRegex') "Plugin auth gate patch should recognize the stale plugin detail deep-link redirect guard."
Assert-True $scriptText.Contains('!1&&') "Plugin auth gate patch should disable the plugin detail deep-link auth redirect without removing the route."
Assert-True $scriptText.Contains("index-*.js") "Plugin auth gate patch should scan the main webview bundle for the sidebar Plugins nav gate."
Assert-True $scriptText.Contains("pluginsDisabledTooltip") "Plugin auth gate patch should anchor the sidebar patch near the disabled Plugins tooltip."
Assert-True $scriptText.Contains('authMethod:') "Plugin auth gate patch should recognize the current sidebar auth method guard shape."
Assert-True $scriptText.Contains('533078438') "Plugin auth gate patch should anchor the sidebar auth guard near the current Plugins feature flag."
Assert-True $scriptText.Contains('${prefix}${gate}=!1') "Plugin auth gate patch should force the sidebar plugin auth-block flag false."
Assert-True $scriptText.Contains('$sidebarRegex.Replace') "Plugin auth gate patch should use the Regex instance replace overload for evaluator replacement."
Assert-True $scriptText.Contains("Patch-PluginSidebarRoute") "Build script should patch the sidebar Plugins route separately from the auth gate."
Assert-True $scriptText.Contains('app-main-*.js') "Sidebar patches should scan the current app-main bundle used by newer Codex Desktop builds."
Assert-True $scriptText.Contains('$handlerRoutePattern') "Sidebar route patch should support the current extracted click-handler route shape."
Assert-True $scriptText.Contains('?`plugins`:`skills`') "Sidebar route patch should log the selected Plugins or Skills nav item instead of always logging skills."
Assert-True $scriptText.Contains('?`/plugins`:`/skills`') "Sidebar route patch should navigate to the real Plugins page when the combined sidebar item is labelled Plugins."

$verifyText = [IO.File]::ReadAllText($verifyScript)
Assert-True $verifyText.Contains('installed-plugin-auth-gate') "Verification should check whether the installed app.asar still has the sidebar Plugins auth gate."
Assert-True $verifyText.Contains('$sidebarPluginGateRegex') "Verification should recognize the stale installed sidebar Plugins auth gate."
Assert-True $verifyText.Contains('$sidebarPluginGatePatchedRegex') "Verification should recognize the patched installed sidebar Plugins auth gate."
Assert-True $verifyText.Contains('$sidebarPluginHandlerRouteRegex') "Verification should recognize the current sidebar Plugins click-handler route shape."
Assert-True $verifyText.Contains('$sidebarPluginHandlerRoutePatchedRegex') "Verification should recognize the patched current sidebar Plugins click-handler route shape."
Assert-True $verifyText.Contains('s&&!0') "Verification should require the Plugins page entry to stay enabled for API-key users."
Assert-True $verifyText.Contains('s&&!1') "Verification should reject installed bundles that permanently disable the Plugins page entry."
Assert-True $verifyText.Contains('$pluginDetailRedirectRegex') "Verification should detect the current stale plugin detail deep-link redirect guard."
Assert-True $verifyText.Contains('$pluginDetailRedirectPatchedRegex') "Verification should recognize the patched plugin detail deep-link redirect guard."
Assert-True $verifyText.Contains('sidebar-plugin-route') "Verification should check that the latest extracted webview sidebar opens the real Plugins page."
Assert-True $verifyText.Contains('installed-sidebar-plugin-route') "Verification should check that the installed app.asar opens the real Plugins page from the sidebar."

Write-Host "Yukino plugin auth gate patch test passed."
