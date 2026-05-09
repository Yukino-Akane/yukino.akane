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
$chromeExtensionId = "hehggadaopoacecdllhhajmbjkdcmajg"
$chromeNativeHostName = "com.openai.codexextension"

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

function Get-LogLineTimestamp([string]$Line) {
    $match = [regex]::Match($Line, "^(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\s+")
    if (-not $match.Success) {
        return $null
    }

    try {
        return [datetimeoffset]::Parse(
            $match.Groups["timestamp"].Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )
    }
    catch {
        return $null
    }
}

function Find-BrowserRuntimeActivityLog([object[]]$Files) {
    $startsByTurn = @{}
    $endsByTurn = @{}

    foreach ($file in $Files) {
        $matches = @(Select-String -LiteralPath $file.FullName -Pattern "IAB_LIFECYCLE (captured turn route|ended browser use turn route)" -CaseSensitive:$false -ErrorAction SilentlyContinue)
        foreach ($match in $matches) {
            $turnId = Get-LogField -Line $match.Line -Name "turnId"
            if (-not $turnId) {
                continue
            }

            $timestamp = Get-LogLineTimestamp -Line $match.Line
            if ($null -eq $timestamp) {
                continue
            }

            $entry = [pscustomobject]@{
                TurnId = $turnId
                Timestamp = $timestamp
                Detail = "$($file.Name):$($match.LineNumber):$($match.Line)"
            }

            if ($match.Line -like "*captured turn route*") {
                $startsByTurn[$turnId] = $entry
            }
            elseif ($match.Line -like "*ended browser use turn route*") {
                $endsByTurn[$turnId] = $entry
            }
        }
    }

    $candidates = @()
    foreach ($turnId in $startsByTurn.Keys) {
        if (-not $endsByTurn.ContainsKey($turnId)) {
            continue
        }

        $start = $startsByTurn[$turnId]
        $end = $endsByTurn[$turnId]
        if ($end.Timestamp -ge $start.Timestamp) {
            $candidates += [pscustomobject]@{
                TurnId = $turnId
                Timestamp = $end.Timestamp
                Detail = "turnId=$turnId; turnStart=$($start.Detail); turnEnd=$($end.Detail)"
            }
        }
    }

    $latest = @($candidates | Sort-Object Timestamp -Descending | Select-Object -First 1)
    if ($latest.Count -gt 0) {
        return [pscustomobject]@{
            Found = $true
            TurnId = $latest[0].TurnId
            Detail = $latest[0].Detail
        }
    }

    return [pscustomobject]@{
        Found = $false
        TurnId = ""
        Detail = ""
    }
}

function Test-ChromePluginCache([string]$PluginRoot) {
    $result = [pscustomobject]@{
        Exists = (Test-Path -LiteralPath $PluginRoot)
        Complete = $false
        Missing = @()
        ExtensionId = ""
        ExtensionHostName = ""
        InstallManifestHostName = ""
        Path = $PluginRoot
    }
    if (-not $result.Exists) {
        $result.Missing = @($PluginRoot)
        return $result
    }

    $required = @(
        ".codex-plugin\plugin.json",
        "assets",
        "scripts\extension-id.json",
        "scripts\installManifest.mjs",
        "extension-host\windows\x64\extension-host.exe"
    )
    $missing = @()
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $PluginRoot $relative))) {
            $missing += $relative
        }
    }

    $extensionIdPath = Join-Path $PluginRoot "scripts\extension-id.json"
    if (Test-Path -LiteralPath $extensionIdPath) {
        try {
            $config = Get-Content -Raw -LiteralPath $extensionIdPath | ConvertFrom-Json
            $result.ExtensionId = [string]$config.extensionId
            $result.ExtensionHostName = [string]$config.extensionHostName
        }
        catch {
            $missing += "scripts\extension-id.json: invalid JSON"
        }
    }

    $installManifestPath = Join-Path $PluginRoot "scripts\installManifest.mjs"
    if (Test-Path -LiteralPath $installManifestPath) {
        $text = [IO.File]::ReadAllText($installManifestPath)
        $match = [regex]::Match($text, 'extensionHostName:"([^"]+)"')
        if ($match.Success) {
            $result.InstallManifestHostName = $match.Groups[1].Value
        }
        else {
            $missing += "scripts\installManifest.mjs: missing extensionHostName"
        }
    }

    if ($result.ExtensionId -ne $chromeExtensionId) {
        $missing += "scripts\extension-id.json: extensionId should be $chromeExtensionId"
    }
    if ($result.ExtensionHostName -ne $chromeNativeHostName) {
        $missing += "scripts\extension-id.json: extensionHostName should be $chromeNativeHostName"
    }
    if ($result.InstallManifestHostName -ne $chromeNativeHostName) {
        $missing += "scripts\installManifest.mjs: extensionHostName should be $chromeNativeHostName"
    }

    $result.Missing = @($missing)
    $result.Complete = $result.Missing.Count -eq 0
    return $result
}

