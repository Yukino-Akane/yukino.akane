param(
    [string]$OutputRoot = $PSScriptRoot,
    [string]$PackageName = "yukino.akane",
    [string]$DisplayName = "Yukino",
    [string]$Publisher = "CN=Yukino",
    [string]$IconSource = (Join-Path $PSScriptRoot "assets\yukino-icon-source.jpg"),
    [string]$SidebarBackgroundSource = (Join-Path $PSScriptRoot "assets\yukino-sidebar-background.png"),
    [switch]$Install,
    [switch]$Clean,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "== $Message ==" -ForegroundColor Cyan
}

function Invoke-OptionalScript([string]$Path, [string[]]$Arguments) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Path failed with exit code $LASTEXITCODE."
    }
}

function Resolve-SdkTool([string]$ToolName) {
    $tool = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter $ToolName -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\x64\\" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $tool) {
        throw "Cannot find $ToolName under Windows Kits. Install Windows SDK or add the tool to PATH."
    }
    return $tool.FullName
}

function Remove-PathSafe([string]$Path, [string]$AllowedRoot) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $allowed = (Resolve-Path -LiteralPath $AllowedRoot).Path
    if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove outside allowed root. Path=$resolved Root=$allowed"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Stop-YukinoProcessTree([int]$RootProcessId) {
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $childrenByParent = @{}
    foreach ($process in $processes) {
        if (-not $childrenByParent.ContainsKey($process.ParentProcessId)) {
            $childrenByParent[$process.ParentProcessId] = New-Object System.Collections.Generic.List[object]
        }
        $childrenByParent[$process.ParentProcessId].Add($process)
    }

    $ids = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue($RootProcessId)
    while ($queue.Count -gt 0) {
        $id = $queue.Dequeue()
        $ids.Add($id)
        if ($childrenByParent.ContainsKey($id)) {
            foreach ($child in $childrenByParent[$id]) {
                $queue.Enqueue([int]$child.ProcessId)
            }
        }
    }

    foreach ($id in @($ids | Select-Object -Unique | Sort-Object -Descending)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

function Test-InstalledYukinoRunning([string]$PackageName, [string]$DisplayName) {
    $installed = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $installed) {
        return $false
    }

    $installLocation = $installed.InstallLocation
    if (-not $installLocation) {
        return $false
    }

    $expectedExe = Join-Path $installLocation "app\$DisplayName.exe"
    $expectedCodex = Join-Path $installLocation "app\resources\codex.exe"
    $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and (
                $_.ExecutablePath.Equals($expectedExe, [StringComparison]::OrdinalIgnoreCase) -or
                $_.ExecutablePath.Equals($expectedCodex, [StringComparison]::OrdinalIgnoreCase)
            )
        } |
        Select-Object -First 1

    return $null -ne $running
}

function Replace-Text([string]$Path, [string]$Old, [string]$New) {
    $text = [IO.File]::ReadAllText($Path)
    $count = [regex]::Matches($text, [regex]::Escape($Old)).Count
    if ($count -gt 0) {
        [IO.File]::WriteAllText($Path, $text.Replace($Old, $New), [Text.UTF8Encoding]::new($false))
    }
    return $count
}

function Patch-TextFileBranding([string]$Path, [string]$PackageName, [string]$DisplayName) {
    $text = [IO.File]::ReadAllText($Path)
    $original = $text

    # Replace user-visible app branding without renaming translation keys such as commentWithCodex.
    $text = [regex]::Replace($text, "(?<![A-Za-z0-9_])Codex[A-Za-z]*", $DisplayName)
    $text = [regex]::Replace($text, "(?<![A-Za-z0-9_])\.codex(?![A-Za-z0-9_-])", ".yukino")
    $text = $text.Replace("codex://", "yukino://")
    $text = $text.Replace("OpenAI.Codex", $PackageName)
    $text = $text.Replace("com.openai.codex", $PackageName)
    $text = $text.Replace('$HOME/.codex', '$HOME/.yukino')
    $text = $text.Replace('`/.codex`', '`/.yukino`')
    $text = $text.Replace('`.codex`', '`.yukino`')
    $text = $text.Replace('.codex/environments', '.yukino/environments')
    $text = $text.Replace('your .codex folder', 'your .yukino folder')
    $text = $text.Replace('your `.codex` folder', 'your `.yukino` folder')
    $text = $text.Replace('codex-desktop-', 'yukino-desktop-')

    if ($text -ne $original) {
        [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
        return $true
    }
    return $false
}

function Patch-TextTreeBranding([string]$Root, [string]$PackageName, [string]$DisplayName) {
    if (-not (Test-Path -LiteralPath $Root)) {
        return 0
    }
    $extensions = @(".css", ".html", ".json", ".js", ".md", ".toml", ".txt", ".yaml", ".yml")
    $patched = 0
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse) {
        if ($file.FullName -like "*\node_modules\*") {
            continue
        }
        if ($extensions -notcontains $file.Extension.ToLowerInvariant()) {
            continue
        }
        if (Patch-TextFileBranding -Path $file.FullName -PackageName $PackageName -DisplayName $DisplayName) {
            $patched += 1
        }
    }
    return $patched
}

