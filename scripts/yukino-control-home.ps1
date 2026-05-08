$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-YukinoControlHome {
    if ($env:YUKINO_HOME) {
        return $env:YUKINO_HOME
    }

    return Join-Path $env:USERPROFILE ".yukino"
}

function New-YukinoDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-YukinoJsonFile([string]$Path, $Value) {
    New-YukinoDirectory (Split-Path -Parent $Path)
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($Path, "$json`n", [Text.UTF8Encoding]::new($false))
}

function Add-YukinoJsonLine([string]$Path, $Value) {
    New-YukinoDirectory (Split-Path -Parent $Path)
    $json = $Value | ConvertTo-Json -Depth 12 -Compress
    [IO.File]::AppendAllText($Path, "$json`n", [Text.UTF8Encoding]::new($false))
}

function New-YukinoControlHome {
    $controlHome = Get-YukinoControlHome
    New-YukinoDirectory $controlHome

    Write-YukinoJsonFile (Join-Path $controlHome "yukino.json") ([ordered]@{
        identity = "Yukino"
        packageName = "yukino.akane"
        controlHome = $controlHome
        updatedAt = [DateTime]::UtcNow.ToString("o")
    })

    return $controlHome
}

function Write-YukinoBuildRecord {
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [string]$SourcePackageFullName = "",
        [string]$SourceVersion = "",
        [string]$TargetVersion = "",
        [string]$MsixPath = "",
        [string]$WorkDir = "",
        [bool]$Installed = $false,
        [hashtable]$Summary = @{}
    )

    $controlHome = New-YukinoControlHome
    Add-YukinoJsonLine (Join-Path $controlHome "build-history.jsonl") ([ordered]@{
        event = $EventName
        status = "passed"
        sourcePackageFullName = $SourcePackageFullName
        sourceVersion = $SourceVersion
        targetVersion = $TargetVersion
        msixPath = $MsixPath
        workDir = $WorkDir
        installed = $Installed
        summary = $Summary
        createdAt = [DateTime]::UtcNow.ToString("o")
    })
}

function Write-YukinoVerificationRecord {
    param(
        [string]$Status = "passed",
        [string]$ProjectRoot = "",
        [string[]]$Checks = @()
    )

    $controlHome = New-YukinoControlHome
    Add-YukinoJsonLine (Join-Path $controlHome "verify-history.jsonl") ([ordered]@{
        event = "verify-yukino"
        status = $Status
        projectRoot = $ProjectRoot
        checks = @($Checks)
        createdAt = [DateTime]::UtcNow.ToString("o")
    })
}

function Write-YukinoReleaseRecord {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [string]$MsixPath = "",
        [string]$MsixSha256 = "",
        [string]$Url = ""
    )

    $controlHome = New-YukinoControlHome
    Add-YukinoJsonLine (Join-Path $controlHome "release-history.jsonl") ([ordered]@{
        event = "release"
        status = "published"
        tag = $Tag
        msixPath = $MsixPath
        msixSha256 = $MsixSha256
        url = $Url
        createdAt = [DateTime]::UtcNow.ToString("o")
    })
}
