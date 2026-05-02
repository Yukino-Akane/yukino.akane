param(
    [Parameter(Mandatory = $true)]
    [string]$SourceImage,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [string]$IconPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Drawing

$CornerRadiusRatio = 0.22

function New-Directory([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function New-RoundedRectanglePath([int]$Width, [int]$Height, [float]$Radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = [Math]::Max(1.0, $Radius * 2.0)
    $rect = New-Object System.Drawing.RectangleF(0, 0, ($Width - 1), ($Height - 1))

    $path.AddArc($rect.X, $rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($rect.Right - $diameter), $rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($rect.Right - $diameter), ($rect.Bottom - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($rect.X, ($rect.Bottom - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-CroppedRoundedImage(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Image]$Source,
    [System.Drawing.Rectangle]$Crop,
    [System.Drawing.Rectangle]$Target,
    [float]$Radius
) {
    $path = New-RoundedRectanglePath $Target.Width $Target.Height $Radius
    try {
        $state = $Graphics.Save()
        try {
            $translate = New-Object System.Drawing.Drawing2D.Matrix
            try {
                $translate.Translate($Target.X, $Target.Y)
                $path.Transform($translate)
            }
            finally {
                $translate.Dispose()
            }
            $Graphics.SetClip($path)
            $Graphics.DrawImage($Source, $Target, $Crop, [System.Drawing.GraphicsUnit]::Pixel)
        }
        finally {
            $Graphics.Restore($state)
        }
    }
    finally {
        $path.Dispose()
    }
}

function New-CroppedImage(
    [System.Drawing.Image]$Source,
    [System.Drawing.Rectangle]$Crop,
    [int]$Width,
    [int]$Height,
    [string]$Path
) {
    $bitmap = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $radius = [Math]::Min($Width, $Height) * $CornerRadiusRatio
            Draw-CroppedRoundedImage $graphics $Source $Crop (New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)) $radius
        }
        finally {
            $graphics.Dispose()
        }

        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

function New-FittedImage(
    [System.Drawing.Image]$Source,
    [System.Drawing.Rectangle]$Crop,
    [int]$Width,
    [int]$Height,
    [string]$Path
) {
    $bitmap = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::FromArgb(49, 67, 255))
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            $scale = [Math]::Min($Width / $Crop.Width, $Height / $Crop.Height)
            $targetWidth = [int][Math]::Round($Crop.Width * $scale)
            $targetHeight = [int][Math]::Round($Crop.Height * $scale)
            $targetX = [int][Math]::Round(($Width - $targetWidth) / 2)
            $targetY = [int][Math]::Round(($Height - $targetHeight) / 2)

            $graphics.DrawImage(
                $Source,
                (New-Object System.Drawing.Rectangle($targetX, $targetY, $targetWidth, $targetHeight)),
                $Crop,
                [System.Drawing.GraphicsUnit]::Pixel
            )
        }
        finally {
            $graphics.Dispose()
        }

        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

function Write-UInt16LE([System.IO.Stream]$Stream, [int]$Value) {
    $bytes = [BitConverter]::GetBytes([UInt16]$Value)
    $Stream.Write($bytes, 0, 2)
}

function Write-UInt32LE([System.IO.Stream]$Stream, [int]$Value) {
    $bytes = [BitConverter]::GetBytes([UInt32]$Value)
    $Stream.Write($bytes, 0, 4)
}

function New-CroppedPngBytes(
    [System.Drawing.Image]$Source,
    [System.Drawing.Rectangle]$Crop,
    [int]$Size
) {
    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $radius = $Size * $CornerRadiusRatio
            Draw-CroppedRoundedImage $graphics $Source $Crop (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)) $radius
        }
        finally {
            $graphics.Dispose()
        }

        $memory = New-Object System.IO.MemoryStream
        try {
            $bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
            return $memory.ToArray()
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

function New-IcoFile(
    [System.Drawing.Image]$Source,
    [System.Drawing.Rectangle]$Crop,
    [string]$Path
) {
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $images = @()
    foreach ($size in $sizes) {
        $images += [pscustomobject]@{
            Size = $size
            Bytes = New-CroppedPngBytes $Source $Crop $size
        }
    }

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Directory $parent
    }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        Write-UInt16LE $stream 0
        Write-UInt16LE $stream 1
        Write-UInt16LE $stream $images.Count

        $offset = 6 + (16 * $images.Count)
        foreach ($image in $images) {
            $entrySize = if ($image.Size -eq 256) { 0 } else { $image.Size }
            $stream.WriteByte([byte]$entrySize)
            $stream.WriteByte([byte]$entrySize)
            $stream.WriteByte([byte]0)
            $stream.WriteByte([byte]0)
            Write-UInt16LE $stream 1
            Write-UInt16LE $stream 32
            Write-UInt32LE $stream $image.Bytes.Length
            Write-UInt32LE $stream $offset
            $offset += $image.Bytes.Length
        }

        foreach ($image in $images) {
            $stream.Write($image.Bytes, 0, $image.Bytes.Length)
        }
    }
    finally {
        $stream.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $SourceImage)) {
    throw "Source image not found: $SourceImage"
}

New-Directory $OutputDir

$source = [System.Drawing.Image]::FromFile($SourceImage)
try {
    if ($source.Width -lt 720 -or $source.Height -lt 720) {
        throw "Source image must be at least 720x720 pixels. Actual: $($source.Width)x$($source.Height)."
    }

    # Face-centered crop selected from the user-provided portrait.
    $squareCrop = New-Object System.Drawing.Rectangle(112, 16, 624, 624)
    if ($squareCrop.Right -gt $source.Width -or $squareCrop.Bottom -gt $source.Height) {
        throw "Configured square crop is outside source image bounds."
    }

    New-CroppedImage $source $squareCrop 50 50 (Join-Path $OutputDir "icon.png")
    New-CroppedImage $source $squareCrop 48 48 (Join-Path $OutputDir "LockScreenLogo.scale-200.png")
    New-CroppedImage $source $squareCrop 88 88 (Join-Path $OutputDir "Square44x44Logo.png")
    New-CroppedImage $source $squareCrop 88 88 (Join-Path $OutputDir "Square44x44Logo.scale-200.png")
    New-CroppedImage $source $squareCrop 300 300 (Join-Path $OutputDir "Square150x150Logo.png")
    New-CroppedImage $source $squareCrop 300 300 (Join-Path $OutputDir "Square150x150Logo.scale-200.png")

    foreach ($size in 16, 20, 24, 30, 32, 36, 40, 44, 48, 60, 64, 72, 80, 96, 256) {
        New-CroppedImage $source $squareCrop $size $size (Join-Path $OutputDir ("Square44x44Logo.targetsize-{0}_altform-unplated.png" -f $size))
        New-CroppedImage $source $squareCrop $size $size (Join-Path $OutputDir ("Square44x44Logo.targetsize-{0}_altform-lightunplated.png" -f $size))
    }

    New-FittedImage $source $squareCrop 620 300 (Join-Path $OutputDir "Wide310x150Logo.scale-200.png")
    New-FittedImage $source $squareCrop 1240 600 (Join-Path $OutputDir "SplashScreen.scale-200.png")

    if ($IconPath) {
        New-IcoFile $source $squareCrop $IconPath
    }
}
finally {
    $source.Dispose()
}