function Patch-UpdaterIsolation([string]$BootstrapPath) {
    $text = [IO.File]::ReadAllText($BootstrapPath)
    $marker = "Yukino updater disabled"
    if ($text.Contains($marker)) {
        return
    }

    $needle = 'let{desktopSentry:r,sparkleManager:i}=e;'
    $patch = 'let{desktopSentry:r,sparkleManager:i}=e;(()=>{let e=`Yukino updater disabled`;if(i&&!i.__yukinoUpdaterDisabled){i.__yukinoUpdaterDisabled=!0;i.updater=null;i.isUpdateReady=!1;i.updateLifecycleState=`idle`;i.installProgressPercent=null;i.lastUnavailableReason=e;i.initialize=async()=>{i.updater=null;i.isUpdateReady=!1;i.updateLifecycleState=`idle`;i.installProgressPercent=null;i.lastUnavailableReason=e};i.hasUpdater=()=>!1;i.getUnavailableReason=()=>e;i.getIsUpdateReady=()=>!1;i.getInstallProgressPercent=()=>null;i.getUpdateLifecycleState=()=>`idle`;i.checkForUpdates=async()=>{};i.installUpdatesIfAvailable=async()=>{};}})();'
    if (-not $text.Contains($needle)) {
        throw "Cannot find sparkleManager bootstrap hook in $BootstrapPath"
    }

    $text = $text.Replace($needle, $patch)
    [IO.File]::WriteAllText($BootstrapPath, $text, [Text.UTF8Encoding]::new($false))
}

function Patch-Manifest([string]$ManifestPath, [string]$PackageName, [string]$DisplayName, [string]$Publisher, [string]$Version) {
    [xml]$xml = Get-Content -LiteralPath $ManifestPath
    $xml.Package.Identity.Name = $PackageName
    $xml.Package.Identity.Publisher = $Publisher
    $xml.Package.Identity.Version = $Version
    $xml.Package.Properties.DisplayName = $DisplayName
    $xml.Package.Properties.PublisherDisplayName = $DisplayName
    $app = $xml.Package.Applications.Application
    $app.Executable = "app\$DisplayName.exe"
    $app.VisualElements.DisplayName = $DisplayName
    $app.VisualElements.Description = $DisplayName
    $protocol = $xml.GetElementsByTagName("uap:Protocol") | Select-Object -First 1
    if ($protocol) {
        $protocol.Name = "yukino"
    }
    $xml.Save($ManifestPath)
}

function Update-AppxIconAssets([string]$PackageRoot, [string]$SourceImage) {
    if (-not (Test-Path -LiteralPath $SourceImage)) {
        throw "Icon source image not found: $SourceImage"
    }

    $generator = Join-Path $PSScriptRoot "scripts\New-YukinoIconAssets.ps1"
    if (-not (Test-Path -LiteralPath $generator)) {
        throw "Icon asset generator not found: $generator"
    }

    $assetsDir = Join-Path $PackageRoot "Assets"
    if (-not (Test-Path -LiteralPath $assetsDir)) {
        throw "Package Assets directory not found: $assetsDir"
    }

    $electronIcon = Join-Path $PackageRoot "app\resources\icon.ico"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $generator -SourceImage $SourceImage -OutputDir $assetsDir -IconPath $electronIcon
    if ($LASTEXITCODE -ne 0) {
        throw "Icon asset generator failed with exit code $LASTEXITCODE."
    }
}

function Patch-UnsupportedExperimentalFeatureSync([string]$AssetsDir) {
    if (-not (Test-Path -LiteralPath $AssetsDir)) {
        return
    }

    $pattern = 'var\s+([A-Za-z_$][A-Za-z0-9_$]*)=\[`apps`,`memories`,`plugins`,`tool_call_mcp_elicitation`,`tool_search`,`tool_suggest`,[A-Za-z_$][A-Za-z0-9_$]*\];function\s+([A-Za-z_$][A-Za-z0-9_$]*)\(\)\{'
    $patched = 0
    foreach ($asset in Get-ChildItem -LiteralPath $AssetsDir -File -Filter "index-*.js") {
        $text = [IO.File]::ReadAllText($asset.FullName)
        if ($text -notmatch $pattern) {
            continue
        }

        $text = [regex]::Replace(
            $text,
            $pattern,
            'var $1=[`apps`,`memories`,`plugins`,`tool_call_mcp_elicitation`,`tool_search`,`tool_suggest`];function $2(){',
            1
        )
        [IO.File]::WriteAllText($asset.FullName, $text, [Text.UTF8Encoding]::new($false))
        $patched += 1
    }

    if ($patched -gt 0) {
        Write-Host "Yukino unsupported experimental features filtered in $patched webview entry file(s)"
    }
}

