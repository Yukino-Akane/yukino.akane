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
$staleAgentSettingsWriteRegex = '[A-Za-z_$][A-Za-z0-9_$]*\(`write-config-value`,\{hostId:[A-Za-z_$][A-Za-z0-9_$]*,keyPath:[A-Za-z_$][A-Za-z0-9_$]*,value:[A-Za-z_$][A-Za-z0-9_$]*,mergeStrategy:`upsert`,filePath:[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?,expectedVersion:[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?\}\)'
$patchedAgentSettingsWriteRegex = '[A-Za-z_$][A-Za-z0-9_$]*\(`batch-write-config-value`,\{hostId:[A-Za-z_$][A-Za-z0-9_$]*,edits:\[\{keyPath:[A-Za-z_$][A-Za-z0-9_$]*,value:[A-Za-z_$][A-Za-z0-9_$]*,mergeStrategy:`upsert`\}\],filePath:[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?,expectedVersion:null,reloadUserConfig:!0\}\)'
$skillsPageEntryGateRegex = '(?<enabled>[A-Za-z_$][A-Za-z0-9_$]*&&)!(?<gate>[A-Za-z_$][A-Za-z0-9_$]*)(?=\)\{let [A-Za-z_$][A-Za-z0-9_$]*;return [A-Za-z_$][A-Za-z0-9_$]*\[\d+\]===Symbol\.for\(`react\.memo_cache_sentinel`\)\?\([A-Za-z_$][A-Za-z0-9_$]*=\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{\}\))'
$skillsPageEntryGatePatchedRegex = '[A-Za-z_$][A-Za-z0-9_$]*&&!0(?=\)\{let [A-Za-z_$][A-Za-z0-9_$]*;return [A-Za-z_$][A-Za-z0-9_$]*\[\d+\]===Symbol\.for\(`react\.memo_cache_sentinel`\)\?\([A-Za-z_$][A-Za-z0-9_$]*=\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{\}\))'
$sidebarPluginGateRegex = '\{authMethod:[A-Za-z_$][A-Za-z0-9_$]*\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),[A-Za-z_$][A-Za-z0-9_$]*=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),[A-Za-z_$][A-Za-z0-9_$]*=[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*\),[A-Za-z_$][A-Za-z0-9_$]*=[A-Za-z_$][A-Za-z0-9_$]*&&[A-Za-z_$][A-Za-z0-9_$]*'
$sidebarPluginGatePatchedRegex = '\{authMethod:[A-Za-z_$][A-Za-z0-9_$]*\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),[A-Za-z_$][A-Za-z0-9_$]*=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),[A-Za-z_$][A-Za-z0-9_$]*=!1,[A-Za-z_$][A-Za-z0-9_$]*=!1'
$sidebarPluginRouteRegex = 'metadata:\{item:`skills`\}\}\),[A-Za-z_$][A-Za-z0-9_$]*\(`/skills`\)\},isActive:[A-Za-z_$][A-Za-z0-9_$]*\.pathname\.startsWith\(`/skills`\),label:[A-Za-z_$][A-Za-z0-9_$]*\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
$sidebarPluginRoutePatchedRegex = 'metadata:\{item:[A-Za-z_$][A-Za-z0-9_$]*\?`plugins`:`skills`\}\}\),[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*\?`/plugins`:`/skills`\)\},isActive:[A-Za-z_$][A-Za-z0-9_$]*\.pathname\.startsWith\([A-Za-z_$][A-Za-z0-9_$]*\?`/plugins`:`/skills`\),label:[A-Za-z_$][A-Za-z0-9_$]*\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
$sidebarPluginRouteStatePatchedRegex = 'metadata:\{item:(?<routeFlag>[A-Za-z_$][A-Za-z0-9_$]*)\?`plugins`:`skills`\}\}\),\k<routeFlag>\?[A-Za-z_$][A-Za-z0-9_$]*\(`/plugins`,\{state:\{initialMode:`browse`,initialTab:`plugins`\}\}\):[A-Za-z_$][A-Za-z0-9_$]*\(`/skills`\)\},isActive:[A-Za-z_$][A-Za-z0-9_$]*\.pathname\.startsWith\(\k<routeFlag>\?`/plugins`:`/skills`\),label:\k<routeFlag>\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
$sidebarPluginHandlerRouteRegex = 'function\s+(?<handler>[A-Za-z_$][A-Za-z0-9_$]*)\([A-Za-z_$][A-Za-z0-9_$]*,[A-Za-z_$][A-Za-z0-9_$]*\)\{[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*,\{eventName:`nav_clicked`,metadata:\{item:`skills`\}\}\),[A-Za-z_$][A-Za-z0-9_$]*\(`/skills`\)\}.*?onClick:\(\)=>\{\k<handler>\([A-Za-z_$][A-Za-z0-9_$]*,[A-Za-z_$][A-Za-z0-9_$]*\)\},isActive:[A-Za-z_$][A-Za-z0-9_$]*\.pathname\.startsWith\(`/skills`\),label:[A-Za-z_$][A-Za-z0-9_$]*\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
$sidebarPluginHandlerRoutePatchedRegex = 'function\s+(?<handler>[A-Za-z_$][A-Za-z0-9_$]*)\([A-Za-z_$][A-Za-z0-9_$]*,[A-Za-z_$][A-Za-z0-9_$]*,(?<routeFlag>[A-Za-z_$][A-Za-z0-9_$]*)\)\{[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*,\{eventName:`nav_clicked`,metadata:\{item:\k<routeFlag>\?`plugins`:`skills`\}\}\),[A-Za-z_$][A-Za-z0-9_$]*\(\k<routeFlag>\?`/plugins`:`/skills`\)\}.*?onClick:\(\)=>\{\k<handler>\([A-Za-z_$][A-Za-z0-9_$]*,[A-Za-z_$][A-Za-z0-9_$]*,\k<routeFlag>\)\},isActive:[A-Za-z_$][A-Za-z0-9_$]*\.pathname\.startsWith\(\k<routeFlag>\?`/plugins`:`/skills`\),label:\k<routeFlag>\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
$sidebarPluginHandlerRouteStatePatchedRegex = 'function\s+(?<handler>[A-Za-z_$][A-Za-z0-9_$]*)\([A-Za-z_$][A-Za-z0-9_$]*,[A-Za-z_$][A-Za-z0-9_$]*,(?<routeFlag>[A-Za-z_$][A-Za-z0-9_$]*)\)\{[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*,\{eventName:`nav_clicked`,metadata:\{item:\k<routeFlag>\?`plugins`:`skills`\}\}\),\k<routeFlag>\?[A-Za-z_$][A-Za-z0-9_$]*\(`/plugins`,\{state:\{initialMode:`browse`,initialTab:`plugins`\}\}\):[A-Za-z_$][A-Za-z0-9_$]*\(`/skills`\)\}.*?onClick:\(\)=>\{\k<handler>\([A-Za-z_$][A-Za-z0-9_$]*,[A-Za-z_$][A-Za-z0-9_$]*,\k<routeFlag>\)\},isActive:[A-Za-z_$][A-Za-z0-9_$]*\.pathname\.startsWith\(\k<routeFlag>\?`/plugins`:`/skills`\),label:\k<routeFlag>\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
$sidebarPluginRouteCurrentRegex = 'onClick:\(\)=>\{[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*,[A-Za-z_$][A-Za-z0-9_$]*\)\},isActive:[A-Za-z_$][A-Za-z0-9_$]*\.pathname\.startsWith\(`/skills`\),label:[A-Za-z_$][A-Za-z0-9_$]*\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
$sidebarPluginRouteCurrentPatchedRegex = 'onClick:\(\)=>\{[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*,[A-Za-z_$][A-Za-z0-9_$]*,(?<routeFlag>[A-Za-z_$][A-Za-z0-9_$]*)\)\},isActive:[A-Za-z_$][A-Za-z0-9_$]*\.pathname\.startsWith\(\k<routeFlag>\?`/plugins`:`/skills`\),label:\k<routeFlag>\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
$pluginDetailRedirectRegex = 'if\([A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*\)\)\{let [A-Za-z_$][A-Za-z0-9_$]*;return [A-Za-z_$][A-Za-z0-9_$]*\[\d+\]===Symbol\.for\(`react\.memo_cache_sentinel`\)\?\([A-Za-z_$][A-Za-z0-9_$]*=\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{replace:!0,to:`/skills`,state:\{initialTab:`skills`,pluginDeepLinkAuthBlocked:!0\}\}\),'
$pluginDetailRedirectPatchedRegex = 'if\(!1&&[A-Za-z_$][A-Za-z0-9_$]*\([A-Za-z_$][A-Za-z0-9_$]*\)\)\{let [A-Za-z_$][A-Za-z0-9_$]*;return [A-Za-z_$][A-Za-z0-9_$]*\[\d+\]===Symbol\.for\(`react\.memo_cache_sentinel`\)\?\([A-Za-z_$][A-Za-z0-9_$]*=\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{replace:!0,to:`/skills`,state:\{initialTab:`skills`,pluginDeepLinkAuthBlocked:!0\}\}\),'
$settingsPageSectionMapRegex = '\{[^{}]*"plugins-settings":[A-Za-z_$][A-Za-z0-9_$]*,"skills-settings":[A-Za-z_$][A-Za-z0-9_$]*[^{}]*\}'

