param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Repo = "Yukino-Akane/yukino.akane",
    [string]$MsixPath = "",
    [switch]$SkipRemoteCheck
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Add-Finding([System.Collections.Generic.List[object]]$Findings, [string]$Check, [string]$Detail) {
    $Findings.Add([pscustomobject]@{
        Check = $Check
        Detail = $Detail
    }) | Out-Null
}

function Invoke-GitLines([string[]]$Arguments) {
    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }

    return @($output)
}

function Convert-GitGrepFinding([string]$Line) {
    if ($Line -match '^[^:]+:(?<file>[^:]+):(?<line>\d+):') {
        return "$($Matches["file"]):$($Matches["line"])"
    }

    return "[redacted git-grep match]"
}

function Test-GitGrep([string]$Pattern, [string]$Check, [string[]]$Pathspecs, [System.Collections.Generic.List[object]]$Findings) {
    $arguments = @("grep", "-n", "-I", "-i", "-E", $Pattern, "HEAD", "--") + $Pathspecs
    $output = & git @arguments 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        foreach ($line in @($output)) {
            Add-Finding $Findings $Check (Convert-GitGrepFinding $line)
        }
    }
    elseif ($exitCode -ne 1) {
        throw "git grep for $Check failed with exit code $exitCode."
    }
}

function Test-MsixPaths([string]$Path, [System.Collections.Generic.List[object]]$Findings) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $dangerousPathPattern = '(?i)(^|/|\\)(\.env|\.yukino|\.codex|credentials?\.json|auth\.json|config\.toml|openclaw\.json|plugins/cache)(/|\\|$)'
        $cpaPathPattern = '(?i)(legacy[-_]?cpa|cpa-sub2api|sub2api)'
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match $dangerousPathPattern) {
                Add-Finding $Findings "msix-dangerous-path" $entry.FullName
            }
            if ($entry.FullName -match $cpaPathPattern) {
                Add-Finding $Findings "msix-cpa-path" $entry.FullName
            }
        }
    }
    finally {
        $zip.Dispose()
    }
}

$project = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path
Push-Location $project
try {
    $findings = [System.Collections.Generic.List[object]]::new()

    if (-not $SkipRemoteCheck) {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw "gh CLI is required for release safety remote checks."
        }

        $repoJson = & gh repo view $Repo --json isPrivate,visibility,nameWithOwner 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to read GitHub repository state for $Repo."
        }

        $repoState = $repoJson | ConvertFrom-Json
        if ($repoState.isPrivate -ne $true -or $repoState.visibility -ne "PRIVATE") {
            Add-Finding $findings "repo-visibility" "$($repoState.nameWithOwner) is $($repoState.visibility)"
        }
    }

    $trackedFiles = Invoke-GitLines @("ls-tree", "-r", "--name-only", "HEAD")
    $dangerousFilePattern = '(?i)(^|/)(\.env($|\.)|\.yukino/|\.codex/|out/|logs/|src_unpacked/|credentials?\.json$|auth\.json$|.*\.(key|pem|pfx|ppk)$)'
    foreach ($file in $trackedFiles) {
        if ($file -match $dangerousFilePattern) {
            Add-Finding $findings "tracked-dangerous-file" $file
        }
    }

    $secretPathspecs = @(".", ":!assets/*.jpg", ":!assets/*.jpeg", ":!assets/*.png")
    $cpaPathspecs = @(".", ":!assets/*.jpg", ":!assets/*.jpeg", ":!assets/*.png", ":!README.md", ":!MOD_NOTES.md", ":!scripts/Test-YukinoReleaseSafety.ps1", ":!tests/Test-YukinoReleaseSafety.ps1")
    Test-GitGrep `
        -Pattern '(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN .*PRIVATE KEY-----|OPENAI_API_KEY\s*[:=]|ANTHROPIC_API_KEY\s*[:=]|GH_TOKEN\s*[:=]|GITHUB_TOKEN\s*[:=]|CLOUDFLARE_API_TOKEN\s*[:=]|CF_API_TOKEN\s*[:=])' `
        -Check "tracked-secret-pattern" `
        -Pathspecs $secretPathspecs `
        -Findings $findings
    Test-GitGrep `
        -Pattern '(legacy[-_]?cpa|cpa-sub2api|sub2api|skillId\s*[:=]\s*[`''"]?legacy-cpa)' `
        -Check "tracked-cpa-skill-pattern" `
        -Pathspecs $cpaPathspecs `
        -Findings $findings

    if ($MsixPath) {
        $resolvedMsix = (Resolve-Path -LiteralPath $MsixPath -ErrorAction Stop).Path
        Test-MsixPaths -Path $resolvedMsix -Findings $findings
    }

    if ($findings.Count -gt 0) {
        Write-Host "Yukino release safety findings:" -ForegroundColor Red
        $findings | Format-Table -AutoSize
        throw "Release safety gate failed with $($findings.Count) finding(s)."
    }

    Write-Host "Yukino release safety gate passed."
}
finally {
    Pop-Location
}