function Patch-PluginAuthGate([string]$AssetsDir) {
    if (-not (Test-Path -LiteralPath $AssetsDir)) {
        return
    }

    $legacyPattern = 'function\s+([A-Za-z_$][A-Za-z0-9_$]*)\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{return\s+\2===`apikey`\}'
    $patched = 0
    foreach ($asset in Get-ChildItem -LiteralPath $AssetsDir -File -Filter "gradient-*.js") {
        $text = [IO.File]::ReadAllText($asset.FullName)
        if ($text -notmatch $legacyPattern) {
            continue
        }

        $text = [regex]::Replace($text, $legacyPattern, 'function $1($2){return !1}', 1)
        [IO.File]::WriteAllText($asset.FullName, $text, [Text.UTF8Encoding]::new($false))
        $patched += 1
    }

    foreach ($asset in Get-ChildItem -LiteralPath $AssetsDir -File -Filter "skills-page-*.js") {
        $text = [IO.File]::ReadAllText($asset.FullName)
        if (-not $text.Contains("pluginsAuthBlockedToast.title") -or -not $text.Contains("s&&!m")) {
            continue
        }

        [IO.File]::WriteAllText($asset.FullName, $text.Replace("s&&!m", "s&&!0"), [Text.UTF8Encoding]::new($false))
        $patched += 1
    }

    $sidebarPattern = '(?<prefix>\{authMethod:(?<auth>[A-Za-z_$][A-Za-z0-9_$]*)\}=[A-Za-z_$][A-Za-z0-9_$]*\(\),(?<featureFlag>[A-Za-z_$][A-Za-z0-9_$]*)=[A-Za-z_$][A-Za-z0-9_$]*\(`533078438`\),)(?<gate>[A-Za-z_$][A-Za-z0-9_$]*)=[A-Za-z_$][A-Za-z0-9_$]*\(\k<auth>\),(?<disabledNav>[A-Za-z_$][A-Za-z0-9_$]*)=(?:[A-Za-z_$][A-Za-z0-9_$]*&&)?\k<featureFlag>&&\k<gate>'
    $sidebarAssets = @(
        Get-ChildItem -LiteralPath $AssetsDir -File -Filter "index-*.js"
        Get-ChildItem -LiteralPath $AssetsDir -File -Filter "app-main-*.js"
    ) | Sort-Object FullName -Unique
    foreach ($asset in $sidebarAssets) {
        $text = [IO.File]::ReadAllText($asset.FullName)
        if (-not $text.Contains("pluginsDisabledTooltip") -or -not $text.Contains("authMethod:") -or -not $text.Contains("533078438")) {
            continue
        }

        $sidebarRegex = [regex]::new($sidebarPattern)
        $newText = $sidebarRegex.Replace($text, {
            param($match)
            $prefix = $match.Groups["prefix"].Value
            $gate = $match.Groups["gate"].Value
            $disabledNav = $match.Groups["disabledNav"].Value
            "${prefix}${gate}=!1,${disabledNav}=!1"
        }, 1)
        if ($newText -eq $text) {
            continue
        }

        [IO.File]::WriteAllText($asset.FullName, $newText, [Text.UTF8Encoding]::new($false))
        $patched += 1
    }

    if ($patched -eq 0) {
        throw "Cannot find plugin API-key auth gate in webview assets."
    }

    Write-Host "Disabled ChatGPT-only plugin auth gate in $patched webview asset file(s)"
}

