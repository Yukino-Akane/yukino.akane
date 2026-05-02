param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$PackageName = "yukino.akane",
    [string]$ConfigPath = "$env:USERPROFILE\.yukino\config.toml",
    [string]$ExpectedApprovalPolicy = "",
    [string]$ExpectedSandboxMode = "",
    [int]$RecentLogFileCount = 8
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$checks = New-Object System.Collections.Generic.List[object]
$staleAgentSettingsWrite = 'T(`write-config-value`,{hostId:e,keyPath:n,value:r,mergeStrategy:`upsert`,filePath:z.filePath,expectedVersion:z.expectedVersion})'
$patchedAgentSettingsWrite = 'T(`batch-write-config-value`,{hostId:e,edits:[{keyPath:n,value:r,mergeStrategy:`upsert`}],filePath:z.filePath,expectedVersion:null,reloadUserConfig:!0})'
$sidebarPluginGateRegex = '\{authMethod:[A-Za-z_$][A-Za-z0-9_$]*\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),[A-Za-z_$][A-Za-z0-9_$]*=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),[A-Za-z_$][A-Za-z0-9_$]*=[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*\),[A-Za-z_$][A-Za-z0-9_$]*=[A-Za-z_$][A-Za-z0-9_$]*&&[A-Za-z_$][A-Za-z0-9_$]*'
$sidebarPluginGatePatchedRegex = '\{authMethod:[A-Za-z_$][A-Za-z0-9_$]*\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),[A-Za-z_$][A-Za-z0-9_$]*=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),[A-Za-z_$][A-Za-z0-9_$]*=!1,[A-Za-z_$][A-Za-z0-9_$]*=!1'

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

function Get-FirstFileText([object[]]$Files) {
    if ($Files.Count -eq 0) {
        return $null
    }
    return [IO.File]::ReadAllText($Files[0].FullName)
}

Write-Host ""
Write-Host "Yukino verification report" -ForegroundColor Cyan
Write-Host "ProjectRoot: $ProjectRoot"
Write-Host "ConfigPath : $ConfigPath"

$logsRoot = Join-Path $ProjectRoot "logs"
$outRoot = Join-Path $ProjectRoot "out"

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    Add-Check "project-root" "FAIL" "Missing project root: $ProjectRoot"
}

if (Test-Path -LiteralPath $logsRoot) {
    $latestBuild = Get-ChildItem -LiteralPath $logsRoot -Directory -Filter "build-*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latestBuild) {
        Add-Check "latest-build" "PASS" $latestBuild.FullName
    }
    else {
        Add-Check "latest-build" "FAIL" "No build-* directory under $logsRoot"
    }
}
else {
    $latestBuild = $null
    Add-Check "latest-build" "FAIL" "Missing logs directory: $logsRoot"
}

