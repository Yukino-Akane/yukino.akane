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

$controlScript = Join-Path $ProjectRoot "scripts\yukino-control-home.ps1"
Assert-True (Test-Path -LiteralPath $controlScript) "Missing Yukino control home script: $controlScript"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("yukino-control-test-" + [guid]::NewGuid().ToString("N"))
$env:YUKINO_HOME = Join-Path $tempRoot ".yukino"

try {
    . $controlScript

    Write-YukinoBuildRecord `
        -EventName "build" `
        -SourcePackageFullName "OpenAI.Codex_26.506.2212.0_x64__2p2nqsd0c76g0" `
        -SourceVersion "26.506.2212.0" `
        -TargetVersion "26.506.2212.1" `
        -MsixPath "D:\zhish\yukino.akane\out\yukino.akane_26.506.2212.1_x64.msix" `
        -WorkDir "D:\zhish\yukino.akane\logs\build-test" `
        -Installed:$false `
        -Summary @{ skipSmoke = $true; audit = "passed" }

    Write-YukinoVerificationRecord `
        -Status "passed" `
        -ProjectRoot $ProjectRoot `
        -Checks @("plugin-auth-gate", "sidebar-plugin-route")

    Write-YukinoReleaseRecord `
        -Tag "v26.506.2212.1-yukino.2" `
        -MsixPath "D:\zhish\yukino.akane\out\yukino.akane_26.506.2212.1_x64.msix" `
        -MsixSha256 "8A8D61344A7BE17D8B4B1FD30CF4293AF0E319DA7CBA32AE50D65F64A598E691" `
        -Url "https://github.com/Yukino-Akane/yukino.akane/releases/tag/v26.506.2212.1-yukino.2"

    $identityPath = Join-Path $env:YUKINO_HOME "yukino.json"
    $buildHistoryPath = Join-Path $env:YUKINO_HOME "build-history.jsonl"
    $verifyHistoryPath = Join-Path $env:YUKINO_HOME "verify-history.jsonl"
    $releaseHistoryPath = Join-Path $env:YUKINO_HOME "release-history.jsonl"

    Assert-True (Test-Path -LiteralPath $identityPath) "Control home should write yukino.json."
    Assert-True (Test-Path -LiteralPath $buildHistoryPath) "Control home should write build-history.jsonl."
    Assert-True (Test-Path -LiteralPath $verifyHistoryPath) "Control home should write verify-history.jsonl."
    Assert-True (Test-Path -LiteralPath $releaseHistoryPath) "Control home should write release-history.jsonl."

    $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
    Assert-True ($identity.identity -eq "Yukino") "Identity file should record Yukino."
    Assert-True ($identity.packageName -eq "yukino.akane") "Identity file should record package name."

    $buildRecord = (Get-Content -LiteralPath $buildHistoryPath | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($buildRecord.sourcePackageFullName -like "OpenAI.Codex_*") "Build history should record source package."
    Assert-True ($buildRecord.targetVersion -eq "26.506.2212.1") "Build history should record target version."
    Assert-True ($buildRecord.summary.audit -eq "passed") "Build history should record summary."

    $verifyRecord = (Get-Content -LiteralPath $verifyHistoryPath | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($verifyRecord.status -eq "passed") "Verification history should record status."
    Assert-True ($verifyRecord.checks -contains "plugin-auth-gate") "Verification history should record checks."

    $releaseRecord = (Get-Content -LiteralPath $releaseHistoryPath | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($releaseRecord.tag -eq "v26.506.2212.1-yukino.2") "Release history should record tag."
    Assert-True ($releaseRecord.msixSha256.Length -eq 64) "Release history should record MSIX SHA256."
}
finally {
    Remove-Item Env:\YUKINO_HOME -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "Yukino control home test passed."
