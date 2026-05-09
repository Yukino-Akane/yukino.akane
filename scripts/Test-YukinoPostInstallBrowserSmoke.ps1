param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$PackageName = "yukino.akane",
    [int]$RecentLogFileCount = 12,
    [datetime]$MinLogTime = [datetime]::MinValue,
    [switch]$RequireBrowserRuntimeActivity,
    [switch]$OpenChromeWindow
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

function Get-ProcessPathById([int]$ProcessId) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($process -and $process.ExecutablePath) {
        return $process.ExecutablePath
    }
    return ""
}

function Invoke-NodeJsonScript([string]$ScriptPath, [string[]]$Arguments, [string]$Description) {
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return [pscustomobject]@{
            ExitCode = 2
            Text = "Missing $Description script: $ScriptPath"
            Json = $null
        }
    }

    $output = & node $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $json = $null
    if ($text) {
        try {
            $json = $text | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            return [pscustomobject]@{
                ExitCode = 2
                Text = "Could not parse $Description JSON output: $text"
                Json = $null
            }
        }
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = $text
        Json = $json
    }
}

function Get-RecentYukinoLogFiles([int]$Count, [datetime]$MinTime) {
    $logDate = Get-Date
    $appLogDir = Join-Path $env:LOCALAPPDATA ("Yukino\Logs\{0}\{1}\{2}" -f $logDate.ToString("yyyy"), $logDate.ToString("MM"), $logDate.ToString("dd"))
    if (-not (Test-Path -LiteralPath $appLogDir)) {
        return [pscustomobject]@{
            Directory = $appLogDir
            Files = @()
            Error = "No app log directory for today: $appLogDir"
        }
    }

    $files = @(Get-ChildItem -LiteralPath $appLogDir -File |
        Where-Object { $MinTime -eq [datetime]::MinValue -or $_.LastWriteTime -ge $MinTime } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Count)
    return [pscustomobject]@{
        Directory = $appLogDir
        Files = $files
        Error = ""
    }
}

function Find-FirstLogMatch([object[]]$Files, [string]$Pattern) {
    foreach ($file in $Files) {
        $match = Select-String -LiteralPath $file.FullName -Pattern $Pattern -CaseSensitive:$false -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) {
            return "$($file.Name):$($match.LineNumber):$($match.Line)"
        }
    }
    return ""
}

function Convert-ToDateTimeOffset([datetime]$Value) {
    if ($Value -eq [datetime]::MinValue) {
        return $null
    }
    if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
        $Value = [datetime]::SpecifyKind($Value, [DateTimeKind]::Local)
    }
    return [datetimeoffset]::new($Value)
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

function Test-LogLineAtOrAfter([string]$Line, [datetime]$MinTime) {
    $minOffset = Convert-ToDateTimeOffset -Value $MinTime
    if ($null -eq $minOffset) {
        return $true
    }

    $lineOffset = Get-LogLineTimestamp -Line $Line
    if ($null -eq $lineOffset) {
        return $false
    }

    return $lineOffset -ge $minOffset
}

function Find-FirstRecentLogMatch([object[]]$Files, [string]$Pattern, [datetime]$MinTime) {
    foreach ($file in $Files) {
        $matches = @(Select-String -LiteralPath $file.FullName -Pattern $Pattern -CaseSensitive:$false -ErrorAction SilentlyContinue)
        foreach ($match in $matches) {
            if (Test-LogLineAtOrAfter -Line $match.Line -MinTime $MinTime) {
                return "$($file.Name):$($match.LineNumber):$($match.Line)"
            }
        }
    }
    return ""
}

function Get-LogLineField([string]$Line, [string]$Name) {
    $match = [regex]::Match($Line, "(?:^|\s)$([regex]::Escape($Name))=(?<value>[^\s]+)")
    if ($match.Success) {
        return $match.Groups["value"].Value.Trim('"')
    }
    return ""
}

