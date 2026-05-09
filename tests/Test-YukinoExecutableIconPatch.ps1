param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$generator = Join-Path $ProjectRoot "scripts\New-YukinoIconAssets.ps1"
$patcher = Join-Path $ProjectRoot "scripts\Set-YukinoExecutableIcon.ps1"
$source = Join-Path $ProjectRoot "assets\yukino-icon-source.jpg"
$output = Join-Path ([IO.Path]::GetTempPath()) ("yukino-exe-icon-test-" + [guid]::NewGuid().ToString("N"))
$iconPath = Join-Path $output "icon.ico"
$exePath = Join-Path $output "YukinoIconProbe.exe"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
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

function Get-PngBitmapSha256([string]$Path) {
    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        return Get-BitmapPixelSha256 $bitmap
    }
    finally {
        $bitmap.Dispose()
    }
}

function Get-AssociatedIconBitmapSha256([string]$Path) {
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
    Assert-True ($null -ne $icon) "No associated icon found for $Path"
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

Add-Type -AssemblyName System.Drawing

try {
    Assert-True (Test-Path -LiteralPath $generator) "Missing icon asset generator: $generator"
    Assert-True (Test-Path -LiteralPath $patcher) "Missing executable icon patcher: $patcher"
    Assert-True (Test-Path -LiteralPath $source) "Missing Yukino icon source image: $source"

    New-Item -ItemType Directory -Path $output -Force | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $generator -SourceImage $source -OutputDir $output -IconPath $iconPath
    if ($LASTEXITCODE -ne 0) {
        throw "Icon asset generator exited with code $LASTEXITCODE."
    }

    $typeDefinition = @"
using System;
public static class Program
{
    public static void Main(string[] args) { }
}
"@
    Add-Type -TypeDefinition $typeDefinition -OutputAssembly $exePath -OutputType ConsoleApplication
    Assert-True (Test-Path -LiteralPath $exePath) "Failed to create icon probe executable: $exePath"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $patcher -ExePath $exePath -IconPath $iconPath
    if ($LASTEXITCODE -ne 0) {
        throw "Executable icon patcher exited with code $LASTEXITCODE."
    }

    $expectedPng = Join-Path $output "Square44x44Logo.targetsize-32_altform-unplated.png"
    Assert-True (Test-Path -LiteralPath $expectedPng) "Missing generated 32px executable icon reference: $expectedPng"
    $expectedHash = Get-PngBitmapSha256 $expectedPng
    $actualHash = Get-AssociatedIconBitmapSha256 $exePath
    Assert-True ($actualHash -eq $expectedHash) "Executable associated icon should match generated Yukino icon. Expected $expectedHash, got $actualHash."

    Write-Host "Yukino executable icon patch test passed."
}
finally {
    if (Test-Path -LiteralPath $output) {
        Remove-Item -LiteralPath $output -Recurse -Force
    }
}