function Get-RegistryDefaultValue([string]$RegistryKey) {
    $output = & reg query $RegistryKey /ve 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $output) {
        return $null
    }
    foreach ($line in $output) {
        $match = [regex]::Match($line, '^\s*\(Default\)\s+REG_\w+\s+(.+?)\s*$')
        if ($match.Success) {
            return $match.Groups[1].Value.Trim('"')
        }
    }
    return $null
}

function Test-ChromeNativeHostYukinoTarget {
    $registryKey = "HKCU\Software\Google\Chrome\NativeMessagingHosts\$chromeNativeHostName"
    $manifestPath = Get-RegistryDefaultValue $registryKey
    if (-not $manifestPath) {
        return [pscustomobject]@{ Correct = $false; Detail = "Missing registry key: $registryKey" }
    }
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return [pscustomobject]@{ Correct = $false; Detail = "Registry manifest path does not exist: $manifestPath" }
    }

    try {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{ Correct = $false; Detail = "Invalid native host manifest JSON: $manifestPath" }
    }

    $expectedOrigin = "chrome-extension://$chromeExtensionId/"
    $hostPath = [string]$manifest.path
    $allowedOrigins = @($manifest.allowed_origins)
    $problems = @()
    if ($manifest.name -ne $chromeNativeHostName) {
        $problems += "name=$($manifest.name)"
    }
    if ($hostPath -notlike "*\.yukino\plugins\cache\openai-bundled\chrome\latest\extension-host\windows\x64\extension-host.exe") {
        $problems += "path=$hostPath"
    }
    if ($allowedOrigins -notcontains $expectedOrigin) {
        $problems += "allowed_origins missing $expectedOrigin"
    }

    if ($problems.Count -gt 0) {
        return [pscustomobject]@{ Correct = $false; Detail = "$manifestPath; $($problems -join '; ')" }
    }

    return [pscustomobject]@{ Correct = $true; Detail = "$manifestPath -> $hostPath" }
}

function Add-InstalledChromePluginCacheCheck([string]$PluginRoot) {
    $result = Test-ChromePluginCache -PluginRoot $PluginRoot
    if ($result.Complete) {
        Add-Check "installed-chrome-plugin-cache" "PASS" $PluginRoot
        return
    }

    $repairScript = Join-Path $ProjectRoot "scripts\Repair-YukinoChromePluginCache.ps1"
    if (Test-Path -LiteralPath $repairScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $repairScript | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $repairedResult = Test-ChromePluginCache -PluginRoot $PluginRoot
            if ($repairedResult.Complete) {
                Add-Check "installed-chrome-plugin-cache" "PASS" "Repaired incomplete Chrome plugin cache at $PluginRoot"
                return
            }
            Add-Check "installed-chrome-plugin-cache" "WARN" "Repair ran, but Chrome plugin cache remains incomplete at $PluginRoot; missing or invalid: $($repairedResult.Missing -join '; ')"
            return
        }
    }

    Add-Check "installed-chrome-plugin-cache" "WARN" "Incomplete Chrome plugin cache at $PluginRoot; missing or invalid: $($result.Missing -join '; ')"
}

