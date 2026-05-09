param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$PackageName = "yukino.akane",
    [string]$OfficialPackageName = "OpenAI.Codex",
    [string]$ConfigPath = "$env:USERPROFILE\.yukino\config.toml",
    [string]$Repo = "Yukino-Akane/yukino.akane",
    [string]$ReleaseTag = "",
    [int]$RecentLogFileCount = 8
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [string]$Status, [string]$Detail) {
    $checks.Add([pscustomobject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
    }) | Out-Null
}

function Get-TomlStringValue([string]$Text, [string]$Key) {
    $pattern = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*"([^"]*)"'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return $null
}

function Test-TomlSectionBoolean([string]$Text, [string]$SectionPattern, [string]$Key, [bool]$Expected) {
    $value = if ($Expected) { "true" } else { "false" }
    $pattern = '(?ms)^\s*\[' + $SectionPattern + '\]\s*(?:(?!^\s*\[).)*?^\s*' + [regex]::Escape($Key) + '\s*=\s*' + $value + '\s*(?:#.*)?$'
    return [regex]::IsMatch($Text, $pattern)
}

function Get-LogField([string]$Line, [string]$Name) {
    $match = [regex]::Match($Line, '(?:^|\s)' + [regex]::Escape($Name) + '=([^ ]+)')
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return ""
}

