param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$packageJsonPath = Join-Path $ProjectRoot "package.json"
$testRunner = Join-Path $ProjectRoot "tests\Run-YukinoTests.ps1"
$smokeChecklist = Join-Path $ProjectRoot "docs\yukino-smoke-checklist.md"
$readme = Join-Path $ProjectRoot "README.md"
$modNotes = Join-Path $ProjectRoot "MOD_NOTES.md"

Assert-True (Test-Path -LiteralPath $packageJsonPath) "Missing package.json command surface."
Assert-True (Test-Path -LiteralPath $testRunner) "Missing unified test runner: $testRunner"
Assert-True (Test-Path -LiteralPath $smokeChecklist) "Missing Yukino smoke checklist: $smokeChecklist"

$packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
Assert-True ($packageJson.private -eq $true) "package.json should mark this maintenance workspace private."
Assert-True ($packageJson.scripts.test -eq "powershell -NoProfile -ExecutionPolicy Bypass -File tests/Run-YukinoTests.ps1") "npm test should run the unified Yukino test runner."
Assert-True ($packageJson.scripts.build -eq "powershell -NoProfile -ExecutionPolicy Bypass -File build-yukino.ps1") "npm run build should call build-yukino.ps1."
Assert-True ($packageJson.scripts.verify -eq "powershell -NoProfile -ExecutionPolicy Bypass -File verify-yukino.ps1") "npm run verify should call verify-yukino.ps1."
Assert-True ($packageJson.scripts."release:dry" -eq "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish-YukinoRelease.ps1 -DryRun") "npm run release:dry should prepare release assets without publishing."
Assert-True ($packageJson.scripts.release -eq "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish-YukinoRelease.ps1 -Latest") "npm run release should publish through the existing release script."

$runnerText = [IO.File]::ReadAllText($testRunner)
foreach ($testName in @(
    "Test-YukinoBuildProcessSafety.ps1",
    "Test-YukinoReleaseWorkflow.ps1",
    "Test-YukinoPluginAuthGatePatch.ps1",
    "Test-YukinoSidebarBackground.ps1",
    "Test-YukinoIconAssets.ps1",
    "Test-YukinoExecutableIconPatch.ps1",
    "Test-YukinoWorkflowHardening.ps1",
    "Test-YukinoBuildAudit.ps1",
    "Test-YukinoControlHome.ps1"
)) {
    Assert-True $runnerText.Contains($testName) "Unified test runner should include $testName."
}

$checklistText = [IO.File]::ReadAllText($smokeChecklist)
foreach ($needle in @(
    "Plugins page opens",
    "Skills page still opens",
    "settings write",
    "sidebar background",
    ".yukino",
    "official OpenAI.Codex remains installed"
)) {
    Assert-True $checklistText.Contains($needle) "Smoke checklist should mention: $needle"
}

$readmeText = [IO.File]::ReadAllText($readme)
Assert-True $readmeText.Contains("npm test") "README should document the unified npm test command."
Assert-True $readmeText.Contains("npm run verify") "README should document the unified verification command."
Assert-True $readmeText.Contains("docs/yukino-smoke-checklist.md") "README should point to the Yukino smoke checklist."

$modNotesText = [IO.File]::ReadAllText($modNotes)
Assert-True $modNotesText.Contains("package.json") "MOD_NOTES should mention the package.json command surface."
Assert-True $modNotesText.Contains("build-history.jsonl") "MOD_NOTES should mention build history records."
Assert-True $modNotesText.Contains("source-manifest.json") "MOD_NOTES should mention source manifest records."
Assert-True $modNotesText.Contains("build-audit.json") "MOD_NOTES should mention build audit records."

Write-Host "Yukino workflow hardening test passed."
