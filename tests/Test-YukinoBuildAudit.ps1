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

function Write-Utf8File([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

$manifestScript = Join-Path $ProjectRoot "scripts\Write-YukinoSourceManifest.ps1"
$auditScript = Join-Path $ProjectRoot "scripts\Write-YukinoBuildAudit.ps1"

Assert-True (Test-Path -LiteralPath $manifestScript) "Missing source manifest script: $manifestScript"
Assert-True (Test-Path -LiteralPath $auditScript) "Missing build audit script: $auditScript"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("yukino-audit-test-" + [guid]::NewGuid().ToString("N"))
$sourceRoot = Join-Path $tempRoot "source"
$outputRoot = Join-Path $tempRoot "output"
$manifestPath = Join-Path $tempRoot "source-manifest.json"
$auditPath = Join-Path $tempRoot "build-audit.json"

try {
    Write-Utf8File (Join-Path $sourceRoot "AppxManifest.xml") "<Package><Identity Name='OpenAI.Codex' /></Package>"
    Write-Utf8File (Join-Path $sourceRoot "app\Codex.exe") "official exe"
    Write-Utf8File (Join-Path $sourceRoot "app\resources\app.asar") "official asar"
    Write-Utf8File (Join-Path $sourceRoot "app\resources\plugins\plugin.json") "{`"name`":`"Codex plugin`"}"
    Write-Utf8File (Join-Path $sourceRoot "AppxBlockMap.xml") "block map"
    Write-Utf8File (Join-Path $sourceRoot "AppxSignature.p7x") "signature"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $manifestScript `
        -SourceRoot $sourceRoot `
        -SourcePackageFullName "OpenAI.Codex_26.506.2212.0_x64__2p2nqsd0c76g0" `
        -SourceVersion "26.506.2212.0" `
        -ManifestPath $manifestPath
    Assert-True ($LASTEXITCODE -eq 0) "Source manifest script failed."

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-True ($manifest.sourcePackageFullName -eq "OpenAI.Codex_26.506.2212.0_x64__2p2nqsd0c76g0") "Source manifest should record package full name."
    Assert-True ($manifest.artifacts.Count -ge 3) "Source manifest should record key source artifacts."
    Assert-True (($manifest.artifacts | Where-Object { $_.id -eq "source.appAsar" }).sha256.Length -eq 64) "Source manifest should hash app.asar."

    Write-Utf8File (Join-Path $outputRoot "AppxManifest.xml") "<Package><Identity Name='yukino.akane' /></Package>"
    Write-Utf8File (Join-Path $outputRoot "app\Yukino.exe") "official exe"
    Write-Utf8File (Join-Path $outputRoot "app\resources\app.asar") "patched asar"
    Write-Utf8File (Join-Path $outputRoot "app\resources\plugins\plugin.json") "{`"name`":`"Yukino plugin`"}"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $auditScript `
        -SourceManifestPath $manifestPath `
        -OutputRoot $outputRoot `
        -AuditPath $auditPath `
        -DisplayName "Yukino"
    Assert-True ($LASTEXITCODE -eq 0) "Build audit script should accept expected Yukino differences."

    $audit = Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
    Assert-True ($audit.status -eq "passed") "Build audit should record passed status."
    Assert-True (($audit.expectedChanged -contains "AppxManifest.xml") -and ($audit.expectedChanged -contains "app/resources/app.asar")) "Build audit should record expected changed files."
    Assert-True ($audit.expectedChanged -contains "app/resources/plugins/plugin.json") "Build audit should allow branded loose plugin resources."
    Assert-True ($audit.expectedAdded -contains "app/Yukino.exe") "Build audit should record the renamed Yukino executable."
    Assert-True ($audit.expectedRemoved -contains "app/Codex.exe") "Build audit should record removed Codex executable."

    Write-Utf8File (Join-Path $outputRoot "AppxSignature.p7x") "stale signature"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $auditOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $auditScript `
            -SourceManifestPath $manifestPath `
            -OutputRoot $outputRoot `
            -AuditPath (Join-Path $tempRoot "bad-audit.json") `
            -DisplayName "Yukino" 2>&1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Assert-True ($LASTEXITCODE -ne 0) "Build audit should reject stale AppxSignature.p7x in output."
    Assert-True (($auditOutput | Out-String) -match "AppxSignature\.p7x") "Build audit should explain stale signature failure."
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "Yukino build audit test passed."