if ($latestBuild) {
    $assetsDir = Join-Path $latestBuild.FullName "app-extracted\webview\assets"
    if (Test-Path -LiteralPath $assetsDir) {
        $agentAssets = @(Get-ChildItem -LiteralPath $assetsDir -File -Filter "agent-settings-*.js")
        $agentText = Get-FirstFileText $agentAssets
        if ($agentText -eq $null) {
            Add-Check "agent-settings-asset" "FAIL" "No agent-settings-*.js asset found in $assetsDir"
        }
        elseif ($agentText.Contains($patchedAgentSettingsWrite) -and -not $agentText.Contains($staleAgentSettingsWrite)) {
            Add-Check "agent-settings-write-patch" "PASS" $agentAssets[0].FullName
        }
        elseif ($agentText.Contains($staleAgentSettingsWrite)) {
            Add-Check "agent-settings-write-patch" "FAIL" "Stale write-config-value route remains in $($agentAssets[0].FullName)"
        }
        else {
            Add-Check "agent-settings-write-patch" "FAIL" "Expected patched batch-write call not found; inspect $($agentAssets[0].FullName)"
        }

        $gatePattern = 'function\s+([A-Za-z_$][A-Za-z0-9_$]*)\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{return\s+\2===`apikey`\}'
        $gateMatches = 0
        $gradientAssets = @(Get-ChildItem -LiteralPath $assetsDir -File -Filter "gradient-*.js")
        foreach ($asset in $gradientAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            $gateMatches += [regex]::Matches($text, $gatePattern).Count
        }
        $skillsPageAssets = @(Get-ChildItem -LiteralPath $assetsDir -File -Filter "skills-page-*.js")
        $skillsPageHasOldGate = $false
        $skillsPageHasPatchedGate = $false
        foreach ($asset in $skillsPageAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            if ($text.Contains("pluginsAuthBlockedToast.title") -and $text.Contains("s&&!m")) {
                $skillsPageHasOldGate = $true
            }
            if ($text.Contains("pluginsAuthBlockedToast.title") -and $text.Contains("s&&!1")) {
                $skillsPageHasPatchedGate = $true
            }
        }

        $sidebarPattern = '(?<prefix>\{authMethod:(?<auth>[A-Za-z_$][A-Za-z0-9_$]*)\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),(?<featureFlag>[A-Za-z_$][A-Za-z0-9_$]*)=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),)(?<gate>[A-Za-z_$][A-Za-z0-9_$]*)=[A-Za-z_$][A-Za-z0-9_$]*\(\k<auth>\),(?<disabledNav>[A-Za-z_$][A-Za-z0-9_$]*)=\k<featureFlag>&&\k<gate>'
        $sidebarPatchedPattern = '(?<prefix>\{authMethod:(?<auth>[A-Za-z_$][A-Za-z0-9_$]*)\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),(?<featureFlag>[A-Za-z_$][A-Za-z0-9_$]*)=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),)(?<gate>[A-Za-z_$][A-Za-z0-9_$]*)=!1,(?<disabledNav>[A-Za-z_$][A-Za-z0-9_$]*)=!1'
        $indexAssets = @(Get-ChildItem -LiteralPath $assetsDir -File -Filter "index-*.js")
        $sidebarHasOldGate = $false
        $sidebarHasPatchedGate = $false
        foreach ($asset in $indexAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            if (-not $text.Contains("pluginsDisabledTooltip")) {
                continue
            }
            if ([regex]::IsMatch($text, $sidebarPattern)) {
                $sidebarHasOldGate = $true
            }
            if ([regex]::IsMatch($text, $sidebarPatchedPattern)) {
                $sidebarHasPatchedGate = $true
            }
        }

        if ($gateMatches -eq 0 -and (-not $skillsPageHasOldGate) -and $skillsPageHasPatchedGate -and (-not $sidebarHasOldGate) -and $sidebarHasPatchedGate) {
            Add-Check "plugin-auth-gate" "PASS" "Desktop plugin auth gate is disabled in skills page and sidebar assets"
        }
        elseif ($gradientAssets.Count -gt 0 -and $gateMatches -eq 0 -and (-not $skillsPageHasOldGate) -and (-not $sidebarHasOldGate)) {
            Add-Check "plugin-auth-gate" "PASS" "No ChatGPT API-key-only gate remains in gradient or sidebar assets"
        }
        else {
            Add-Check "plugin-auth-gate" "FAIL" "$gateMatches legacy API-key gate match(es), skills-page old gate=$skillsPageHasOldGate, sidebar old gate=$sidebarHasOldGate, sidebar patched gate=$sidebarHasPatchedGate"
        }

        $oldSettingsEntry = 'case`plugins-settings`:return d===`extension`&&u;case`skills-settings`:return d===`extension`&&!u;'
        $newSettingsEntry = 'case`plugins-settings`:return d===`electron`||d===`extension`&&u;case`skills-settings`:return d===`extension`&&!u;'
        $settingsAssets = @(Get-ChildItem -LiteralPath $assetsDir -File -Filter "settings-page-*.js")
        $settingsHasOld = $false
        $settingsHasNew = $false
        foreach ($asset in $settingsAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            if ($text.Contains($oldSettingsEntry)) {
                $settingsHasOld = $true
            }
            if ($text.Contains($newSettingsEntry)) {
                $settingsHasNew = $true
            }
        }
        if ($settingsAssets.Count -eq 0) {
            Add-Check "plugins-settings-entry" "WARN" "No settings-page-*.js assets found"
        }
        elseif ($settingsHasNew -and -not $settingsHasOld) {
            Add-Check "plugins-settings-entry" "PASS" "Desktop plugins settings entry is enabled"
        }
        elseif ($settingsHasOld) {
            Add-Check "plugins-settings-entry" "FAIL" "Old extension-only plugins settings entry remains"
        }
        else {
            Add-Check "plugins-settings-entry" "WARN" "Expected settings entry pattern not found; upstream asset may have changed"
        }

        $sidebarBackgroundAsset = Join-Path $assetsDir "yukino-sidebar-background.png"
        $sidebarCssAssets = @(Get-ChildItem -LiteralPath $assetsDir -File -Filter "index-*.css")
        $sidebarCssHasPatch = $false
        $sidebarCssHasAspectSafeSizing = $false
        $sidebarCssHasCenteredPortraitFraming = $false
        $sidebarCssHasDistortedSizing = $false
        $sidebarCssHasFullWindowCover = $false
        foreach ($asset in $sidebarCssAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            if ($text.Contains("/* Yukino sidebar background patch */") -and
                $text.Contains("--yukino-sidebar-background-image") -and
                $text.Contains("yukino-sidebar-background.png") -and
                $text.Contains(".main-surface")) {
                $sidebarCssHasPatch = $true
            }
            if ($text.Contains("background-size: var(--yukino-sidebar-background-width) 100%, auto 100vh;")) {
                $sidebarCssHasAspectSafeSizing = $true
            }
            if ($text.Contains("background-position: left top, calc(var(--yukino-sidebar-background-half-width) - var(--yukino-sidebar-portrait-half-width)) center;")) {
                $sidebarCssHasCenteredPortraitFraming = $true
            }
            if ($text.Contains("background-size: var(--yukino-sidebar-background-width) 100%, var(--yukino-sidebar-background-width) 100%;")) {
                $sidebarCssHasDistortedSizing = $true
            }
            if ($text.Contains("background-size: var(--yukino-sidebar-background-width) 100%, cover;")) {
                $sidebarCssHasFullWindowCover = $true
            }
        }
        if (-not (Test-Path -LiteralPath $sidebarBackgroundAsset)) {
            Add-Check "sidebar-background-patch" "FAIL" "Missing sidebar background asset: $sidebarBackgroundAsset"
        }
        elseif (-not $sidebarCssHasPatch) {
            Add-Check "sidebar-background-patch" "FAIL" "Missing sidebar background CSS patch in index-*.css"
        }
        elseif ($sidebarCssHasDistortedSizing -or $sidebarCssHasFullWindowCover -or -not $sidebarCssHasAspectSafeSizing -or -not $sidebarCssHasCenteredPortraitFraming) {
            Add-Check "sidebar-background-patch" "FAIL" "Sidebar background CSS does not preserve the image aspect ratio"
        }
        else {
            Add-Check "sidebar-background-patch" "PASS" $sidebarBackgroundAsset
        }
    }
    else {
        Add-Check "webview-assets" "FAIL" "Missing assets directory: $assetsDir"
    }
}