Add-Type -AssemblyName System.Drawing

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

function Get-FirstFileText([object[]]$Files) {
    if ($Files.Count -eq 0) {
        return $null
    }
    return [IO.File]::ReadAllText($Files[0].FullName)
}

function Get-BitmapPixelSha256([System.Drawing.Bitmap]$Bitmap) {
    $stream = New-Object System.IO.MemoryStream
    try {
        $writer = New-Object System.IO.BinaryWriter($stream)
        try {
            $writer.Write([int]$Bitmap.Width)
            $writer.Write([int]$Bitmap.Height)
            for ($y = 0; $y -lt $Bitmap.Height; $y++) {
                for ($x = 0; $x -lt $Bitmap.Width; $x++) {
                    $pixel = $Bitmap.GetPixel($x, $y)
                    $writer.Write([byte]$pixel.A)
                    $writer.Write([byte]$pixel.R)
                    $writer.Write([byte]$pixel.G)
                    $writer.Write([byte]$pixel.B)
                }
            }
            $writer.Flush()
        }
        finally {
            $writer.Dispose()
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [BitConverter]::ToString($sha.ComputeHash($stream.ToArray())).Replace("-", "")
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-AssociatedIconPixelSha256([string]$Path) {
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
    if ($null -eq $icon) {
        return $null
    }
    try {
        $bitmap = $icon.ToBitmap()
        try {
            return Get-BitmapPixelSha256 $bitmap
        }
        finally {
            $bitmap.Dispose()
        }
    }
    finally {
        $icon.Dispose()
    }
}

function Get-PngPixelSha256([string]$Path) {
    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        return Get-BitmapPixelSha256 $bitmap
    }
    finally {
        $bitmap.Dispose()
    }
}

function Expand-AsarToTemp([string]$AsarPath) {
    $extractRoot = Join-Path ([IO.Path]::GetTempPath()) ("yukino-installed-asar-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    npx --yes @electron/asar extract $AsarPath $extractRoot | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract installed app.asar for verification."
    }
    return $extractRoot
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
        elseif (
            ($agentText.Contains($patchedAgentSettingsWrite) -or [regex]::IsMatch($agentText, $patchedAgentSettingsWriteRegex)) -and
            (-not $agentText.Contains($staleAgentSettingsWrite)) -and
            (-not [regex]::IsMatch($agentText, $staleAgentSettingsWriteRegex))
        ) {
            Add-Check "agent-settings-write-patch" "PASS" $agentAssets[0].FullName
        }
        elseif ($agentText.Contains($staleAgentSettingsWrite) -or [regex]::IsMatch($agentText, $staleAgentSettingsWriteRegex)) {
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
        $skillsPageHasDisabledPluginPage = $false
        $skillsPageHasDeepLinkToast = $false
        $skillsPageHasOldEntryGate = $false
        $skillsPageHasPatchedEntryGate = $false
        foreach ($asset in $skillsPageAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            if ($text.Contains("pluginsAuthBlockedToast.title") -and $text.Contains("pluginDeepLinkAuthBlocked")) {
                $skillsPageHasDeepLinkToast = $true
            }
            if ($text.Contains("pluginsAuthBlockedToast.title") -and ($text.Contains("s&&!m") -or [regex]::IsMatch($text, $skillsPageEntryGateRegex))) {
                $skillsPageHasOldGate = $true
                $skillsPageHasOldEntryGate = $true
            }
            if ($text.Contains("pluginsAuthBlockedToast.title") -and ($text.Contains("s&&!0") -or [regex]::IsMatch($text, $skillsPageEntryGatePatchedRegex))) {
                $skillsPageHasPatchedGate = $true
                $skillsPageHasPatchedEntryGate = $true
            }
            if ($text.Contains("pluginsAuthBlockedToast.title") -and $text.Contains("s&&!1")) {
                $skillsPageHasDisabledPluginPage = $true
            }
        }
        $pluginDetailAssets = @(Get-ChildItem -LiteralPath $assetsDir -File -Filter "plugin-detail-page-*.js")
        $pluginDetailHasOldRedirect = $false
        $pluginDetailHasPatchedRedirect = $false
        foreach ($asset in $pluginDetailAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            if (-not $text.Contains("pluginDeepLinkAuthBlocked")) {
                continue
            }
            if ([regex]::IsMatch($text, $pluginDetailRedirectRegex)) {
                $pluginDetailHasOldRedirect = $true
            }
            if ([regex]::IsMatch($text, $pluginDetailRedirectPatchedRegex)) {
                $pluginDetailHasPatchedRedirect = $true
            }
        }

        $sidebarPattern = '(?<prefix>\{authMethod:(?<auth>[A-Za-z_$][A-Za-z0-9_$]*)\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),(?<featureFlag>[A-Za-z_$][A-Za-z0-9_$]*)=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),)(?<gate>[A-Za-z_$][A-Za-z0-9_$]*)=[A-Za-z_$][A-Za-z0-9_$]*\(\k<auth>\),(?<disabledNav>[A-Za-z_$][A-Za-z0-9_$]*)=(?:[A-Za-z_$][A-Za-z0-9_$]*&&)?\k<featureFlag>&&\k<gate>'
        $sidebarPatchedPattern = '(?<prefix>\{authMethod:(?<auth>[A-Za-z_$][A-Za-z0-9_$]*)\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),(?<featureFlag>[A-Za-z_$][A-Za-z0-9_$]*)=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),)(?<gate>[A-Za-z_$][A-Za-z0-9_$]*)=!1,(?<disabledNav>[A-Za-z_$][A-Za-z0-9_$]*)=!1'
        $sidebarAssets = @(
            Get-ChildItem -LiteralPath $assetsDir -File -Filter "index-*.js"
            Get-ChildItem -LiteralPath $assetsDir -File -Filter "app-main-*.js"
        ) | Sort-Object FullName -Unique
        $sidebarHasOldGate = $false
        $sidebarHasPatchedGate = $false
        foreach ($asset in $sidebarAssets) {
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

        if ($gateMatches -eq 0 -and (-not $skillsPageHasOldGate) -and (-not $skillsPageHasDisabledPluginPage) -and $skillsPageHasPatchedGate -and $skillsPageHasPatchedEntryGate -and (-not $pluginDetailHasOldRedirect) -and (-not $sidebarHasOldGate) -and $sidebarHasPatchedGate) {
            Add-Check "plugin-auth-gate" "PASS" "Desktop plugin auth gate is disabled in skills page and sidebar assets"
        }
        elseif ($gradientAssets.Count -gt 0 -and $gateMatches -eq 0 -and (-not $skillsPageHasOldGate) -and (-not $skillsPageHasDisabledPluginPage) -and $skillsPageHasPatchedEntryGate -and (-not $pluginDetailHasOldRedirect) -and ($pluginDetailHasPatchedRedirect -or -not $skillsPageHasDeepLinkToast) -and (-not $sidebarHasOldGate)) {
            Add-Check "plugin-auth-gate" "PASS" "No ChatGPT API-key-only gate remains in gradient, plugin detail, or sidebar assets"
        }
        else {
            Add-Check "plugin-auth-gate" "FAIL" "$gateMatches legacy API-key gate match(es), skills-page old gate=$skillsPageHasOldGate, skills-page old entry gate=$skillsPageHasOldEntryGate, skills-page patched entry gate=$skillsPageHasPatchedEntryGate, skills-page disabled plugin page=$skillsPageHasDisabledPluginPage, plugin detail old redirect=$pluginDetailHasOldRedirect, plugin detail patched redirect=$pluginDetailHasPatchedRedirect, sidebar old gate=$sidebarHasOldGate, sidebar patched gate=$sidebarHasPatchedGate"
        }

        $sidebarHasOldPluginRoute = $false
        $sidebarHasPatchedPluginRoute = $false
        foreach ($asset in $sidebarAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            if (-not $text.Contains("sidebarElectron.skillsAppsRouteNavLink")) {
                continue
            }
            if ([regex]::IsMatch($text, $sidebarPluginRouteRegex) -or [regex]::IsMatch($text, $sidebarPluginHandlerRouteRegex) -or [regex]::IsMatch($text, $sidebarPluginRouteCurrentRegex)) {
                $sidebarHasOldPluginRoute = $true
            }
            if ([regex]::IsMatch($text, $sidebarPluginRouteStatePatchedRegex) -or [regex]::IsMatch($text, $sidebarPluginHandlerRouteStatePatchedRegex)) {
                $sidebarHasPatchedPluginRoute = $true
            }
        }
        if ($sidebarHasPatchedPluginRoute -and (-not $sidebarHasOldPluginRoute)) {
            Add-Check "sidebar-plugin-route" "PASS" "Sidebar Plugins nav opens the Plugins page instead of Skills"
        }
        elseif ($sidebarHasOldPluginRoute) {
            Add-Check "sidebar-plugin-route" "FAIL" "Sidebar Plugins nav still routes to /skills"
        }
        else {
            Add-Check "sidebar-plugin-route" "FAIL" "Expected sidebar Plugins route pattern not found"
        }

        $oldSettingsEntry = 'case`plugins-settings`:return d===`extension`&&u;case`skills-settings`:return d===`extension`&&!u;'
        $newSettingsEntry = 'case`plugins-settings`:return d===`electron`||d===`extension`&&u;case`skills-settings`:return d===`extension`&&!u;'
        $settingsAssets = @(Get-ChildItem -LiteralPath $assetsDir -File -Filter "settings-page-*.js")
        $settingsHasOld = $false
        $settingsHasNew = $false
        $settingsHasSectionMap = $false
        foreach ($asset in $settingsAssets) {
            $text = [IO.File]::ReadAllText($asset.FullName)
            if ($text.Contains($oldSettingsEntry)) {
                $settingsHasOld = $true
            }
            if ($text.Contains($newSettingsEntry)) {
                $settingsHasNew = $true
            }
            if ([regex]::IsMatch($text, $settingsPageSectionMapRegex)) {
                $settingsHasSectionMap = $true
            }
        }
        if ($settingsAssets.Count -eq 0) {
            Add-Check "plugins-settings-entry" "WARN" "No settings-page-*.js assets found"
        }
        elseif (($settingsHasNew -or $settingsHasSectionMap) -and -not $settingsHasOld) {
            Add-Check "plugins-settings-entry" "PASS" "Desktop plugins settings entry is enabled"
        }
        elseif ($settingsHasOld) {
            Add-Check "plugins-settings-entry" "FAIL" "Old extension-only plugins settings entry remains"
        }
        else {
            Add-Check "plugins-settings-entry" "WARN" "Expected settings entry pattern not found; upstream asset may have changed"
        }

        $sidebarBackgroundAsset = Join-Path $assetsDir "yukino-sidebar-background.png"
        $sidebarCssAssets = @(
            Get-ChildItem -LiteralPath $assetsDir -File -Filter "index-*.css"
            Get-ChildItem -LiteralPath $assetsDir -File -Filter "app-main-*.css"
        ) | Sort-Object FullName -Unique
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
            Add-Check "sidebar-background-patch" "FAIL" "Missing sidebar background CSS patch in main webview CSS"
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
    $installedExe = Join-Path $installed.InstallLocation "app\Yukino.exe"
    $installedExeIconReference = Join-Path $installed.InstallLocation "Assets\Square44x44Logo.targetsize-32_altform-unplated.png"
    if (-not (Test-Path -LiteralPath $installedExe)) {
        Add-Check "installed-executable-icon" "FAIL" "Missing installed executable: $installedExe"
    }
    elseif (-not (Test-Path -LiteralPath $installedExeIconReference)) {
        Add-Check "installed-executable-icon" "FAIL" "Missing installed executable icon reference: $installedExeIconReference"
    }
    else {
        $expectedExeIconHash = Get-PngPixelSha256 $installedExeIconReference
        $actualExeIconHash = Get-AssociatedIconPixelSha256 $installedExe
        if ($actualExeIconHash -eq $expectedExeIconHash) {
            Add-Check "installed-executable-icon" "PASS" "Yukino.exe associated icon matches Yukino asset"
        }
        else {
            Add-Check "installed-executable-icon" "FAIL" "Yukino.exe associated icon does not match the generated Yukino icon; rebuild and reinstall the MSIX"
        }
    }

    $installedAsar = Join-Path $installed.InstallLocation "app\resources\app.asar"
    if (Test-Path -LiteralPath $installedAsar) {
        $installedExtractDir = $null
        try {
            $installedExtractDir = Expand-AsarToTemp $installedAsar
            $installedAssetsDir = Join-Path $installedExtractDir "webview\assets"
            $installedAgentAssets = @(Get-ChildItem -LiteralPath $installedAssetsDir -File -Filter "agent-settings-*.js" -ErrorAction SilentlyContinue)
            $installedSkillsPageAssets = @(Get-ChildItem -LiteralPath $installedAssetsDir -File -Filter "skills-page-*.js" -ErrorAction SilentlyContinue)
            $installedPluginDetailAssets = @(Get-ChildItem -LiteralPath $installedAssetsDir -File -Filter "plugin-detail-page-*.js" -ErrorAction SilentlyContinue)
            $installedSidebarAssets = @(
                Get-ChildItem -LiteralPath $installedAssetsDir -File -Filter "index-*.js" -ErrorAction SilentlyContinue
                Get-ChildItem -LiteralPath $installedAssetsDir -File -Filter "app-main-*.js" -ErrorAction SilentlyContinue
            ) | Sort-Object FullName -Unique
            $installedSidebarCssAssets = @(
                Get-ChildItem -LiteralPath $installedAssetsDir -File -Filter "index-*.css" -ErrorAction SilentlyContinue
                Get-ChildItem -LiteralPath $installedAssetsDir -File -Filter "app-main-*.css" -ErrorAction SilentlyContinue
            ) | Sort-Object FullName -Unique
            $installedSidebarBackgroundAsset = Join-Path $installedAssetsDir "yukino-sidebar-background.png"

            $installedHasPatchedWrite = $false
            $installedHasStaleWrite = $false
            foreach ($asset in $installedAgentAssets) {
                $text = [IO.File]::ReadAllText($asset.FullName)
                if ($text.Contains($patchedAgentSettingsWrite) -or [regex]::IsMatch($text, $patchedAgentSettingsWriteRegex)) {
                    $installedHasPatchedWrite = $true
                }
                if ($text.Contains($staleAgentSettingsWrite) -or [regex]::IsMatch($text, $staleAgentSettingsWriteRegex)) {
                    $installedHasStaleWrite = $true
                }
            }
            if ($installedHasPatchedWrite -and -not $installedHasStaleWrite) {
                Add-Check "installed-agent-settings-patch" "PASS" $installedAsar
            }
            elseif ($installedHasStaleWrite) {
                Add-Check "installed-agent-settings-patch" "FAIL" "Installed app.asar still contains stale Agent Settings write route"
            }
            else {
                Add-Check "installed-agent-settings-patch" "FAIL" "Installed app.asar does not contain expected Agent Settings patch"
            }

            $installedHasSkillsPageAuthToast = $false
            $installedHasPatchedSkillsPageGate = $false
            $installedHasOldSkillsPageEntryGate = $false
            $installedHasDisabledSkillsPageGate = $false
            $installedHasPluginDetailDeepLinkGate = $false
            $installedHasPluginDetailRedirect = $false
            $installedHasPatchedPluginDetailRedirect = $false
            foreach ($asset in $installedSkillsPageAssets) {
                $text = [IO.File]::ReadAllText($asset.FullName)
                if ($text.Contains("pluginsAuthBlockedToast.title")) {
                    $installedHasSkillsPageAuthToast = $true
                }
                if ($text.Contains("pluginsAuthBlockedToast.title") -and ($text.Contains("s&&!0") -or [regex]::IsMatch($text, $skillsPageEntryGatePatchedRegex))) {
                    $installedHasPatchedSkillsPageGate = $true
                }
                if ($text.Contains("pluginsAuthBlockedToast.title") -and ($text.Contains("s&&!m") -or [regex]::IsMatch($text, $skillsPageEntryGateRegex))) {
                    $installedHasOldSkillsPageEntryGate = $true
                }
                if ($text.Contains("pluginsAuthBlockedToast.title") -and $text.Contains("s&&!1")) {
                    $installedHasDisabledSkillsPageGate = $true
                }
                if ($text.Contains("pluginDeepLinkAuthBlocked")) {
                    $installedHasPluginDetailDeepLinkGate = $true
                }
            }
            foreach ($asset in $installedPluginDetailAssets) {
                $text = [IO.File]::ReadAllText($asset.FullName)
                if (-not $text.Contains("pluginDeepLinkAuthBlocked")) {
                    continue
                }
                if ([regex]::IsMatch($text, $pluginDetailRedirectRegex)) {
                    $installedHasPluginDetailRedirect = $true
                }
                if ([regex]::IsMatch($text, $pluginDetailRedirectPatchedRegex)) {
                    $installedHasPatchedPluginDetailRedirect = $true
                }
                $installedHasPluginDetailDeepLinkGate = $true
            }

            $installedHasSidebarPluginGate = $false
            $installedHasPatchedSidebarPluginGate = $false
            foreach ($asset in $installedSidebarAssets) {
                $text = [IO.File]::ReadAllText($asset.FullName)
                if (-not $text.Contains("pluginsDisabledTooltip")) {
                    continue
                }
                if ([regex]::IsMatch($text, $sidebarPluginGateRegex)) {
                    $installedHasSidebarPluginGate = $true
                }
                if ([regex]::IsMatch($text, $sidebarPluginGatePatchedRegex)) {
                    $installedHasPatchedSidebarPluginGate = $true
                }
            }
            if ($installedHasSkillsPageAuthToast -and $installedHasDisabledSkillsPageGate) {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed skills-page bundle disables the Plugins page entry with s&&!1; rebuild and reinstall the MSIX"
            }
            elseif ($installedHasOldSkillsPageEntryGate) {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed skills-page bundle still gates the Plugins marketplace entry for API-key users; rebuild and reinstall the MSIX"
            }
            elseif ($installedHasPluginDetailRedirect) {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed plugin detail bundle still redirects API-key users back to Skills; rebuild and reinstall the MSIX"
            }
            elseif ($installedHasSkillsPageAuthToast -and (-not $installedHasPatchedSkillsPageGate) -and (-not $installedHasPatchedPluginDetailRedirect)) {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed skills-page bundle does not contain the expected Plugins page entry patch"
            }
            elseif ($installedHasPluginDetailDeepLinkGate -and -not $installedHasPatchedPluginDetailRedirect) {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed plugin detail bundle does not contain the expected patched deep-link redirect gate"
            }
            elseif ($installedHasPatchedSidebarPluginGate -and -not $installedHasSidebarPluginGate) {
                Add-Check "installed-plugin-auth-gate" "PASS" $installedAsar
            }
            elseif ($installedHasSidebarPluginGate) {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed app.asar still contains the disabled Plugins sidebar gate; install the latest MSIX to apply the fix"
            }
            else {
                Add-Check "installed-plugin-auth-gate" "FAIL" "Installed app.asar does not contain the expected patched Plugins sidebar gate"
            }

            $installedHasSidebarPluginRoute = $false
            $installedHasPatchedSidebarPluginRoute = $false
            foreach ($asset in $installedSidebarAssets) {
                $text = [IO.File]::ReadAllText($asset.FullName)
                if ([regex]::IsMatch($text, $sidebarPluginRouteRegex) -or [regex]::IsMatch($text, $sidebarPluginHandlerRouteRegex) -or [regex]::IsMatch($text, $sidebarPluginRouteCurrentRegex)) {
                    $installedHasSidebarPluginRoute = $true
                }
                if ([regex]::IsMatch($text, $sidebarPluginRouteStatePatchedRegex) -or [regex]::IsMatch($text, $sidebarPluginHandlerRouteStatePatchedRegex)) {
                    $installedHasPatchedSidebarPluginRoute = $true
                }
            }
            if ($installedHasPatchedSidebarPluginRoute -and -not $installedHasSidebarPluginRoute) {
                Add-Check "installed-sidebar-plugin-route" "PASS" $installedAsar
            }
            elseif ($installedHasSidebarPluginRoute) {
                Add-Check "installed-sidebar-plugin-route" "FAIL" "Installed app.asar still routes the sidebar Plugins nav to /skills; install the latest MSIX to apply the fix"
            }
            else {
                Add-Check "installed-sidebar-plugin-route" "FAIL" "Installed app.asar does not contain the expected patched sidebar Plugins route"
            }

            $installedHasSidebarBackground = Test-Path -LiteralPath $installedSidebarBackgroundAsset
            $installedHasAspectSafeSidebarBackground = $false
            $installedHasCenteredPortraitSidebarBackground = $false
            $installedHasDistortedSidebarBackground = $false
            $installedHasFullWindowCoverSidebarBackground = $false
            foreach ($asset in $installedSidebarCssAssets) {
                $text = [IO.File]::ReadAllText($asset.FullName)
                if ($text.Contains("background-size: var(--yukino-sidebar-background-width) 100%, auto 100vh;")) {
                    $installedHasAspectSafeSidebarBackground = $true
                }
                if ($text.Contains("background-position: left top, calc(var(--yukino-sidebar-background-half-width) - var(--yukino-sidebar-portrait-half-width)) center;")) {
                    $installedHasCenteredPortraitSidebarBackground = $true
                }
                if ($text.Contains("background-size: var(--yukino-sidebar-background-width) 100%, var(--yukino-sidebar-background-width) 100%;")) {
                    $installedHasDistortedSidebarBackground = $true
                }
                if ($text.Contains("background-size: var(--yukino-sidebar-background-width) 100%, cover;")) {
                    $installedHasFullWindowCoverSidebarBackground = $true
                }
            }
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
        catch {
            Add-Check "installed-agent-settings-patch" "FAIL" "Unable to inspect installed app.asar assets: $($_.Exception.Message)"
            Add-Check "installed-plugin-auth-gate" "FAIL" "Unable to inspect installed app.asar assets: $($_.Exception.Message)"
            Add-Check "installed-sidebar-plugin-route" "FAIL" "Unable to inspect installed app.asar assets: $($_.Exception.Message)"
            Add-Check "installed-sidebar-background-patch" "FAIL" "Unable to inspect installed app.asar assets: $($_.Exception.Message)"
        }
        finally {
            if ($installedExtractDir -and (Test-Path -LiteralPath $installedExtractDir)) {
                Remove-Item -LiteralPath $installedExtractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Add-Check "installed-agent-settings-patch" "FAIL" "Missing installed app.asar: $installedAsar"
        Add-Check "installed-plugin-auth-gate" "FAIL" "Missing installed app.asar: $installedAsar"
        Add-Check "installed-sidebar-plugin-route" "FAIL" "Missing installed app.asar: $installedAsar"
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
    $configErrorRecords = @()
    foreach ($file in $logFiles) {
        $matches = Select-String -LiteralPath $file.FullName -Pattern "config/batchWrite|configVersionConflict|Unable to save|errorCode=-32600|method=config/" -ErrorAction SilentlyContinue
        foreach ($match in $matches) {
            $line = $match.Line
            $timestampMatch = [regex]::Match($line, '^(\d{4}-\d{2}-\d{2}T[^ ]+)')
            $timestamp = if ($timestampMatch.Success) { $timestampMatch.Groups[1].Value } else { "" }
            $record = [pscustomobject]@{
                Timestamp = $timestamp
                File = $file.Name
                Line = $line
                Method = Get-LogField $line "method"
                ErrorCode = Get-LogField $line "errorCode"
            }
            $records += $record
            if ($record.Method -like "config/*" -and $record.ErrorCode -and $record.ErrorCode -ne "null") {
                $configErrorRecords += $record
            }
        }
    }

    $batchRecords = @($records | Where-Object { $_.Line -like "*method=config/batchWrite*" } | Sort-Object Timestamp)
    $conflictRecords = @($records | Where-Object { $_.Line -like "*configVersionConflict*" -or $_.Line -like "*Unable to save*" })
    $conflictRecords += $configErrorRecords
    $conflictRecords = @($conflictRecords | Sort-Object Timestamp, File, Line -Unique)
    $latestSuccessfulBatch = $null
    if ($batchRecords.Count -eq 0) {
        Add-Check "latest-batch-write-log" "PASS" "No config batchWrite evidence in latest $RecentLogFileCount log file(s); run a manual settings write when validating that patch."
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
$controlHomeScript = Join-Path $ProjectRoot "scripts\yukino-control-home.ps1"
$verificationStatus = if ($failures.Count -gt 0) { "failed" } else { "passed" }
if (Test-Path -LiteralPath $controlHomeScript) {
    . $controlHomeScript
    Write-YukinoVerificationRecord `
        -Status $verificationStatus `
        -ProjectRoot $ProjectRoot `
        -Checks @($checks | ForEach-Object { "$($_.Name):$($_.Status)" })
}

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
