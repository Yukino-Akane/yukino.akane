param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$browserSmokeScript = Join-Path $ProjectRoot "scripts\Test-YukinoPostInstallBrowserSmoke.ps1"
$releaseInstallSmokeScript = Join-Path $ProjectRoot "scripts\Test-YukinoReleaseInstall.ps1"
$testRunner = Join-Path $ProjectRoot "tests\Run-YukinoTests.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $browserSmokeScript) "Missing post-install Browser smoke script: $browserSmokeScript"

$browserSmokeText = [IO.File]::ReadAllText($browserSmokeScript)
Assert-True $browserSmokeText.Contains("installed-yukino-package") "Post-install Browser smoke should verify the installed Yukino package."
Assert-True $browserSmokeText.Contains("installed-yukino-exe") "Post-install Browser smoke should verify app\Yukino.exe."
Assert-True $browserSmokeText.Contains("app-server-yukino-process") "Post-install Browser smoke should verify the app-server process is running from Yukino."
Assert-True $browserSmokeText.Contains("browser-use-native-pipe-server") "Post-install Browser smoke should verify Browser runtime pipe log markers."
Assert-True $browserSmokeText.Contains("BrowserUseThreadConfig") "Post-install Browser smoke should verify Browser runtime path selection."
Assert-True $browserSmokeText.Contains("node_repl.exe") "Post-install Browser smoke should verify a live Yukino node_repl runtime."
Assert-True $browserSmokeText.Contains("RequireBrowserRuntimeActivity") "Post-install Browser smoke should support strict Browser runtime activity checks after a manual Browser tool call."
Assert-True $browserSmokeText.Contains("Find-FirstRecentLogMatch") "Post-install Browser smoke should filter Browser runtime evidence by log line timestamp, not just file mtime."
Assert-True $browserSmokeText.Contains("browser-runtime-activity-log") "Post-install Browser smoke should emit a named Browser runtime activity check."
Assert-True $browserSmokeText.Contains("Find-BrowserRuntimeActivityLog") "Post-install Browser smoke should pair Browser activity start/end markers instead of accepting unrelated lines."
Assert-True $browserSmokeText.Contains("captured turn route") "Post-install Browser smoke should require a real Browser tool turn in strict mode."
Assert-True $browserSmokeText.Contains("ended browser use turn route") "Post-install Browser smoke should require a completed Browser tool turn in strict mode."
Assert-True $browserSmokeText.Contains("turnId") "Post-install Browser smoke should match Browser activity markers by turnId."
Assert-True $browserSmokeText.Contains("browser-runtime-tab-log") "Post-install Browser smoke should report stronger tab/page evidence when available without requiring a new tab every run."
Assert-True $browserSmokeText.Contains('"node-repl-yukino-runtime" "WARN"') "Post-install Browser smoke should warn, not fail, when Browser runtime has not been triggered yet."
Assert-True $browserSmokeText.Contains('"browser-use-native-pipe-server" "WARN"') "Post-install Browser smoke should warn, not fail, when the Browser pipe has not been triggered yet."
Assert-True $browserSmokeText.Contains('"browser-runtime-yukino-path-log" "WARN"') "Post-install Browser smoke should warn, not fail, when runtime path logs have not been triggered yet."
Assert-True $browserSmokeText.Contains("Browser runtime has not been triggered") "Post-install Browser smoke should explain lazy Browser runtime evidence."
Assert-True $browserSmokeText.Contains("check-extension-installed.js") "Post-install Browser smoke should verify the Chrome extension is installed and enabled."
Assert-True $browserSmokeText.Contains("check-native-host-manifest.js") "Post-install Browser smoke should verify the Chrome native host manifest."
Assert-True $browserSmokeText.Contains("open-chrome-window.js") "Post-install Browser smoke should dry-run a harmless Chrome open command."
Assert-True $browserSmokeText.Contains("--dry-run") "Post-install Browser smoke should default to a non-disruptive Chrome dry run."
Assert-True $browserSmokeText.Contains("about:blank") "Post-install Browser smoke should only use a harmless URL."
Assert-True $browserSmokeText.Contains("chrome-native-host-yukino-target") "Post-install Browser smoke should require the native host to target Yukino's cache."
Assert-True $browserSmokeText.Contains("MinLogTime") "Post-install Browser smoke should support filtering logs to the current launch window."

$releaseInstallText = [IO.File]::ReadAllText($releaseInstallSmokeScript)
Assert-True $releaseInstallText.Contains("Test-YukinoPostInstallBrowserSmoke.ps1") "Release install smoke should call the post-install Browser smoke."
Assert-True $releaseInstallText.Contains("SkipBrowserSmoke") "Release install smoke should allow skipping Browser smoke when launch is skipped."
Assert-True $releaseInstallText.Contains("launchStart") "Release install smoke should capture launch time before invoking Browser smoke."
Assert-True $releaseInstallText.Contains("-MinLogTime") "Release install smoke should pass the launch time to Browser smoke."
Assert-True $releaseInstallText.Contains("RequireBrowserRuntimeActivity") "Release install smoke should expose strict Browser runtime activity checks for manual post-install verification."

$runnerText = [IO.File]::ReadAllText($testRunner)
Assert-True $runnerText.Contains("Test-YukinoPostInstallBrowserSmoke.ps1") "The test suite should include the post-install Browser smoke contract test."

Write-Host "Yukino post-install Browser smoke contract test passed."