$installed = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($installed) {
    Add-Check "installed-package" "PASS" "$($installed.PackageFullName) at $($installed.InstallLocation)"
    $installedAsar = Join-Path $installed.InstallLocation "app\resources\app.asar"
    if (Test-Path -LiteralPath $installedAsar) {
        if (Get-Command rg -ErrorAction SilentlyContinue) {
            & rg -a --fixed-strings --quiet -- $patchedAgentSettingsWrite $installedAsar
            $installedHasPatchedWrite = $LASTEXITCODE -eq 0
            & rg -a --fixed-strings --quiet -- $staleAgentSettingsWrite $installedAsar
            $installedHasStaleWrite = $LASTEXITCODE -eq 0
            if ($installedHasPatchedWrite -and -not $installedHasStaleWrite) {
                Add-Check "installed-agent-settings-patch" "PASS" $installedAsar
            }
            elseif ($installedHasStaleWrite) {
                Add-Check "installed-agent-settings-patch" "FAIL" "Installed app.asar still contains stale Agent Settings write route"
            }
            else {
                Add-Check "installed-agent-settings-patch" "FAIL" "Installed app.asar does not contain expected Agent Settings patch"
            }

            & rg -a --pcre2 --quiet -- $sidebarPluginGateRegex $installedAsar
            $installedHasSidebarPluginGate = $LASTEXITCODE -eq 0
            & rg -a --pcre2 --quiet -- $sidebarPluginGatePatchedRegex $installedAsar
            $installedHasPatchedSidebarPluginGate = $LASTEXITCODE -eq 0
            if ($installedHasPatchedSidebarPluginGate -and -not $installedHasSidebarPluginGate) {
                Add-Check "installed-plugin-auth-gate" "PASS" $installedAsar
            }
            elseif ($installedHasSidebarPluginGate) {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed app.asar still contains the disabled Plugins sidebar gate; install the latest MSIX to apply the fix"
            }
            else {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed app.asar does not contain the expected patched Plugins sidebar gate"
            }

            & rg -a --fixed-strings --quiet -- "yukino-sidebar-background.png" $installedAsar
            $installedHasSidebarBackground = $LASTEXITCODE -eq 0
            & rg -a --fixed-strings --quiet -- "background-size: var(--yukino-sidebar-background-width) 100%, auto 100vh;" $installedAsar
            $installedHasAspectSafeSidebarBackground = $LASTEXITCODE -eq 0
            & rg -a --fixed-strings --quiet -- "background-position: left top, calc(var(--yukino-sidebar-background-half-width) - var(--yukino-sidebar-portrait-half-width)) center;" $installedAsar
            $installedHasCenteredPortraitSidebarBackground = $LASTEXITCODE -eq 0
            & rg -a --fixed-strings --quiet -- "background-size: var(--yukino-sidebar-background-width) 100%, var(--yukino-sidebar-background-width) 100%;" $installedAsar
            $installedHasDistortedSidebarBackground = $LASTEXITCODE -eq 0
            & rg -a --fixed-strings --quiet -- "background-size: var(--yukino-sidebar-background-width) 100%, cover;" $installedAsar
            $installedHasFullWindowCoverSidebarBackground = $LASTEXITCODE -eq 0
            if (-not $installedHasSidebarBackground) {
                Add-Check "installed-sidebar-background-patch" "FAIL" "Installed app.asar does not contain the Yukino sidebar background asset reference"
            }
            elseif ($installedHasDistortedSidebarBackground -or $installedHasFullWindowCoverSidebarBackground -or -not $installedHasAspectSafeSidebarBackground -or -not $installedHasCenteredPortraitSidebarBackground) {
                Add-Check "installed-sidebar-background-patch" "FAIL" "Installed sidebar background CSS does not preserve the image aspect ratio"
            }
            else {
                Add-Check "installed-sidebar-background-patch" "PASS" $installedAsar
            }
        }
        else {
            Add-Check "installed-agent-settings-patch" "WARN" "rg is not available; skipped installed app.asar text probe"
            Add-Check "installed-plugin-auth-gate" "WARN" "rg is not available; skipped installed plugin auth gate text probe"
            Add-Check "installed-sidebar-background-patch" "WARN" "rg is not available; skipped installed sidebar background text probe"
        }
    }
    else {
        Add-Check "installed-agent-settings-patch" "FAIL" "Missing installed app.asar: $installedAsar"
        Add-Check "installed-plugin-auth-gate" "FAIL" "Missing installed app.asar: $installedAsar"
        Add-Check "installed-sidebar-background-patch" "FAIL" "Missing installed app.asar: $installedAsar"
    }
}
else {
    Add-Check "installed-package" "FAIL" "Package $PackageName is not installed"
}