function Patch-PluginSidebarRoute([string]$AssetsDir) {
    if (-not (Test-Path -LiteralPath $AssetsDir)) {
        return
    }

    $inlineRoutePattern = 'metadata:\{item:`skills`\}\}\),(?<navigate>[A-Za-z_$][A-Za-z0-9_$]*)\(`/skills`\)\},isActive:(?<location>[A-Za-z_$][A-Za-z0-9_$]*)\.pathname\.startsWith\(`/skills`\),label:(?<routeFlag>[A-Za-z_$][A-Za-z0-9_$]*)\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
    $handlerRoutePattern = 'onClick:\(\)=>\{(?<handler>[A-Za-z_$][A-Za-z0-9_$]*)\((?<scope>[A-Za-z_$][A-Za-z0-9_$]*),(?<navigate>[A-Za-z_$][A-Za-z0-9_$]*)\)\},isActive:(?<location>[A-Za-z_$][A-Za-z0-9_$]*)\.pathname\.startsWith\(`/skills`\),label:(?<routeFlag>[A-Za-z_$][A-Za-z0-9_$]*)\?\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsxs\)\(`span`,\{className:`inline-flex items-center gap-1`,children:\[\(0,[A-Za-z_$][A-Za-z0-9_$]*\.jsx\)\([A-Za-z_$][A-Za-z0-9_$]*,\{id:`sidebarElectron\.skillsAppsRouteNavLink`,defaultMessage:`Plugins`'
    $patched = 0
    $routeAssets = @(
        Get-ChildItem -LiteralPath $AssetsDir -File -Filter "index-*.js"
        Get-ChildItem -LiteralPath $AssetsDir -File -Filter "app-main-*.js"
    ) | Sort-Object FullName -Unique
    foreach ($asset in $routeAssets) {
        $text = [IO.File]::ReadAllText($asset.FullName)
        if (-not $text.Contains("sidebarElectron.skillsAppsRouteNavLink")) {
            continue
        }

        $newText = $text
        $inlineMatch = [regex]::Match($newText, $inlineRoutePattern)
        if ($inlineMatch.Success) {
            $navigate = $inlineMatch.Groups["navigate"].Value
            $location = $inlineMatch.Groups["location"].Value
            $routeFlag = $inlineMatch.Groups["routeFlag"].Value
            $old = 'metadata:{item:`skills`}}),' + $navigate + '(`/skills`)},isActive:' + $location + '.pathname.startsWith(`/skills`),label:' + $routeFlag + '?'
            $new = 'metadata:{item:' + $routeFlag + '?`plugins`:`skills`}}),' + $navigate + '(' + $routeFlag + '?`/plugins`:`/skills`)},isActive:' + $location + '.pathname.startsWith(' + $routeFlag + '?`/plugins`:`/skills`),label:' + $routeFlag + '?'
            $newText = $newText.Replace($inlineMatch.Value, $inlineMatch.Value.Replace($old, $new))
        }

        $handlerRouteMatch = [regex]::Match($newText, $handlerRoutePattern)
        if ($handlerRouteMatch.Success) {
            $match = $handlerRouteMatch
            $handler = $match.Groups["handler"].Value
            $scope = $match.Groups["scope"].Value
            $navigate = $match.Groups["navigate"].Value
            $location = $match.Groups["location"].Value
            $routeFlag = $match.Groups["routeFlag"].Value
            $handlerDefinitionPattern = 'function\s+' + [regex]::Escape($handler) + '\((?<handlerScope>[A-Za-z_$][A-Za-z0-9_$]*),(?<handlerNavigate>[A-Za-z_$][A-Za-z0-9_$]*)\)\{(?<logger>[A-Za-z_$][A-Za-z0-9_$]*)\(\k<handlerScope>,\{eventName:`nav_clicked`,metadata:\{item:`skills`\}\}\),\k<handlerNavigate>\(`/skills`\)\}'
            $handlerMatch = [regex]::Match($newText, $handlerDefinitionPattern)
            if (-not $handlerMatch.Success) {
                throw "Cannot find sidebar Plugins route handler $handler in $($asset.Name)."
            }

            $handlerScope = $handlerMatch.Groups["handlerScope"].Value
            $handlerNavigate = $handlerMatch.Groups["handlerNavigate"].Value
            $logger = $handlerMatch.Groups["logger"].Value
            $newHandler = 'function ' + $handler + '(' + $handlerScope + ',' + $handlerNavigate + ',' + $routeFlag + '){' + $logger + '(' + $handlerScope + ',{eventName:`nav_clicked`,metadata:{item:' + $routeFlag + '?`plugins`:`skills`}}),' + $handlerNavigate + '(' + $routeFlag + '?`/plugins`:`/skills`)}'
            $newText = [regex]::new($handlerDefinitionPattern).Replace($newText, {
                param($handlerDefinitionMatch)
                $newHandler
            }, 1)

            $old = 'onClick:()=>{' + $handler + '(' + $scope + ',' + $navigate + ')},isActive:' + $location + '.pathname.startsWith(`/skills`),label:' + $routeFlag + '?'
            $new = 'onClick:()=>{' + $handler + '(' + $scope + ',' + $navigate + ',' + $routeFlag + ')},isActive:' + $location + '.pathname.startsWith(' + $routeFlag + '?`/plugins`:`/skills`),label:' + $routeFlag + '?'
            $newText = $newText.Replace($match.Value, $match.Value.Replace($old, $new))
        }

        if ($newText -eq $text) {
            continue
        }

        [IO.File]::WriteAllText($asset.FullName, $newText, [Text.UTF8Encoding]::new($false))
        $patched += 1
    }

    if ($patched -eq 0) {
        throw "Cannot find sidebar Plugins route in webview assets."
    }

    Write-Host "Patched sidebar Plugins route in $patched webview asset file(s)"
}

function Patch-AgentSettingsConfigWrites([string]$AssetsDir) {
    if (-not (Test-Path -LiteralPath $AssetsDir)) {
        return
    }

    $legacyOld = 'T(`write-config-value`,{hostId:e,keyPath:n,value:r,mergeStrategy:`upsert`,filePath:z.filePath,expectedVersion:z.expectedVersion})'
    $legacyNew = 'T(`batch-write-config-value`,{hostId:e,edits:[{keyPath:n,value:r,mergeStrategy:`upsert`}],filePath:z.filePath,expectedVersion:null,reloadUserConfig:!0})'
    $configWritePattern = '(?<caller>[A-Za-z_$][A-Za-z0-9_$]*)\(`write-config-value`,\{hostId:(?<hostId>[A-Za-z_$][A-Za-z0-9_$]*),keyPath:(?<keyPath>[A-Za-z_$][A-Za-z0-9_$]*),value:(?<value>[A-Za-z_$][A-Za-z0-9_$]*),mergeStrategy:`upsert`,filePath:(?<filePath>[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?),expectedVersion:(?<expectedVersion>[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?)\}\)'
    $patched = 0
    foreach ($asset in Get-ChildItem -LiteralPath $AssetsDir -File -Filter "agent-settings-*.js") {
        $text = [IO.File]::ReadAllText($asset.FullName)
        if (-not $text.Contains("write-config-value")) {
            continue
        }

        if ($text.Contains($legacyOld)) {
            $newText = $text.Replace($legacyOld, $legacyNew)
        }
        else {
            $configWriteRegex = [regex]::new($configWritePattern)
            $newText = $configWriteRegex.Replace($text, {
                param($match)
                $caller = $match.Groups["caller"].Value
                $hostId = $match.Groups["hostId"].Value
                $keyPath = $match.Groups["keyPath"].Value
                $value = $match.Groups["value"].Value
                $filePath = $match.Groups["filePath"].Value
                $caller + '(`batch-write-config-value`,{hostId:' + $hostId + ',edits:[{keyPath:' + $keyPath + ',value:' + $value + ',mergeStrategy:`upsert`}],filePath:' + $filePath + ',expectedVersion:null,reloadUserConfig:!0})'
            }, 1)
        }
        if ($newText -eq $text) {
            continue
        }

        [IO.File]::WriteAllText($asset.FullName, $newText, [Text.UTF8Encoding]::new($false))
        $patched += 1
    }

    if ($patched -eq 0) {
        throw "Cannot find Agent Settings config write call in webview assets."
    }

    Write-Host "Patched Agent Settings config writes in $patched webview asset file(s)"
}

