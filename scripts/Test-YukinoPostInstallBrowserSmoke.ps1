param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$PackageName = "yukino.akane",
    [int]$RecentLogFileCount = 12,
    [datetime]$MinLogTime = [datetime]::MinValue,
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

function Test-YukinoProcessPath([string]$Path, [string]$InstallLocation) {
    if (-not $Path) {
        return $false
    }
    return $Path -like "$InstallLocation*"
}

Write-Host ""
Write-Host "Yukino post-install Browser smoke" -ForegroundColor Cyan
Write-Host "ProjectRoot: $ProjectRoot"
Write-Host "Package    : $PackageName"
if ($MinLogTime -ne [datetime]::MinValue) {
    Write-Host "MinLogTime : $($MinLogTime.ToString('o'))"
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
        Add-Check "node-repl-yukino-runtime" "FAIL" "No live Yukino node_repl.exe runtime found."
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

    $browserPipeLog = Find-FirstLogMatch -Files $logStatus.Files -Pattern "browser-use native pipe listening"
    if ($browserPipeLog) {
        Add-Check "browser-use-native-pipe-server" "PASS" $browserPipeLog
    }
    else {
        Add-Check "browser-use-native-pipe-server" "FAIL" "No browser-use native pipe listening marker in latest $RecentLogFileCount log file(s)."
    }

    $runtimePathLog = Find-FirstLogMatch -Files $logStatus.Files -Pattern "BrowserUseThreadConfig.*OpenAI\\Yukino\\bin\\node_repl\.exe"
    if ($runtimePathLog) {
        Add-Check "browser-runtime-yukino-path-log" "PASS" $runtimePathLog
    }
    else {
        Add-Check "browser-runtime-yukino-path-log" "FAIL" "No BrowserUseThreadConfig marker selecting the Yukino node_repl runtime."
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