function Get-GitOutput([string[]]$Arguments, [string]$WorkingDirectory) {
    Push-Location $WorkingDirectory
    try {
        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $exitCode
            Text = ($output -join "`n")
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "Yukino local state diagnostic"
Write-Host "ProjectRoot: $ProjectRoot"
Write-Host "ConfigPath : $ConfigPath"

$project = $null
try {
    $project = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path
    Add-Check "project-root" "PASS" $project
}
catch {
    Add-Check "project-root" "FAIL" "Missing project root: $ProjectRoot"
}

$installed = @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending)
if ($installed.Count -eq 0) {
    Add-Check "installed-yukino-package" "FAIL" "No installed package named $PackageName"
}
else {
    $pkg = $installed[0]
    Add-Check "installed-yukino-package" "PASS" "PackageFullName=$($pkg.PackageFullName); Version=$($pkg.Version); InstallLocation=$($pkg.InstallLocation)"

    $exe = Join-Path $pkg.InstallLocation "app\Yukino.exe"
    if (Test-Path -LiteralPath $exe) {
        Add-Check "installed-yukino-exe" "PASS" $exe
    }
    else {
        Add-Check "installed-yukino-exe" "FAIL" "Missing installed executable: $exe"
    }
}

$officialPackages = @(Get-AppxPackage -Name $OfficialPackageName -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending)
if ($officialPackages.Count -eq 0) {
    Add-Check "official-codex-package" "WARN" "No installed package named $OfficialPackageName"
}
else {
    $official = $officialPackages[0]
    Add-Check "official-codex-package" "PASS" "PackageFullName=$($official.PackageFullName); Version=$($official.Version); InstallLocation=$($official.InstallLocation)"
}

if ($installed.Count -gt 0 -and $officialPackages.Count -gt 0) {
    if ($installed[0].PackageFullName -ne $officialPackages[0].PackageFullName -and
        $installed[0].InstallLocation -ne $officialPackages[0].InstallLocation) {
        Add-Check "package-isolation" "PASS" "$PackageName is installed separately from $OfficialPackageName"
    }
    else {
        Add-Check "package-isolation" "FAIL" "$PackageName and $OfficialPackageName appear to share package identity or install location"
    }
}

$running = @(Get-Process -Name "Yukino" -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    $paths = @($running | Select-Object -ExpandProperty Path -Unique)
    Add-Check "running-yukino-process" "PASS" "$($running.Count) process(es); $($paths -join '; ')"
}
else {
    Add-Check "running-yukino-process" "WARN" "Yukino is not currently running"
}

if (Test-Path -LiteralPath $ConfigPath) {
    $configText = [IO.File]::ReadAllText($ConfigPath)
    Add-Check "config-file" "PASS" $ConfigPath

    $approvalPolicy = Get-TomlStringValue $configText "approval_policy"
    if ($approvalPolicy) {
        Add-Check "config-approval-policy" "PASS" "approval_policy=$approvalPolicy"
    }
    else {
        Add-Check "config-approval-policy" "WARN" "approval_policy not found"
    }

    $sandboxMode = Get-TomlStringValue $configText "sandbox_mode"
    if ($sandboxMode) {
        Add-Check "config-sandbox-mode" "PASS" "sandbox_mode=$sandboxMode"
    }
    else {
        Add-Check "config-sandbox-mode" "WARN" "sandbox_mode not found"
    }

    if (Test-TomlSectionBoolean $configText "features" "plugins" $true) {
        Add-Check "config-feature-plugins" "PASS" "features.plugins=true"
    }
    else {
        Add-Check "config-feature-plugins" "WARN" "features.plugins=true not found"
    }

    if (Test-TomlSectionBoolean $configText 'plugins\."browser-use@openai-bundled"' "enabled" $true) {
        Add-Check "config-browser-use-plugin" "PASS" "browser-use@openai-bundled enabled"
    }
    else {
        Add-Check "config-browser-use-plugin" "WARN" "browser-use@openai-bundled enabled=true not found"
    }
}
else {
    Add-Check "config-file" "FAIL" "Missing config: $ConfigPath"
}

$logDate = Get-Date
$appLogDir = Join-Path $env:LOCALAPPDATA ("Yukino\Logs\{0}\{1}\{2}" -f $logDate.ToString("yyyy"), $logDate.ToString("MM"), $logDate.ToString("dd"))
if (Test-Path -LiteralPath $appLogDir) {
    $logFiles = @(Get-ChildItem -LiteralPath $appLogDir -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $RecentLogFileCount)
    Add-Check "recent-log-files" "PASS" "$($logFiles.Count) file(s) under $appLogDir"

    $pluginLines = @()
    $configConflictLines = @()
    $startupErrorLines = @()
    foreach ($file in $logFiles) {
        $matches = Select-String -LiteralPath $file.FullName -Pattern "pluginsAuthBlockedToast|pluginDeepLinkAuthBlocked|configVersionConflict|Unable to save|errorCode=-32600|uncaughtException|Unhandled|startup|fatal" -ErrorAction SilentlyContinue
        foreach ($match in $matches) {
            $line = $match.Line
            $method = Get-LogField $line "method"
            $errorCode = Get-LogField $line "errorCode"
            if ($line -like "*pluginsAuthBlockedToast*" -or $line -like "*pluginDeepLinkAuthBlocked*") {
                $pluginLines += "$($file.Name):$($match.LineNumber):$line"
            }
            if ($line -like "*configVersionConflict*" -or $line -like "*Unable to save*" -or ($method -like "config/*" -and $errorCode -and $errorCode -ne "null")) {
                $configConflictLines += "$($file.Name):$($match.LineNumber):$line"
            }
            if ($line -match "(?i)uncaughtException|Unhandled|fatal") {
                $startupErrorLines += "$($file.Name):$($match.LineNumber):$line"
            }
        }
    }

    if ($pluginLines.Count -eq 0) {
        Add-Check "recent-plugin-log-errors" "PASS" "No plugin auth/deep-link failure markers in latest $RecentLogFileCount log file(s)"
    }
    else {
        Add-Check "recent-plugin-log-errors" "WARN" "$($pluginLines.Count) plugin marker line(s); first=$($pluginLines[0])"
    }

    if ($configConflictLines.Count -eq 0) {
        Add-Check "recent-config-log-errors" "PASS" "No config conflict markers in latest $RecentLogFileCount log file(s)"
    }
    else {
        Add-Check "recent-config-log-errors" "WARN" "$($configConflictLines.Count) config marker line(s); first=$($configConflictLines[0])"
    }

    if ($startupErrorLines.Count -eq 0) {
        Add-Check "recent-startup-log-errors" "PASS" "No fatal startup markers in latest $RecentLogFileCount log file(s)"
    }
    else {
        Add-Check "recent-startup-log-errors" "WARN" "$($startupErrorLines.Count) startup marker line(s); first=$($startupErrorLines[0])"
    }
}
else {
    Add-Check "recent-log-files" "WARN" "No app log directory for today: $appLogDir"
}

if ($project) {
    $gitStatus = Get-GitOutput -Arguments @("status", "--short", "--branch") -WorkingDirectory $project
    if ($gitStatus.ExitCode -eq 0) {
        $firstLine = (($gitStatus.Text -split "`n") | Select-Object -First 1)
        $dirtyLines = @(($gitStatus.Text -split "`n") | Select-Object -Skip 1 | Where-Object { $_ })
        if ($dirtyLines.Count -eq 0) {
            Add-Check "repo-status" "PASS" "git status --short --branch: $firstLine"
        }
        else {
            Add-Check "repo-status" "WARN" "git status --short --branch: $firstLine; dirty entries=$($dirtyLines.Count)"
        }
    }
    else {
        Add-Check "repo-status" "WARN" $gitStatus.Text
    }

    $head = Get-GitOutput -Arguments @("log", "-1", "--oneline", "--decorate") -WorkingDirectory $project
    if ($head.ExitCode -eq 0) {
        Add-Check "repo-head" "PASS" $head.Text
    }
    else {
        Add-Check "repo-head" "WARN" $head.Text
    }
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $tagToCheck = $ReleaseTag
    if (-not $tagToCheck) {
        $tagOutput = & gh release list --repo $Repo --limit 1 --json tagName 2>$null
        if ($LASTEXITCODE -eq 0 -and $tagOutput) {
            $tagData = $tagOutput | ConvertFrom-Json
            if ($tagData -and $tagData[0].tagName) {
                $tagToCheck = $tagData[0].tagName
            }
        }
    }

    if ($tagToCheck) {
        $releaseJson = & gh release view $tagToCheck --repo $Repo --json tagName,name,isDraft,isPrerelease,assets 2>$null
        if ($LASTEXITCODE -eq 0 -and $releaseJson) {
            $release = $releaseJson | ConvertFrom-Json
            $assetNames = @($release.assets | ForEach-Object { $_.name })
            $releaseMsix = @($assetNames | Where-Object { $_ -like "$PackageName*_x64.msix" } | Select-Object -First 1)
            $hasMsix = $releaseMsix.Count -gt 0
            $hasInstaller = $assetNames -contains "Install-YukinoRelease.ps1"
            $hasChecksum = $assetNames -contains "SHA256SUMS.txt"
            $hasCert = $assetNames -contains "Yukino.cer"
            if ($hasMsix -and $hasInstaller -and $hasChecksum -and $hasCert -and -not $release.isDraft) {
                Add-Check "release-assets" "PASS" "gh release view $tagToCheck; assets=$($assetNames -join ', ')"
            }
            else {
                Add-Check "release-assets" "WARN" "gh release view $tagToCheck; missing expected asset or draft release"
            }
        }
        else {
            Add-Check "release-assets" "WARN" "gh release view failed for $Repo $tagToCheck"
        }

        if ($installed.Count -gt 0 -and $releaseMsix.Count -gt 0) {
            $versionMatch = [regex]::Match($releaseMsix[0], "^(?<package>.+)_(?<version>\d+\.\d+\.\d+\.\d+)_x64\.msix$")
            if ($versionMatch.Success) {
                $releaseVersion = $versionMatch.Groups["version"].Value
                if ($installed[0].Version.ToString() -eq $releaseVersion) {
                    Add-Check "installed-release-version" "PASS" "Installed version $($installed[0].Version) matches release MSIX $($releaseMsix[0])"
                }
                else {
                    Add-Check "installed-release-version" "WARN" "Installed version $($installed[0].Version) differs from release MSIX version $releaseVersion"
                }
            }
            else {
                Add-Check "installed-release-version" "WARN" "Could not infer version from release MSIX asset: $($releaseMsix[0])"
            }
        }
    }
    else {
        Add-Check "release-assets" "WARN" "No release tag resolved for $Repo"
    }
}
else {
    Add-Check "release-assets" "WARN" "gh CLI not found; skipped release comparison"
}

Write-Host ""
$checks | Format-Table -AutoSize -Wrap

$failures = @($checks | Where-Object { $_.Status -eq "FAIL" })
$warnings = @($checks | Where-Object { $_.Status -eq "WARN" })

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Local state diagnostic failed: $($failures.Count) failure(s), $($warnings.Count) warning(s)." -ForegroundColor Red
    exit 1
}
elseif ($warnings.Count -gt 0) {
    Write-Host "Local state diagnostic passed with $($warnings.Count) warning(s)." -ForegroundColor Yellow
}
else {
    Write-Host "Local state diagnostic passed." -ForegroundColor Green
}