function Get-ChromePluginPendingCleanupEntries([string]$ChromeCacheRoot) {
    $pendingManifest = Join-Path $ChromeCacheRoot "pending-delete.jsonl"
    if (-not (Test-Path -LiteralPath $pendingManifest)) {
        return @()
    }

    $pending = @()
    foreach ($line in [IO.File]::ReadLines($pendingManifest)) {
        if (-not $line.Trim()) {
            continue
        }
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ($record.path) {
                $pending += [string]$record.path
            }
        }
        catch {
            $pending += "invalid manifest line"
        }
    }

    return $pending
}

function Add-ChromePluginCachePendingCleanupCheck([string]$ChromeCacheRoot) {
    $pendingManifest = Join-Path $ChromeCacheRoot "pending-delete.jsonl"
    if (-not (Test-Path -LiteralPath $pendingManifest)) {
        Add-Check "chrome-plugin-cache-pending-cleanup" "PASS" "No pending delayed cleanup manifest: $pendingManifest"
        return
    }

    $pending = @(Get-ChromePluginPendingCleanupEntries -ChromeCacheRoot $ChromeCacheRoot)

    if ($pending.Count -eq 0) {
        Add-Check "chrome-plugin-cache-pending-cleanup" "PASS" "Delayed cleanup manifest is empty: $pendingManifest"
    }
    else {
        Add-Check "chrome-plugin-cache-pending-cleanup" "WARN" "$($pending.Count) pending path(s) in $pendingManifest; latest=$($pending[0])"
    }
}

