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
Assert-True $scriptText.Contains('[switch]$SkipSmoke') "Build script should expose -SkipSmoke for release builds run from an active Yukino session."
Assert-True $scriptText.Contains("Test-InstalledYukinoRunning") "Build script should detect whether the installed Yukino app is already running."
Assert-True $scriptText.Contains('$installedYukinoRunning = Test-InstalledYukinoRunning') "Build script should compute installed Yukino activity before source smoke testing."
Assert-True $scriptText.Contains('Skipping source smoke launch') "Build script should skip source smoke testing when -SkipSmoke is set or installed Yukino is running."
Assert-True $scriptText.Contains("Stop-YukinoProcessTree") "Build script should stop only a targeted process tree."
Assert-True $scriptText.Contains('Start-Process -FilePath $newExe -PassThru') "Build script should track the smoke-test process it starts."
Assert-True $scriptText.Contains('Stop-YukinoProcessTree -RootProcessId $process.Id') "Build script should stop the smoke-test process by PID, not by app name."
Assert-True $scriptText.Contains('Join-Path $extractDir "webview\assets"') "Build script should run node --check over patched webview assets, not only Electron bootstrap files."
Assert-True (-not $scriptText.Contains('Where-Object { $_.Name -eq "$DisplayName.exe" }')) "Build script must not kill every running Yukino.exe before smoke testing."
Assert-True (-not $scriptText.Contains('Where-Object { $_.ExecutablePath -eq $newExe }')) "Build script should not rely on executable-path scans to clean up smoke-test children."

Write-Host "Yukino build process safety test passed."
