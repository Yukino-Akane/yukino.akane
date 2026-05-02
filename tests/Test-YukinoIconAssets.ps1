param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script = Join-Path $ProjectRoot "scripts\New-YukinoIconAssets.ps1"
$source = Join-Path $ProjectRoot "assets\yukino-icon-source.jpg"
$output = Join-Path ([IO.Path]::GetTempPath()) ("yukino-icon-test-" + [guid]::NewGuid().ToString("N"))
$iconPath = Join-Path $output "icon.ico"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ImageSize([string]$Path, [int]$ExpectedWidth, [int]$ExpectedHeight) {
    Assert-True (Test-Path -LiteralPath $Path) "Missing generated icon asset: $Path"
    $image = [System.Drawing.Image]::FromFile($Path)
    try {
        Assert-True ($image.Width -eq $ExpectedWidth) "Expected $Path width $ExpectedWidth, got $($image.Width)."
        Assert-True ($image.Height -eq $ExpectedHeight) "Expected $Path height $ExpectedHeight, got $($image.Height)."
    }
    finally {
        $image.Dispose()
    }
}

function Assert-FileSha256([string]$Path, [string]$ExpectedHash, [string]$Message) {
    Assert-True (Test-Path -LiteralPath $Path) "Missing file for hash check: $Path"
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    Assert-True ($actualHash -eq $ExpectedHash) "$Message Expected SHA256 $ExpectedHash, got $actualHash."
}

function Assert-SelectedCrop([string]$ScriptPath) {
    $scriptText = [IO.File]::ReadAllText($ScriptPath)
    $selectedCrop = 'New-Object System.Drawing.Rectangle(112, 16, 624, 624)'
    Assert-True $scriptText.Contains($selectedCrop) "Expected Yukino icon crop to use selected face-centered crop: $selectedCrop"
}

function Assert-RoundedIconAlpha([string]$Path) {
    Assert-True (Test-Path -LiteralPath $Path) "Missing generated icon asset: $Path"
    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $corners = @(
            $bitmap.GetPixel(0, 0).A,
            $bitmap.GetPixel(($bitmap.Width - 1), 0).A,
            $bitmap.GetPixel(0, ($bitmap.Height - 1)).A,
            $bitmap.GetPixel(($bitmap.Width - 1), ($bitmap.Height - 1)).A
        )
        foreach ($alpha in $corners) {
            Assert-True ($alpha -eq 0) "Expected transparent rounded corner in $Path, got alpha $alpha."
        }

        $centerAlpha = $bitmap.GetPixel([int]($bitmap.Width / 2), [int]($bitmap.Height / 2)).A
        Assert-True ($centerAlpha -gt 240) "Expected opaque icon center in $Path, got alpha $centerAlpha."
    }
    finally {
        $bitmap.Dispose()
    }
}

Add-Type -AssemblyName System.Drawing

try {
    Assert-True (Test-Path -LiteralPath $script) "Missing icon asset generator: $script"
    Assert-True (Test-Path -LiteralPath $source) "Missing Yukino icon source image: $source"
    Assert-FileSha256 $source "AAC072723648FB7138599F63486EC5F2D695E34E15F0A6D7C97C9F67F88F02C2" "Yukino icon source should be the user-selected 141901688_p3.jpg."
    Assert-SelectedCrop $script

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -SourceImage $source -OutputDir $output -IconPath $iconPath
    if ($LASTEXITCODE -ne 0) {
        throw "Icon asset generator exited with code $LASTEXITCODE."
    }

    Assert-ImageSize (Join-Path $output "icon.png") 50 50
    Assert-ImageSize (Join-Path $output "LockScreenLogo.scale-200.png") 48 48
    Assert-ImageSize (Join-Path $output "Square44x44Logo.png") 88 88
    Assert-ImageSize (Join-Path $output "Square44x44Logo.scale-200.png") 88 88
    Assert-ImageSize (Join-Path $output "Square150x150Logo.png") 300 300
    Assert-ImageSize (Join-Path $output "Square150x150Logo.scale-200.png") 300 300
    Assert-ImageSize (Join-Path $output "Wide310x150Logo.scale-200.png") 620 300
    Assert-ImageSize (Join-Path $output "SplashScreen.scale-200.png") 1240 600
    Assert-RoundedIconAlpha (Join-Path $output "icon.png")
    Assert-RoundedIconAlpha (Join-Path $output "Square44x44Logo.png")
    Assert-RoundedIconAlpha (Join-Path $output "Square150x150Logo.png")
    Assert-RoundedIconAlpha (Join-Path $output "Square44x44Logo.targetsize-256_altform-unplated.png")
    Assert-True (Test-Path -LiteralPath $iconPath) "Missing generated Electron icon: $iconPath"
    $iconBytes = [IO.File]::ReadAllBytes($iconPath)
    Assert-True ($iconBytes.Length -gt 1000) "Generated icon.ico is unexpectedly small."
    Assert-True ($iconBytes[0] -eq 0 -and $iconBytes[1] -eq 0 -and $iconBytes[2] -eq 1 -and $iconBytes[3] -eq 0) "Generated icon.ico has an invalid ICO header."

    foreach ($size in 16, 20, 24, 30, 32, 36, 40, 44, 48, 60, 64, 72, 80, 96, 256) {
        foreach ($form in "unplated", "lightunplated") {
            Assert-ImageSize (Join-Path $output ("Square44x44Logo.targetsize-{0}_altform-{1}.png" -f $size, $form)) $size $size
        }
    }

    Write-Host "Yukino icon asset test passed."
}
finally {
    if (Test-Path -LiteralPath $output) {
        Remove-Item -LiteralPath $output -Recurse -Force
    }
}
