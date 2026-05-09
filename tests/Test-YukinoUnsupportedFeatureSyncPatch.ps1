param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$buildScript = Join-Path $ProjectRoot "build-yukino.ps1"
$verifyScript = Join-Path $ProjectRoot "verify-yukino.ps1"
$testRoot = Join-Path $env:TEMP ("yukino-feature-sync-test-" + [guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $buildScript) "Missing build script: $buildScript"
Assert-True (Test-Path -LiteralPath $verifyScript) "Missing verification script: $verifyScript"

$buildText = [IO.File]::ReadAllText($buildScript)
$verifyText = [IO.File]::ReadAllText($verifyScript)

Assert-True $buildText.Contains('=``workspace_dependencies``') "Build patch should consume the full workspace_dependencies template literal."
Assert-True $buildText.Contains('$filteredFeatures') "Build patch should filter workspace_dependencies out of the sync feature set."
Assert-True (-not $buildText.Contains('+,`workspace_dependencies`]),')) "Build patch must not add workspace_dependencies to the sync feature set."
Assert-True $verifyText.Contains('SyntaxRiskCount') "Verification should detect malformed workspace_dependencies template literal syntax."
Assert-True $verifyText.Contains('workspace_dependencies``') "Verification should reject the exact malformed syntax that kept the renderer at the splash screen."

New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $badAsset = Join-Path $testRoot "src-bad.js"
    @'
var Rt={file:`file-menu`},zt=`features.`,Bt=new Set([`memories`,`plugins`,`apps`,`tool_suggest`,`tool_search`,`tool_call_mcp_elicitation`,`workspace_dependencies`]),Vt=`workspace_dependencies``;function Ht(e){return e}
'@ | Set-Content -LiteralPath $badAsset -Encoding UTF8

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    node --check $badAsset 2>$null
    $badExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    Assert-True ($badExitCode -ne 0) "Malformed workspace_dependencies template literal should fail node --check."

    $goodAsset = Join-Path $testRoot "src-good.js"
    @'
var Rt={file:`file-menu`},zt=`features.`,Bt=new Set([`memories`,`plugins`,`apps`,`tool_suggest`,`tool_search`,`tool_call_mcp_elicitation`]),Vt=`workspace_dependencies`;function Ht(e){return e}
'@ | Set-Content -LiteralPath $goodAsset -Encoding UTF8

    node --check $goodAsset
    Assert-True ($LASTEXITCODE -eq 0) "Filtered workspace_dependencies patch should preserve valid JavaScript."
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Yukino unsupported feature sync patch test passed."