function Patch-WebviewSidebarBackground([string]$ExtractDir, [string]$SourceImage) {
    if (-not (Test-Path -LiteralPath $SourceImage)) {
        throw "Sidebar background source image not found: $SourceImage"
    }

    $assetsDir = Join-Path $ExtractDir "webview\assets"
    if (-not (Test-Path -LiteralPath $assetsDir)) {
        throw "Webview assets directory not found: $assetsDir"
    }

    $assetName = "yukino-sidebar-background.png"
    Copy-Item -LiteralPath $SourceImage -Destination (Join-Path $assetsDir $assetName) -Force

    $cssFile = @(
        Get-ChildItem -LiteralPath $assetsDir -File -Filter "index-*.css"
        Get-ChildItem -LiteralPath $assetsDir -File -Filter "app-main-*.css"
    ) |
        Sort-Object FullName -Unique |
        Where-Object {
            $css = [IO.File]::ReadAllText($_.FullName)
            $css.Contains(".main-surface") -and $css.Contains("--color-token-side-bar-background")
        } |
        Select-Object -First 1
    if (-not $cssFile) {
        throw "Cannot find main webview CSS asset for Yukino sidebar background patch."
    }

    $markerStart = "/* Yukino sidebar background patch */"
    $markerEnd = "/* End Yukino sidebar background patch */"
    $patch = @'
/* Yukino sidebar background patch */
:root {
  --yukino-sidebar-background-image: url("./yukino-sidebar-background.png");
  --yukino-sidebar-background-width: clamp(280px, 27vw, 430px);
  --yukino-sidebar-background-half-width: calc(var(--yukino-sidebar-background-width) / 2);
  --yukino-sidebar-portrait-half-width: 42.105263vh;
}

[data-codex-window-type=electron] body {
  background-image:
    linear-gradient(90deg,
      color-mix(in srgb, var(--color-token-side-bar-background) 42%, transparent) 0%,
      color-mix(in srgb, var(--color-token-side-bar-background) 60%, transparent) 72%,
      transparent 100%),
    var(--yukino-sidebar-background-image);
  background-position: left top, calc(var(--yukino-sidebar-background-half-width) - var(--yukino-sidebar-portrait-half-width)) center;
  background-repeat: no-repeat, no-repeat;
  background-size: var(--yukino-sidebar-background-width) 100%, auto 100vh;
}

[data-codex-window-type=electron] .bg-token-side-bar-background,
[data-codex-window-type=electron] .bg-token-side-bar-background\/90 {
  background-color: color-mix(in srgb, var(--color-token-side-bar-background) 54%, transparent);
}

@media (prefers-color-scheme: dark) {
  [data-codex-window-type=electron] .electron\:dark\:bg-token-side-bar-background:where([data-codex-window-type=electron] .electron\:dark\:bg-token-side-bar-background) {
    background-color: color-mix(in srgb, var(--color-token-side-bar-background) 48%, transparent);
  }
}

[data-codex-window-type=electron] .main-surface:where([data-codex-window-type=electron] .main-surface) {
  background-color: var(--color-token-main-surface-primary);
  background-image: none;
}
/* End Yukino sidebar background patch */
'@

    $text = [IO.File]::ReadAllText($cssFile.FullName)
    $pattern = [regex]::Escape($markerStart) + ".*?" + [regex]::Escape($markerEnd)
    $text = [regex]::Replace($text, $pattern, "", [Text.RegularExpressions.RegexOptions]::Singleline).TrimEnd()
    [IO.File]::WriteAllText($cssFile.FullName, $text + "`n" + $patch + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Patched Yukino sidebar background into $($cssFile.Name)"
}

function Patch-BuildJs([string]$ExtractDir, [string]$SidebarBackgroundSource) {
    $buildDir = Join-Path $ExtractDir ".vite\build"
    $bootstrap = Join-Path $buildDir "bootstrap.js"
    $prefix = 'process.env.CODEX_HOME||(process.env.CODEX_HOME=require(`node:path`).join(require(`node:os`).homedir(),`.yukino`));process.env.YUKINO_HOME||(process.env.YUKINO_HOME=process.env.CODEX_HOME);'
    $bootstrapText = [IO.File]::ReadAllText($bootstrap)
    if (-not $bootstrapText.StartsWith($prefix)) {
        [IO.File]::WriteAllText($bootstrap, $prefix + $bootstrapText, [Text.UTF8Encoding]::new($false))
    }
    Patch-UpdaterIsolation $bootstrap

    foreach ($file in Get-ChildItem -LiteralPath $buildDir -File -Filter "*.js") {
        $path = $file.FullName
        [void](Replace-Text $path "Codex" "Yukino")
        [void](Replace-Text $path "codex://" "yukino://")
        [void](Replace-Text $path '`codex:`' '`yukino:`')
        [void](Replace-Text $path '$HOME/.codex' '$HOME/.yukino')
        [void](Replace-Text $path '`/.codex`' '`/.yukino`')
        [void](Replace-Text $path '`.codex`' '`.yukino`')
        [void](Replace-Text $path ',`.codex`' ',`.yukino`')
        [void](Replace-Text $path ',`Documents`,`Codex`' ',`Documents`,`Yukino`')
        [void](Replace-Text $path ',`Codex`,`Logs`' ',`Yukino`,`Logs`')
        [void](Replace-Text $path ',`codex`,`logs`' ',`yukino`,`logs`')
        [void](Replace-Text $path '`codex-desktop-' '`yukino-desktop-')
        [void](Replace-Text $path "com.openai.codex" "yukino.akane")

        $text = [IO.File]::ReadAllText($path)
        $text = [regex]::Replace($text, "\.codex(?=[\s/])", ".yukino")
        [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    }

    $packageJson = Join-Path $ExtractDir "package.json"
    [void](Replace-Text $packageJson '"name": "codex-electron"' '"name": "yukino-akane-electron"')
    [void](Replace-Text $packageJson '"productName": "Codex"' '"productName": "Yukino"')
    [void](Replace-Text $packageJson '"author": "OpenAI"' '"author": "Yukino"')
    [void](Replace-Text $packageJson '"description": "Codex"' '"description": "Yukino"')
    [void](Replace-Text $packageJson '"codexWindowsPackageIdentity": "OpenAI.Codex"' '"codexWindowsPackageIdentity": "yukino.akane"')
    [void](Replace-Text $packageJson '"codexWindowsPackagePublisher": "CN=OpenAI, O=OpenAI, L=San Francisco, S=California, C=US"' '"codexWindowsPackagePublisher": "CN=Yukino"')

    $indexHtml = Join-Path $ExtractDir "webview\index.html"
    if (Test-Path -LiteralPath $indexHtml) {
        [void](Replace-Text $indexHtml "<title>Codex</title>" "<title>Yukino</title>")
    }

    Patch-UnsupportedExperimentalFeatureSync -AssetsDir (Join-Path $ExtractDir "webview\assets")
    Patch-PluginAuthGate -AssetsDir (Join-Path $ExtractDir "webview\assets")
    Patch-PluginSidebarRoute -AssetsDir (Join-Path $ExtractDir "webview\assets")
    Patch-AgentSettingsConfigWrites -AssetsDir (Join-Path $ExtractDir "webview\assets")
    Patch-WebviewSidebarBackground -ExtractDir $ExtractDir -SourceImage $SidebarBackgroundSource

    foreach ($relative in @("native-menu-locales", "skills", "webview")) {
        $patched = Patch-TextTreeBranding -Root (Join-Path $ExtractDir $relative) -PackageName "yukino.akane" -DisplayName "Yukino"
        if ($patched -gt 0) {
            Write-Host "Patched $patched text resource file(s) under $relative"
        }
    }
    [void](Patch-TextFileBranding -Path $packageJson -PackageName "yukino.akane" -DisplayName "Yukino")

    foreach ($settingsPage in Get-ChildItem -LiteralPath (Join-Path $ExtractDir "webview\assets") -File -Filter "settings-page-*.js") {
        $text = [IO.File]::ReadAllText($settingsPage.FullName)
        $old = 'case`plugins-settings`:return d===`extension`&&u;case`skills-settings`:return d===`extension`&&!u;'
        $new = 'case`plugins-settings`:return d===`electron`||d===`extension`&&u;case`skills-settings`:return d===`extension`&&!u;'
        if ($text.Contains($old)) {
            [IO.File]::WriteAllText($settingsPage.FullName, $text.Replace($old, $new), [Text.UTF8Encoding]::new($false))
            Write-Host "Enabled desktop plugins settings entry in $($settingsPage.Name)"
        }
    }
}

function Patch-LooseResources([string]$ResourcesRoot, [string]$PackageName, [string]$DisplayName) {
    foreach ($relative in @("plugins")) {
        $patched = Patch-TextTreeBranding -Root (Join-Path $ResourcesRoot $relative) -PackageName $PackageName -DisplayName $DisplayName
        if ($patched -gt 0) {
            Write-Host "Patched $patched loose resource file(s) under $relative"
        }
    }
}

function Patch-AsarHash([string]$ExePath, [string]$OldHash, [string]$NewHash) {
    if ($OldHash.Length -ne 64 -or $NewHash.Length -ne 64) {
        throw "ASAR hashes must be 64 ASCII characters."
    }
    $matches = @(rg -a -b -o $OldHash $ExePath)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one embedded ASAR hash '$OldHash' in $ExePath, found $($matches.Count)."
    }
    $offset = [Int64](($matches[0] -split ":")[0])
    $bytes = [Text.Encoding]::ASCII.GetBytes($NewHash)
    $stream = [IO.File]::Open($ExePath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
    try {
        [void]$stream.Seek($offset, [IO.SeekOrigin]::Begin)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $stream.Dispose()
    }
}

Write-Step "Resolve latest installed OpenAI.Codex"
$sourcePackage = Get-AppxPackage -Name "OpenAI.Codex" | Sort-Object Version -Descending | Select-Object -First 1
if (-not $sourcePackage) {
    throw "OpenAI.Codex is not installed."
}
$sourceRoot = $sourcePackage.InstallLocation
$sourceVersion = [version]$sourcePackage.Version
$targetVersion = "{0}.{1}.{2}.{3}" -f $sourceVersion.Major, $sourceVersion.Minor, $sourceVersion.Build, ($sourceVersion.Revision + 1)
Write-Host "Source: $($sourcePackage.PackageFullName)"
Write-Host "Target version: $targetVersion"

$src = Join-Path $OutputRoot "src_unpacked"
$out = Join-Path $OutputRoot "out"
$logs = Join-Path $OutputRoot "logs"
$work = Join-Path $logs ("build-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $out, $logs, $work -Force | Out-Null

if ($Clean) {
    Write-Step "Clean previous source copy"
    Remove-PathSafe $src $OutputRoot
}

Write-Step "Copy source package"
Remove-PathSafe $src $OutputRoot
Copy-Item -LiteralPath $sourceRoot -Destination $src -Recurse -Force

$sourceManifestPath = Join-Path $work "source-manifest.json"
Invoke-OptionalScript (Join-Path $PSScriptRoot "scripts\Write-YukinoSourceManifest.ps1") @(
    "-SourceRoot", $src,
    "-SourcePackageFullName", $sourcePackage.PackageFullName,
    "-SourceVersion", ([string]$sourcePackage.Version),
    "-ManifestPath", $sourceManifestPath
)

Write-Step "Remove old package metadata"
foreach ($relative in @("AppxBlockMap.xml", "AppxSignature.p7x", "AppxMetadata", "microsoft.system.package.metadata")) {
    Remove-PathSafe (Join-Path $src $relative) $src
}

Write-Step "Patch manifest and executable name"
Patch-Manifest -ManifestPath (Join-Path $src "AppxManifest.xml") -PackageName $PackageName -DisplayName $DisplayName -Publisher $Publisher -Version $targetVersion
Update-AppxIconAssets -PackageRoot $src -SourceImage $IconSource
$oldExe = Join-Path $src "app\Codex.exe"
$newExe = Join-Path $src "app\$DisplayName.exe"
if (Test-Path -LiteralPath $oldExe) {
    Move-Item -LiteralPath $oldExe -Destination $newExe -Force
}
elseif (-not (Test-Path -LiteralPath $newExe)) {
    throw "Cannot find app executable to rename."
}

Write-Step "Extract and patch app.asar"
$resources = Join-Path $src "app\resources"
$asarPath = Join-Path $resources "app.asar"
$extractDir = Join-Path $work "app-extracted"
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
npx --yes @electron/asar extract $asarPath $extractDir
Patch-BuildJs -ExtractDir $extractDir -SidebarBackgroundSource $SidebarBackgroundSource
Patch-LooseResources -ResourcesRoot $resources -PackageName $PackageName -DisplayName $DisplayName

Write-Step "Validate patched JavaScript"
$failed = @()
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $extractDir ".vite\build") -File -Filter "*.js") {
    node --check $file.FullName
    if ($LASTEXITCODE -ne 0) {
        $failed += $file.Name
    }
}
if ($failed.Count -gt 0) {
    throw "node --check failed: $($failed -join ', ')"
}

Write-Step "Repack app.asar"
$patchedAsar = Join-Path $work "app.yukino.asar"
Remove-PathSafe $patchedAsar $work
Remove-PathSafe "$patchedAsar.unpacked" $work
npx --yes @electron/asar pack $extractDir $patchedAsar --unpack-dir "{node_modules/better-sqlite3,node_modules/node-pty}"
Copy-Item -LiteralPath $patchedAsar -Destination $asarPath -Force
Remove-PathSafe (Join-Path $resources "app.asar.unpacked") $resources
Copy-Item -LiteralPath "$patchedAsar.unpacked" -Destination (Join-Path $resources "app.asar.unpacked") -Recurse -Force

Write-Step "Patch Electron ASAR integrity hash"
$launchLog = Join-Path $work "launch-before-hash.log"
$launchStdout = Join-Path $work "launch-before-hash.stdout.log"
$launchStderr = Join-Path $work "launch-before-hash.stderr.log"
$env:ELECTRON_ENABLE_LOGGING = "true"
$env:ELECTRON_ENABLE_STACK_DUMPING = "true"
$launch = Start-Process -FilePath $newExe -ArgumentList @("--enable-logging=stderr", "--v=1") -RedirectStandardOutput $launchStdout -RedirectStandardError $launchStderr -Wait -PassThru
$logText = @(
    if (Test-Path -LiteralPath $launchStdout) { Get-Content -LiteralPath $launchStdout -Raw }
    if (Test-Path -LiteralPath $launchStderr) { Get-Content -LiteralPath $launchStderr -Raw }
) -join "`n"
[IO.File]::WriteAllText($launchLog, $logText, [Text.UTF8Encoding]::new($false))
$match = [regex]::Match($logText, "Integrity check failed for asar archive \(([a-f0-9]{64}) vs ([a-f0-9]{64})\)")
if ($match.Success) {
    Patch-AsarHash -ExePath $newExe -OldHash $match.Groups[1].Value -NewHash $match.Groups[2].Value
    Write-Host "Patched ASAR hash $($match.Groups[1].Value) -> $($match.Groups[2].Value)"
}
elseif ($launch.ExitCode -eq 0) {
    Write-Host "No ASAR hash patch needed."
}
else {
    throw "Could not parse ASAR integrity hash from $launchLog"
}

$installedYukinoRunning = Test-InstalledYukinoRunning -PackageName $PackageName -DisplayName $DisplayName
if ($SkipSmoke -or $installedYukinoRunning) {
    $reason = if ($SkipSmoke) { "-SkipSmoke was set" } else { "installed $DisplayName is running" }
    Write-Host "Skipping source smoke launch because $reason." -ForegroundColor Yellow
}
else {
    Write-Step "Smoke source launch"
    $process = Start-Process -FilePath $newExe -PassThru
    Start-Sleep -Seconds 8
    $process.Refresh()
    if ($process.HasExited) {
        throw "Source Yukino process exited during smoke test."
    }
    Stop-YukinoProcessTree -RootProcessId $process.Id
}

Write-Step "Pack and sign MSIX"
$makeappx = Resolve-SdkTool "makeappx.exe"
$signtool = Resolve-SdkTool "signtool.exe"
$msix = Join-Path $out ("{0}_{1}_x64.msix" -f $PackageName, $targetVersion)
& $makeappx pack /d $src /p $msix /o
if ($LASTEXITCODE -ne 0) {
    throw "makeappx pack failed."
}

$cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $Publisher -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Publisher -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable -KeyUsage DigitalSignature -NotAfter (Get-Date).AddYears(5)
}
$cerPath = Join-Path $out "$DisplayName.cer"
Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null
certutil -addstore -f Root $cerPath | Out-Null