function Find-BrowserRuntimeActivityLog([object[]]$Files, [datetime]$MinTime) {
    $startsByTurn = @{}
    $endsByTurn = @{}

    foreach ($file in $Files) {
        $matches = @(Select-String -LiteralPath $file.FullName -Pattern "IAB_LIFECYCLE (captured turn route|ended browser use turn route)" -CaseSensitive:$false -ErrorAction SilentlyContinue)
        foreach ($match in $matches) {
            if (-not (Test-LogLineAtOrAfter -Line $match.Line -MinTime $MinTime)) {
                continue
            }

            $turnId = Get-LogLineField -Line $match.Line -Name "turnId"
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

    foreach ($turnId in $startsByTurn.Keys) {
        if (-not $endsByTurn.ContainsKey($turnId)) {
            continue
        }

        $start = $startsByTurn[$turnId]
        $end = $endsByTurn[$turnId]
        if ($end.Timestamp -ge $start.Timestamp) {
            return [pscustomobject]@{
                Found = $true
                TurnId = $turnId
                Detail = "turnId=$turnId; turnStart=$($start.Detail); turnEnd=$($end.Detail)"
            }
        }
    }

    return [pscustomobject]@{
        Found = $false
        TurnId = ""
        Detail = ""
    }
}

function Test-YukinoProcessPath([string]$Path, [string]$InstallLocation) {
    if (-not $Path) {
        return $false
    }
    return $Path -like "$InstallLocation*"
}

function Get-LazyBrowserRuntimeDetail([string]$EvidenceName) {
    return "Browser runtime has not been triggered in this launch window; $EvidenceName is expected only after a Browser tool call. Installed app-server, Chrome extension, native host, and cache checks still validate the post-install Browser surface."
}

function Get-SmokeGroupStatus([object[]]$Checks, [string[]]$Names) {
    $items = @($Checks | Where-Object { $Names -contains $_.Name })
    if ($items.Count -eq 0) {
        return "SKIP"
    }
    if (@($items | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0) {
        return "FAIL"
    }
    if (@($items | Where-Object { $_.Status -eq "WARN" }).Count -gt 0) {
        return "WARN"
    }
    return "PASS"
}

function Write-SmokeSummary([object[]]$Checks) {
    $failures = @($Checks | Where-Object { $_.Status -eq "FAIL" })
    $warnings = @($Checks | Where-Object { $_.Status -eq "WARN" })
    $overall = if ($failures.Count -gt 0) { "FAIL" } elseif ($warnings.Count -gt 0) { "WARN" } else { "PASS" }

    $summary = @(
        [pscustomobject]@{
            Area = "Startup"
            Status = Get-SmokeGroupStatus -Checks $Checks -Names @(
                "installed-yukino-package",
                "installed-yukino-exe",
                "running-yukino-process",
                "app-server-yukino-process",
                "app-server-log"
            )
        },
        [pscustomobject]@{
            Area = "Browser runtime"
            Status = Get-SmokeGroupStatus -Checks $Checks -Names @(
                "node-repl-yukino-runtime",
                "browser-use-native-pipe-server",
                "browser-runtime-yukino-path-log",
                "browser-runtime-activity-log",
                "browser-runtime-tab-log"
            )
        },
        [pscustomobject]@{
            Area = "Chrome extension"
            Status = Get-SmokeGroupStatus -Checks $Checks -Names @(
                "chrome-extension-installed",
                "chrome-native-host-manifest",
                "chrome-native-host-yukino-target"
            )
        },
        [pscustomobject]@{
            Area = "Plugin cache"
            Status = Get-SmokeGroupStatus -Checks $Checks -Names @(
                "chrome-plugin-cache"
            )
        },
        [pscustomobject]@{
            Area = "Chrome launch"
            Status = Get-SmokeGroupStatus -Checks $Checks -Names @(
                "chrome-open-window"
            )
        },
        [pscustomobject]@{
            Area = "Overall"
            Status = $overall
        }
    )

    Write-Host ""
    Write-Host "Yukino post-install summary" -ForegroundColor Cyan
    $summary | Format-Table -AutoSize
}

Write-Host ""
Write-Host "Yukino post-install Browser smoke" -ForegroundColor Cyan
Write-Host "ProjectRoot: $ProjectRoot"
Write-Host "Package    : $PackageName"
if ($MinLogTime -ne [datetime]::MinValue) {
    Write-Host "MinLogTime : $($MinLogTime.ToString('o'))"
}
if ($RequireBrowserRuntimeActivity) {
    Write-Host "Browser runtime activity evidence is required."
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Add-Check "node-command" "FAIL" "node is required to run Chrome plugin helper scripts."
}
else {
    Add-Check "node-command" "PASS" (Get-Command node).Source
}

$project = $null
try {
    $project = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path
    Add-Check "project-root" "PASS" $project
}
catch {
    Add-Check "project-root" "FAIL" "Missing project root: $ProjectRoot"
}

$installed = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $installed) {
    Add-Check "installed-yukino-package" "FAIL" "No installed package named $PackageName"
}
else {
    Add-Check "installed-yukino-package" "PASS" "PackageFullName=$($installed.PackageFullName); InstallLocation=$($installed.InstallLocation)"

    $installedExe = Join-Path $installed.InstallLocation "app\Yukino.exe"
    if (Test-Path -LiteralPath $installedExe) {
        Add-Check "installed-yukino-exe" "PASS" $installedExe
    }
    else {
        Add-Check "installed-yukino-exe" "FAIL" "Missing installed executable: $installedExe"
    }

    $runningYukino = @(Get-CimInstance Win32_Process -Filter "Name='Yukino.exe'" -ErrorAction SilentlyContinue |
        Where-Object { Test-YukinoProcessPath -Path $_.ExecutablePath -InstallLocation $installed.InstallLocation })
    if ($runningYukino.Count -gt 0) {
        Add-Check "running-yukino-process" "PASS" "$($runningYukino.Count) process(es); main pid(s)=$((@($runningYukino | Where-Object { $_.CommandLine -notmatch ' --type=' } | Select-Object -ExpandProperty ProcessId) -join ', '))"
    }
    else {
        Add-Check "running-yukino-process" "FAIL" "No running Yukino.exe process from $($installed.InstallLocation)"
    }

    $appServerExe = Join-Path $installed.InstallLocation "app\resources\codex.exe"
    $appServerProcesses = @(Get-CimInstance Win32_Process -Filter "Name='codex.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "* app-server*" -and $_.ExecutablePath -eq $appServerExe })
    if ($appServerProcesses.Count -gt 0) {
        Add-Check "app-server-yukino-process" "PASS" "$($appServerProcesses.Count) process(es); $appServerExe"
    }
    else {
        Add-Check "app-server-yukino-process" "FAIL" "No Yukino app-server process from $appServerExe"
    }

    $nodeReplProcesses = @(Get-CimInstance Win32_Process -Filter "Name='node_repl.exe'" -ErrorAction SilentlyContinue)
    $yukinoNodeRepl = @()
    foreach ($process in $nodeReplProcesses) {
        $parentPath = Get-ProcessPathById -ProcessId ([int]$process.ParentProcessId)
        if (($process.ExecutablePath -like "*\OpenAI\Yukino\bin\node_repl.exe") -or (Test-YukinoProcessPath -Path $parentPath -InstallLocation $installed.InstallLocation)) {
            $yukinoNodeRepl += $process
        }
    }
    if ($yukinoNodeRepl.Count -gt 0) {
        Add-Check "node-repl-yukino-runtime" "PASS" "$($yukinoNodeRepl.Count) node_repl.exe process(es); $((@($yukinoNodeRepl | Select-Object -ExpandProperty ExecutablePath -Unique)) -join '; ')"
    }
    else {
        if ($RequireBrowserRuntimeActivity) {
            Add-Check "node-repl-yukino-runtime" "FAIL" "No live Yukino node_repl.exe runtime after Browser activity was required."
        }
        else {
            Add-Check "node-repl-yukino-runtime" "WARN" (Get-LazyBrowserRuntimeDetail -EvidenceName "a live Yukino node_repl.exe runtime")
        }
    }
}

$logStatus = Get-RecentYukinoLogFiles -Count $RecentLogFileCount -MinTime $MinLogTime
if ($logStatus.Files.Count -eq 0) {
    $detail = if ($logStatus.Error) { $logStatus.Error } else { "No Yukino log files at or after $($MinLogTime.ToString('o')) under $($logStatus.Directory)" }
    Add-Check "recent-yukino-log-files" "FAIL" $detail
}
else {
    $logDetail = "$($logStatus.Files.Count) file(s) under $($logStatus.Directory)"
    if ($MinLogTime -ne [datetime]::MinValue) {
        $logDetail += "; filtered after $($MinLogTime.ToString('o'))"
    }
    Add-Check "recent-yukino-log-files" "PASS" $logDetail

    $appServerLog = Find-FirstLogMatch -Files $logStatus.Files -Pattern "\[AppServerConnection\].*(Yukino CLI initialized|initialize_handshake_result.*outcome=success|Current reported app-server version)"
    if ($appServerLog) {
        Add-Check "app-server-log" "PASS" $appServerLog
    }
    else {
        Add-Check "app-server-log" "FAIL" "No recent AppServerConnection success marker in latest $RecentLogFileCount log file(s)."
    }

    $browserPipeLog = Find-FirstRecentLogMatch -Files $logStatus.Files -Pattern "browser-use native pipe listening" -MinTime $MinLogTime
    if (-not $browserPipeLog -and $RequireBrowserRuntimeActivity) {
        $browserPipeLog = Find-FirstLogMatch -Files $logStatus.Files -Pattern "browser-use native pipe listening"
    }
    if ($browserPipeLog) {
        Add-Check "browser-use-native-pipe-server" "PASS" $browserPipeLog
    }
    else {
        if ($RequireBrowserRuntimeActivity) {
            Add-Check "browser-use-native-pipe-server" "FAIL" "No recent browser-use native pipe listening log marker at or after $($MinLogTime.ToString('o'))."
        }
        else {
            Add-Check "browser-use-native-pipe-server" "WARN" (Get-LazyBrowserRuntimeDetail -EvidenceName "the browser-use native pipe listening log marker")
        }
    }

    $runtimePathLog = Find-FirstRecentLogMatch -Files $logStatus.Files -Pattern "BrowserUseThreadConfig.*OpenAI\\Yukino\\bin\\node_repl\.exe" -MinTime $MinLogTime
    if (-not $runtimePathLog -and $RequireBrowserRuntimeActivity) {
        $runtimePathLog = Find-FirstLogMatch -Files $logStatus.Files -Pattern "BrowserUseThreadConfig.*OpenAI\\Yukino\\bin\\node_repl\.exe"
    }
    if ($runtimePathLog) {
        Add-Check "browser-runtime-yukino-path-log" "PASS" $runtimePathLog
    }
    else {
        if ($RequireBrowserRuntimeActivity) {
            Add-Check "browser-runtime-yukino-path-log" "FAIL" "No recent BrowserUseThreadConfig Yukino runtime path log marker at or after $($MinLogTime.ToString('o'))."
        }
        else {
            Add-Check "browser-runtime-yukino-path-log" "WARN" (Get-LazyBrowserRuntimeDetail -EvidenceName "the BrowserUseThreadConfig Yukino runtime path log marker")
        }
    }

    $activityLog = Find-BrowserRuntimeActivityLog -Files $logStatus.Files -MinTime $MinLogTime
    if ($activityLog.Found) {
        Add-Check "browser-runtime-activity-log" "PASS" $activityLog.Detail
    }
    elseif ($RequireBrowserRuntimeActivity) {
        Add-Check "browser-runtime-activity-log" "FAIL" "Missing recent matched Browser runtime activity log markers: captured turn route and ended browser use turn route with the same turnId; MinLogTime=$($MinLogTime.ToString('o')). Trigger Yukino with a Browser task such as opening https://example.com, then rerun this smoke with -RequireBrowserRuntimeActivity."
    }

    $createTabLog = Find-FirstRecentLogMatch -Files $logStatus.Files -Pattern "browser-use-iab-api.*iab createTab mapped page to tab" -MinTime $MinLogTime
    $pageReadyLog = Find-FirstRecentLogMatch -Files $logStatus.Files -Pattern "browser-sidebar-manager.*browser sidebar dom-ready.*url=" -MinTime $MinLogTime
    if ($createTabLog -or $pageReadyLog) {
        Add-Check "browser-runtime-tab-log" "PASS" "createTab=$createTabLog; pageReady=$pageReadyLog"
    }
}

$pluginRoot = Join-Path $env:USERPROFILE ".yukino\plugins\cache\openai-bundled\chrome\latest"
$pluginScripts = Join-Path $pluginRoot "scripts"
if (-not (Test-Path -LiteralPath $pluginScripts)) {
    $repairScript = if ($project) { Join-Path $project "scripts\Repair-YukinoChromePluginCache.ps1" } else { "" }
    if ($repairScript -and (Test-Path -LiteralPath $repairScript)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $repairScript | Out-Null
    }
}

if (Test-Path -LiteralPath $pluginScripts) {
    Add-Check "chrome-plugin-cache" "PASS" $pluginRoot
}
else {
    Add-Check "chrome-plugin-cache" "FAIL" "Missing Chrome plugin scripts under $pluginScripts"
}

$extensionCheck = Invoke-NodeJsonScript -ScriptPath (Join-Path $pluginScripts "check-extension-installed.js") -Arguments @("--json") -Description "Chrome extension install check"
if ($extensionCheck.ExitCode -eq 0 -and $extensionCheck.Json -and $extensionCheck.Json.installed -and $extensionCheck.Json.enabled -and $extensionCheck.Json.extensionId -eq $chromeExtensionId) {
    Add-Check "chrome-extension-installed" "PASS" "extensionId=$($extensionCheck.Json.extensionId); profile=$($extensionCheck.Json.profilePath); versions=$($extensionCheck.Json.versions -join ',')"
}
else {
    Add-Check "chrome-extension-installed" "FAIL" "Chrome extension is not installed/enabled as expected. exit=$($extensionCheck.ExitCode); output=$($extensionCheck.Text)"
}

$nativeHostCheck = Invoke-NodeJsonScript -ScriptPath (Join-Path $pluginScripts "check-native-host-manifest.js") -Arguments @("--json") -Description "Chrome native host manifest check"
if ($nativeHostCheck.ExitCode -eq 0 -and $nativeHostCheck.Json -and $nativeHostCheck.Json.correct -and $nativeHostCheck.Json.expectedHostName -eq $chromeNativeHostName) {
    Add-Check "chrome-native-host-manifest" "PASS" "$($nativeHostCheck.Json.manifestPath)"

    try {
        $manifest = Get-Content -Raw -LiteralPath $nativeHostCheck.Json.manifestPath | ConvertFrom-Json
        $hostPath = [string]$manifest.path
        if ($hostPath -like "*\.yukino\plugins\cache\openai-bundled\chrome\latest\extension-host\windows\x64\extension-host.exe" -and (Test-Path -LiteralPath $hostPath)) {
            Add-Check "chrome-native-host-yukino-target" "PASS" $hostPath
        }
        else {
            Add-Check "chrome-native-host-yukino-target" "FAIL" "Native host target is not Yukino's extension-host.exe: $hostPath"
        }
    }
    catch {
        Add-Check "chrome-native-host-yukino-target" "FAIL" "Could not inspect native host target: $($_.Exception.Message)"
    }
}
else {
    Add-Check "chrome-native-host-manifest" "FAIL" "Native host manifest is not correct. exit=$($nativeHostCheck.ExitCode); output=$($nativeHostCheck.Text)"
}

$chromeOpenArgs = if ($OpenChromeWindow) { @("--json") } else { @("--dry-run", "--json") }
$chromeOpenCheck = Invoke-NodeJsonScript -ScriptPath (Join-Path $pluginScripts "open-chrome-window.js") -Arguments $chromeOpenArgs -Description "Chrome harmless open check"
if ($chromeOpenCheck.ExitCode -eq 0 -and $chromeOpenCheck.Json -and $chromeOpenCheck.Json.args -contains "about:blank") {
    $mode = if ($OpenChromeWindow) { "opened" } else { "dry-run" }
    Add-Check "chrome-open-window" "PASS" "$mode about:blank via $($chromeOpenCheck.Json.command); profile=$($chromeOpenCheck.Json.profileDirectory)"
}
else {
    Add-Check "chrome-open-window" "FAIL" "Could not validate harmless Chrome open command. exit=$($chromeOpenCheck.ExitCode); output=$($chromeOpenCheck.Text)"
}

Write-Host ""
$checks | Format-Table -AutoSize -Wrap

Write-SmokeSummary -Checks ($checks.ToArray())

$failures = @($checks | Where-Object { $_.Status -eq "FAIL" })
$warnings = @($checks | Where-Object { $_.Status -eq "WARN" })

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Yukino post-install Browser smoke failed: $($failures.Count) failure(s), $($warnings.Count) warning(s)." -ForegroundColor Red
    exit 1
}
elseif ($warnings.Count -gt 0) {
    Write-Host "Yukino post-install Browser smoke passed with $($warnings.Count) warning(s)." -ForegroundColor Yellow
}
else {
    Write-Host "Yukino post-install Browser smoke passed." -ForegroundColor Green
}