if (Test-Path -LiteralPath $outRoot) {
    $latestMsix = Get-ChildItem -LiteralPath $outRoot -File -Filter "$PackageName*_x64.msix" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latestMsix) {
        Add-Check "latest-msix" "PASS" $latestMsix.FullName
    }
    else {
        Add-Check "latest-msix" "WARN" "No $PackageName MSIX found under $outRoot"
    }
}
else {
    Add-Check "latest-msix" "WARN" "Missing output directory: $outRoot"
}

if (Test-Path -LiteralPath $ConfigPath) {
    $configText = [IO.File]::ReadAllText($ConfigPath)
    $approvalPolicy = Get-TomlStringValue $configText "approval_policy"
    $sandboxMode = Get-TomlStringValue $configText "sandbox_mode"
    $validApproval = @("untrusted", "on-failure", "on-request", "never")
    $validSandbox = @("read-only", "workspace-write", "danger-full-access")

    if ($approvalPolicy -and ($validApproval -contains $approvalPolicy)) {
        if ($ExpectedApprovalPolicy -and $approvalPolicy -ne $ExpectedApprovalPolicy) {
            Add-Check "config-approval-policy" "WARN" "approval_policy=$approvalPolicy, expected $ExpectedApprovalPolicy"
        }
        else {
            Add-Check "config-approval-policy" "PASS" "approval_policy=$approvalPolicy"
        }
    }
    else {
        Add-Check "config-approval-policy" "FAIL" "Missing or invalid approval_policy"
    }

    if ($sandboxMode -and ($validSandbox -contains $sandboxMode)) {
        if ($ExpectedSandboxMode -and $sandboxMode -ne $ExpectedSandboxMode) {
            Add-Check "config-sandbox-mode" "WARN" "sandbox_mode=$sandboxMode, expected $ExpectedSandboxMode"
        }
        else {
            Add-Check "config-sandbox-mode" "PASS" "sandbox_mode=$sandboxMode"
        }
    }
    else {
        Add-Check "config-sandbox-mode" "FAIL" "Missing or invalid sandbox_mode"
    }

    $legacyWindowsSandbox = [regex]::IsMatch($configText, '(?ms)^\s*\[windows\]\s*(?:(?!^\s*\[).)*?^\s*sandbox\s*=')
    if ($legacyWindowsSandbox) {
        Add-Check "windows-sandbox-compat" "PASS" "[windows] sandbox compatibility value is present"
    }
    else {
        Add-Check "windows-sandbox-compat" "WARN" "No [windows] sandbox compatibility value; current desktop runtime may prompt for sandbox setup"
    }

    if (Test-TomlSectionBoolean $configText "features" "plugins" $true) {
        Add-Check "config-feature-plugins" "PASS" "features.plugins=true"
    }
    else {
        Add-Check "config-feature-plugins" "WARN" "features.plugins is not true or not found"
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
    $records = @()
    foreach ($file in $logFiles) {
        $matches = Select-String -LiteralPath $file.FullName -Pattern "config/batchWrite|configVersionConflict|Unable to save|errorCode=-32600" -ErrorAction SilentlyContinue
        foreach ($match in $matches) {
            $line = $match.Line
            $timestampMatch = [regex]::Match($line, '^(\d{4}-\d{2}-\d{2}T[^ ]+)')
            $timestamp = if ($timestampMatch.Success) { $timestampMatch.Groups[1].Value } else { "" }
            $records += [pscustomobject]@{
                Timestamp = $timestamp
                File = $file.Name
                Line = $line
            }
        }
    }

    $batchRecords = @($records | Where-Object { $_.Line -like "*method=config/batchWrite*" } | Sort-Object Timestamp)
    $conflictRecords = @($records | Where-Object { $_.Line -like "*configVersionConflict*" -or $_.Line -like "*errorCode=-32600*" })
    $latestSuccessfulBatch = $null
    if ($batchRecords.Count -eq 0) {
        Add-Check "latest-batch-write-log" "WARN" "No config/batchWrite entry found in latest $RecentLogFileCount log file(s)"
    }
    else {
        $lastBatch = $batchRecords | Select-Object -Last 1
        if ($lastBatch.Line -like "*errorCode=null*") {
            $latestSuccessfulBatch = $lastBatch
            Add-Check "latest-batch-write-log" "PASS" $lastBatch.Line
        }
        else {
            Add-Check "latest-batch-write-log" "FAIL" $lastBatch.Line
        }
    }

    if ($conflictRecords.Count -eq 0) {
        Add-Check "recent-config-conflicts" "PASS" "No configVersionConflict in latest $RecentLogFileCount log file(s)"
    }
    elseif ($latestSuccessfulBatch -and $latestSuccessfulBatch.Timestamp) {
        $postSuccessConflicts = @($conflictRecords | Where-Object { $_.Timestamp -and $_.Timestamp -gt $latestSuccessfulBatch.Timestamp })
        if ($postSuccessConflicts.Count -eq 0) {
            Add-Check "recent-config-conflicts" "PASS" "$($conflictRecords.Count) historical conflict-related line(s), none after latest successful batchWrite"
        }
        else {
            Add-Check "recent-config-conflicts" "WARN" "$($postSuccessConflicts.Count) conflict-related line(s) after latest successful batchWrite"
        }
    }
    else {
        Add-Check "recent-config-conflicts" "WARN" "$($conflictRecords.Count) older conflict-related line(s) found in latest $RecentLogFileCount log file(s)"
    }
}
else {
    Add-Check "app-log-dir" "WARN" "No app log directory for today: $appLogDir"
}

Write-Host ""
$checks | Format-Table -AutoSize -Wrap

$failures = @($checks | Where-Object { $_.Status -eq "FAIL" })
$warnings = @($checks | Where-Object { $_.Status -eq "WARN" })

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Verification failed: $($failures.Count) failure(s), $($warnings.Count) warning(s)." -ForegroundColor Red
    exit 1
}

if ($warnings.Count -gt 0) {
    Write-Host "Verification completed with $($warnings.Count) warning(s)." -ForegroundColor Yellow
    exit 0
}

Write-Host "Verification passed." -ForegroundColor Green