& $signtool sign /fd SHA256 /sha1 $cert.Thumbprint $msix
if ($LASTEXITCODE -ne 0) {
    throw "signtool sign failed."
}
& $signtool verify /pa /v $msix
if ($LASTEXITCODE -ne 0) {
    throw "signtool verify failed."
}

Write-Step "Verify package structure"
$verifyDir = Join-Path $out ("verify-unpack-" + $targetVersion)
Remove-PathSafe $verifyDir $out
& $makeappx unpack /p $msix /d $verifyDir /o | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "makeappx unpack verification failed."
}

$buildAuditPath = Join-Path $work "build-audit.json"
Invoke-OptionalScript (Join-Path $PSScriptRoot "scripts\Write-YukinoBuildAudit.ps1") @(
    "-SourceManifestPath", $sourceManifestPath,
    "-OutputRoot", $src,
    "-AuditPath", $buildAuditPath,
    "-DisplayName", $DisplayName
)

if ($Install) {
    Write-Step "Install Yukino package"
    Write-Host "Install mode will close the installed $DisplayName package before replacing it." -ForegroundColor Yellow
    Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "$DisplayName.exe" -or ($_.Name -eq "codex.exe" -and $_.ExecutablePath -like "*$PackageName*") } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    $existing = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-AppxPackage -Package $existing.PackageFullName
    }
    Add-AppxPackage -Path $msix -ForceApplicationShutdown -ForceUpdateFromAnyVersion

    $verifyScript = Join-Path $OutputRoot "verify-yukino.ps1"
    if (Test-Path -LiteralPath $verifyScript) {
        Write-Step "Verify installed Yukino package"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ProjectRoot $OutputRoot -PackageName $PackageName
        if ($LASTEXITCODE -ne 0) {
            throw "Yukino post-install verification failed."
        }
    }
    else {
        Write-Host "Skipping post-install verification; missing $verifyScript" -ForegroundColor Yellow
    }
}

Write-Step "Done"
$controlHomeScript = Join-Path $PSScriptRoot "scripts\yukino-control-home.ps1"
if (Test-Path -LiteralPath $controlHomeScript) {
    . $controlHomeScript
    Write-YukinoBuildRecord `
        -EventName "build" `
        -SourcePackageFullName $sourcePackage.PackageFullName `
        -SourceVersion ([string]$sourcePackage.Version) `
        -TargetVersion $targetVersion `
        -MsixPath $msix `
        -WorkDir $work `
        -Installed ([bool]$Install) `
        -Summary @{ sourceManifest = $sourceManifestPath; buildAudit = $buildAuditPath; skipSmoke = [bool]$SkipSmoke }
}
[pscustomobject]@{
    SourcePackage = $sourcePackage.PackageFullName
    TargetVersion = $targetVersion
    Msix = $msix
    WorkDir = $work
    Installed = [bool]$Install
}
