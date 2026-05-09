param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$smokeScript = Join-Path $ProjectRoot "scripts\Test-YukinoReleaseInstall.ps1"
$browserSmokeScript = Join-Path $ProjectRoot "scripts\Test-YukinoPostInstallBrowserSmoke.ps1"
$releaseTest = Join-Path $ProjectRoot "tests\Test-YukinoReleaseWorkflow.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $smokeScript) "Missing release install smoke script: $smokeScript"
Assert-True (Test-Path -LiteralPath $browserSmokeScript) "Missing post-install Browser smoke script: $browserSmokeScript"

$scriptText = [IO.File]::ReadAllText($smokeScript)
Assert-True $scriptText.Contains("gh release download") "Release install smoke should download assets from GitHub instead of using local out artifacts."
Assert-True $scriptText.Contains("SHA256SUMS.txt") "Release install smoke should verify the downloaded MSIX against SHA256SUMS.txt."
Assert-True $scriptText.Contains("Install-YukinoRelease.ps1") "Release install smoke should exercise the published installer path."
Assert-True $scriptText.Contains("verify-yukino.ps1") "Release install smoke should run installed-package verification after installing."
Assert-True $scriptText.Contains("Start-Process") "Release install smoke should perform a launch check against the installed executable."
Assert-True $scriptText.Contains("Test-YukinoPostInstallBrowserSmoke.ps1") "Release install smoke should run the post-install Browser smoke after launch."
Assert-True $scriptText.Contains("Remove-Item") "Release install smoke should clean downloaded release assets unless preservation is requested."

$browserSmokeText = [IO.File]::ReadAllText($browserSmokeScript)
Assert-True $browserSmokeText.Contains("installed-yukino-package") "Post-install Browser smoke should verify the installed Yukino package."
Assert-True $browserSmokeText.Contains("app-server-yukino-process") "Post-install Browser smoke should verify the app-server process is running from Yukino."
Assert-True $browserSmokeText.Contains("browser-use-native-pipe-server") "Post-install Browser smoke should verify Browser runtime pipe log markers."
Assert-True $browserSmokeText.Contains("node_repl.exe") "Post-install Browser smoke should verify a live Yukino node_repl runtime."
Assert-True $browserSmokeText.Contains('"node-repl-yukino-runtime" "WARN"') "Release install smoke should not fail solely because Browser runtime is lazy and untriggered."
Assert-True $browserSmokeText.Contains("Browser runtime has not been triggered") "Release install smoke should report lazy Browser runtime evidence clearly."
Assert-True $browserSmokeText.Contains("check-extension-installed.js") "Post-install Browser smoke should verify the Chrome extension is installed and enabled."
Assert-True $browserSmokeText.Contains("check-native-host-manifest.js") "Post-install Browser smoke should verify the Chrome native host manifest."
Assert-True $browserSmokeText.Contains("open-chrome-window.js") "Post-install Browser smoke should dry-run a harmless Chrome open command."

$releaseTestText = [IO.File]::ReadAllText($releaseTest)
Assert-True $releaseTestText.Contains("Test-YukinoReleaseInstall.ps1") "Release workflow tests should enforce the release install smoke script contract."

Write-Host "Yukino release install smoke test passed."
