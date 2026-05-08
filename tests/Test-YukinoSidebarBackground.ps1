param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$buildScript = Join-Path $ProjectRoot "build-yukino.ps1"
$verifyScript = Join-Path $ProjectRoot "verify-yukino.ps1"
$background = Join-Path $ProjectRoot "assets\yukino-sidebar-background.png"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-FileSha256([string]$Path, [string]$ExpectedHash, [string]$Message) {
    Assert-True (Test-Path -LiteralPath $Path) "Missing file for hash check: $Path"
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    Assert-True ($actualHash -eq $ExpectedHash) "$Message Expected SHA256 $ExpectedHash, got $actualHash."
}

Assert-True (Test-Path -LiteralPath $buildScript) "Missing build script: $buildScript"
Assert-True (Test-Path -LiteralPath $verifyScript) "Missing verify script: $verifyScript"
Assert-FileSha256 $background "8C9C04205C9DD6C7D1CADAD316E14E55F66CED62D9C57A2CE84EDFE9BDE4B63D" "Yukino sidebar background should be the user-selected 142378756_p0.png."

$scriptText = [IO.File]::ReadAllText($buildScript)
Assert-True $scriptText.Contains("Patch-WebviewSidebarBackground") "Build script should include the sidebar background patch function."
Assert-True $scriptText.Contains("yukino-sidebar-background.png") "Build script should copy the sidebar background asset into the webview bundle."
Assert-True $scriptText.Contains('app-main-*.css') "Build script should support the current app-main CSS bundle used by newer Codex Desktop builds."
Assert-True $scriptText.Contains("--yukino-sidebar-background-image") "Build script should inject a CSS variable for the sidebar background image."
Assert-True (-not $scriptText.Contains("background-size: var(--yukino-sidebar-background-width) 100%, var(--yukino-sidebar-background-width) 100%;")) "Sidebar background image must not be forced into the sidebar dimensions; that distorts the portrait image."
Assert-True (-not $scriptText.Contains("background-size: var(--yukino-sidebar-background-width) 100%, cover;")) "Sidebar background image must not use full-window cover; that crops the portrait down to a small slice in the rail."
Assert-True $scriptText.Contains("--yukino-sidebar-portrait-half-width: 42.105263vh;") "Build script should know the portrait's half-width at full viewport height."
Assert-True $scriptText.Contains("background-position: left top, calc(var(--yukino-sidebar-background-half-width) - var(--yukino-sidebar-portrait-half-width)) center;") "Sidebar background should center the full-height portrait inside the sidebar rail."
Assert-True $scriptText.Contains("background-size: var(--yukino-sidebar-background-width) 100%, auto 100vh;") "Sidebar background image should keep its aspect ratio at full viewport height."
Assert-True $scriptText.Contains(".main-surface") "Build script should keep the main conversation surface visually separate from the sidebar image."

$verifyText = [IO.File]::ReadAllText($verifyScript)
Assert-True $verifyText.Contains("sidebar-background-patch") "Verify script should report whether the sidebar background patch is present."
Assert-True $verifyText.Contains("yukino-sidebar-background.png") "Verify script should check that the sidebar background asset exists in the build output."
Assert-True $verifyText.Contains("installed-sidebar-background-patch") "Verify script should report whether the installed package has the sidebar background patch."
Assert-True $verifyText.Contains("Sidebar background CSS does not preserve the image aspect ratio") "Verify script should reject distorted sidebar background sizing in build output."
Assert-True $verifyText.Contains("Installed sidebar background CSS does not preserve the image aspect ratio") "Verify script should reject distorted sidebar background sizing in the installed package."
Assert-True $verifyText.Contains("background-size: var(--yukino-sidebar-background-width) 100%, auto 100vh;") "Verify script should require the sidebar-bounded portrait sizing in build output."
Assert-True $verifyText.Contains("background-position: left top, calc(var(--yukino-sidebar-background-half-width) - var(--yukino-sidebar-portrait-half-width)) center;") "Verify script should require sidebar-centered portrait framing."

Write-Host "Yukino sidebar background test passed."
