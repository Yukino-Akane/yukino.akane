$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tests = @(
    "Test-YukinoBuildProcessSafety.ps1",
    "Test-YukinoReleaseWorkflow.ps1",
    "Test-YukinoPluginAuthGatePatch.ps1",
    "Test-YukinoSidebarBackground.ps1",
    "Test-YukinoIconAssets.ps1",
    "Test-YukinoExecutableIconPatch.ps1",
    "Test-YukinoWorkflowHardening.ps1",
    "Test-YukinoBuildAudit.ps1",
    "Test-YukinoControlHome.ps1"
)

foreach ($test in $tests) {
    $path = Join-Path $PSScriptRoot $test
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing test: $path"
    }

    Write-Host ""
    Write-Host "== $test ==" -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $path -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) {
        throw "$test failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "Yukino test suite passed." -ForegroundColor Green