function Get-SessionDynamicToolNames {
    $sessionsRoot = Join-Path $env:USERPROFILE ".yukino\sessions"
    $empty = [pscustomobject]@{
        SessionPath = ""
        ToolNames = @()
        Error = ""
    }
    if (-not (Test-Path -LiteralPath $sessionsRoot)) {
        $empty.Error = "Missing sessions directory: $sessionsRoot"
        return $empty
    }

    $latestSession = Get-ChildItem -LiteralPath $sessionsRoot -File -Filter "rollout-*.jsonl" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latestSession) {
        $empty.Error = "No rollout session files found under $sessionsRoot"
        return $empty
    }

    try {
        $stream = [IO.File]::Open($latestSession.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $reader = New-Object IO.StreamReader($stream)
            try {
                while (-not $reader.EndOfStream) {
                    $line = $reader.ReadLine()
                    if (-not $line -or $line -notlike '*"session_meta"*') {
                        continue
                    }
                    try {
                        $record = $line | ConvertFrom-Json
                    }
                    catch {
                        continue
                    }
                    if ($record.type -ne "session_meta") {
                        continue
                    }

                    $toolNames = @()
                    foreach ($tool in @($record.payload.dynamic_tools)) {
                        if ($tool -is [string]) {
                            $toolNames += $tool
                        }
                        elseif ($tool.name) {
                            $toolNames += [string]$tool.name
                        }
                        elseif ($tool.function -and $tool.function.name) {
                            $toolNames += [string]$tool.function.name
                        }
                    }
                    return [pscustomobject]@{
                        SessionPath = $latestSession.FullName
                        ToolNames = @($toolNames | Where-Object { $_ } | Sort-Object -Unique)
                        Error = ""
                    }
                }
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return [pscustomobject]@{
            SessionPath = $latestSession.FullName
            ToolNames = @()
            Error = $_.Exception.Message
        }
    }

    return [pscustomobject]@{
        SessionPath = $latestSession.FullName
        ToolNames = @()
        Error = "No session_meta record found"
    }
}

function Get-ProcessPathById([int]$ProcessId) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($process -and $process.ExecutablePath) {
        return $process.ExecutablePath
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

    if (Test-TomlSectionBoolean $configText 'plugins\."chrome@openai-bundled"' "enabled" $true) {
        Add-Check "config-chrome-plugin" "PASS" "chrome@openai-bundled enabled"
    }
    else {
        Add-Check "config-chrome-plugin" "WARN" "chrome@openai-bundled enabled=true not found"
    }
}
else {
    Add-Check "config-file" "FAIL" "Missing config: $ConfigPath"
}

$installedChromeCacheRoot = Join-Path $env:USERPROFILE ".yukino\plugins\cache\openai-bundled\chrome"
$installedChromePluginRoot = Join-Path $installedChromeCacheRoot "latest"
Add-InstalledChromePluginCacheCheck $installedChromePluginRoot
Add-ChromePluginCachePendingCleanupCheck $installedChromeCacheRoot

$nativeHostStatus = Test-ChromeNativeHostYukinoTarget
if ($nativeHostStatus.Correct) {
    Add-Check "chrome-native-host-yukino-target" "PASS" $nativeHostStatus.Detail
}
else {
    Add-Check "chrome-native-host-yukino-target" "WARN" $nativeHostStatus.Detail
}

$sessionTools = Get-SessionDynamicToolNames
if ($sessionTools.Error) {
    Add-Check "session-dynamic-tools" "WARN" $sessionTools.Error
}
else {
    $toolNames = @($sessionTools.ToolNames)
    $toolSummary = if ($toolNames.Count -gt 0) { $toolNames -join ", " } else { "(none)" }
    Add-Check "session-dynamic-tools" "PASS" "$($toolNames.Count) dynamic tool(s) in latest session metadata $($sessionTools.SessionPath): $toolSummary"
}

$nodeReplProcesses = @(Get-CimInstance Win32_Process -Filter "Name='node_repl.exe'" -ErrorAction SilentlyContinue)
$details = @()
$hasYukinoNodeRepl = $false
$hasOfficialNodeRepl = $false
foreach ($process in $nodeReplProcesses) {
    $exePath = $process.ExecutablePath
    $parentPath = Get-ProcessPathById -ProcessId ([int]$process.ParentProcessId)
    if ($exePath -like "*\OpenAI\Yukino\bin\node_repl.exe" -or $parentPath -like "*\yukino.akane_*") {
        $hasYukinoNodeRepl = $true
    }
    if ($exePath -like "*\OpenAI\Codex\bin\node_repl.exe" -or $parentPath -like "*\OpenAI.Codex_*") {
        $hasOfficialNodeRepl = $true
    }
    $details += "pid=$($process.ProcessId); parent=$($process.ParentProcessId); exe=$exePath; parentExe=$parentPath"
}

if (-not $sessionTools.Error) {
    if ($toolNames -contains "mcp__node_repl__js" -or $toolNames -contains "node_repl" -or $toolNames -contains "js") {
        Add-Check "session-node-repl-tool" "PASS" "Browser execution tool is exposed in latest session metadata"
    }
    elseif ($hasYukinoNodeRepl) {
        Add-Check "session-node-repl-tool" "PASS" "Latest session metadata lacks Browser tool, but a live Yukino node_repl runtime is present"
    }
    else {
        Add-Check "session-node-repl-tool" "WARN" "No browser execution tool in latest session metadata; expected mcp__node_repl__js/node_repl/js for Browser control"
    }
}
elseif ($hasYukinoNodeRepl) {
    Add-Check "session-node-repl-tool" "PASS" "Could not inspect session metadata, but a live Yukino node_repl runtime is present"
}
else {
    Add-Check "session-node-repl-tool" "WARN" "Could not inspect current session dynamic tools"
}

if ($nodeReplProcesses.Count -eq 0) {
    Add-Check "node-repl-process" "WARN" "No live node_repl.exe process found"
}
else {
    if ($hasYukinoNodeRepl) {
        Add-Check "node-repl-process" "PASS" ($details -join " | ")
    }
    elseif ($hasOfficialNodeRepl) {
        Add-Check "node-repl-process" "WARN" "Only official Codex node_repl.exe appears live, not Yukino: $($details -join ' | ')"
    }
    else {
        Add-Check "node-repl-process" "WARN" ($details -join " | ")
    }
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
    $browserRuntimeLines = @()
    $unsupportedWorkspaceDependencyLines = @()
    $pluginCacheLockLines = @()
    foreach ($file in $logFiles) {
        $matches = Select-String -LiteralPath $file.FullName -Pattern 'pluginsAuthBlockedToast|pluginDeepLinkAuthBlocked|configVersionConflict|Unable to save|errorCode=-32600|uncaughtException|Unhandled|startup|fatal|browser-use native pipe listening|BrowserUseThreadConfig|IAB_LIFECYCLE (captured turn route|ended browser use turn route)|unsupported feature enablement .*workspace_dependencies|plugin_cache_windows_file_lock' -ErrorAction SilentlyContinue
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
            if ($line -like "*browser-use native pipe listening*" -or $line -like "*BrowserUseThreadConfig*") {
                $browserRuntimeLines += "$($file.Name):$($match.LineNumber):$line"
            }
            if ($line -like "*unsupported feature enablement*workspace_dependencies*") {
                $unsupportedWorkspaceDependencyLines += "$($file.Name):$($match.LineNumber):$line"
            }
            if ($line -like "*plugin_cache_windows_file_lock*") {
                $pluginCacheLockLines += "$($file.Name):$($match.LineNumber):$line"
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

    if ($browserRuntimeLines.Count -gt 0) {
        Add-Check "browser-use-runtime-log" "PASS" "$($browserRuntimeLines.Count) Browser runtime marker line(s); latest=$($browserRuntimeLines[0])"
    }
    else {
        Add-Check "browser-use-runtime-log" "WARN" "No 'browser-use native pipe listening' or BrowserUseThreadConfig markers in latest $RecentLogFileCount log file(s)"
    }

    $browserActivity = Find-BrowserRuntimeActivityLog -Files $logFiles
    if ($browserActivity.Found) {
        Add-Check "browser-runtime-activity-log" "PASS" $browserActivity.Detail
    }
    else {
        Add-Check "browser-runtime-activity-log" "WARN" "No matched Browser activity turn in latest $RecentLogFileCount log file(s); after a manual Browser task, run scripts\Test-YukinoPostInstallBrowserSmoke.ps1 -MinLogTime (Get-Date).AddMinutes(-10) -RequireBrowserRuntimeActivity for strict validation."
    }

    if ($unsupportedWorkspaceDependencyLines.Count -eq 0) {
        Add-Check "unsupported-workspace-dependencies-log" "PASS" "No unsupported feature enablement workspace_dependencies lines in latest $RecentLogFileCount log file(s)"
    }
    else {
        Add-Check "unsupported-workspace-dependencies-log" "WARN" "$($unsupportedWorkspaceDependencyLines.Count) unsupported workspace_dependencies line(s); first=$($unsupportedWorkspaceDependencyLines[0])"
    }

    if ($pluginCacheLockLines.Count -eq 0) {
        Add-Check "plugin_cache_windows_file_lock" "PASS" "No Chrome plugin cache lock failures in latest $RecentLogFileCount log file(s)"
    }
    else {
        $cacheState = Test-ChromePluginCache -PluginRoot $installedChromePluginRoot
        $pendingCleanupEntries = @(Get-ChromePluginPendingCleanupEntries -ChromeCacheRoot $installedChromeCacheRoot)
        $cacheRecovered = $cacheState.Complete -and $pendingCleanupEntries.Count -eq 0 -and $nativeHostStatus.Correct
        if ($cacheRecovered) {
            Add-Check "plugin_cache_windows_file_lock" "PASS" "Recovered Chrome plugin cache lock evidence (Historical/recovered): $($pluginCacheLockLines.Count) line(s); latest=$($pluginCacheLockLines[0])"
        }
        else {
            Add-Check "plugin_cache_windows_file_lock" "WARN" "Active or unrecovered Chrome plugin cache lock evidence: $($pluginCacheLockLines.Count) line(s); cacheComplete=$($cacheState.Complete); pendingCleanupEntries=$($pendingCleanupEntries.Count); nativeHostCorrect=$($nativeHostStatus.Correct); latest=$($pluginCacheLockLines[0])"
        }
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
