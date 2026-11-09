$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$iconDir = Join-Path $root 'Volna\Resources\Assets.xcassets\AppIcon.appiconset'
New-Item -ItemType Directory -Force -Path $iconDir | Out-Null

$size = 1024
$bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.Clear([System.Drawing.Color]::FromArgb(255, 7, 7, 9))

$rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    [System.Drawing.Color]::FromArgb(255, 24, 7, 12),
    [System.Drawing.Color]::FromArgb(255, 5, 5, 7),
    45.0
)
$graphics.FillRectangle($bgBrush, $rect)

# Soft crimson glow.
for ($i = 10; $i -ge 1; $i--) {
    $alpha = [int](6 + (10 - $i) * 2)
    $radius = 280 + $i * 26
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, 255, 59, 79))
    $graphics.FillEllipse($brush, [int](512 - $radius / 2), [int](540 - $radius / 2), [int]$radius, [int]$radius)
    $brush.Dispose()
}

# Waveform.
function New-WavePath {
    param([double]$BaseY, [double]$Amplitude, [double]$Phase)
    $points = New-Object 'System.Drawing.PointF[]' 180
    for ($i = 0; $i -lt 180; $i++) {
        $x = 110 + ($i / 179.0) * 804
        $taper = [Math]::Sin(($i / 179.0) * [Math]::PI)
        $y = $BaseY + [Math]::Sin(($i / 179.0) * [Math]::PI * 5.2 + $Phase) * $Amplitude * $taper
        $points[$i] = New-Object System.Drawing.PointF([single]$x, [single]$y)
    }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddCurve($points, 0.35)
    return $path
}

$redPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 255, 59, 79), 34)
$redPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$redPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$redPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$redPath = New-WavePath -BaseY 512 -Amplitude 150 -Phase 0.15
$graphics.DrawPath($redPen, $redPath)

$whitePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(245, 255, 247, 244), 20)
$whitePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$whitePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$whitePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$whitePath = New-WavePath -BaseY 512 -Amplitude 92 -Phase 1.2
$graphics.DrawPath($whitePen, $whitePath)

$dimPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 255, 138, 102), 9)
$dimPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$dimPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$dimPath = New-WavePath -BaseY 512 -Amplitude 208 -Phase 2.1
$graphics.DrawPath($dimPen, $dimPath)

# Finish with a subtle bottom highlight.
$highlightBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle(0, 760, 1024, 264)),
    [System.Drawing.Color]::FromArgb(0, 255, 59, 79),
    [System.Drawing.Color]::FromArgb(35, 255, 59, 79),
    90.0
)
$graphics.FillRectangle($highlightBrush, 0, 760, 1024, 264)

$graphics.Dispose()
$iconPath = Join-Path $iconDir 'AppIcon-1024.png'
$bitmap.Save($iconPath, [System.Drawing.Imaging.ImageFormat]::Png)

$sizes = @(
    @{ Name = 'AppIcon-20@2x.png'; Pixels = 40 },
    @{ Name = 'AppIcon-20@3x.png'; Pixels = 60 },
    @{ Name = 'AppIcon-29@2x.png'; Pixels = 58 },
    @{ Name = 'AppIcon-29@3x.png'; Pixels = 87 },
    @{ Name = 'AppIcon-40@2x.png'; Pixels = 80 },
    @{ Name = 'AppIcon-40@3x.png'; Pixels = 120 },
    @{ Name = 'AppIcon-60@2x.png'; Pixels = 120 },
    @{ Name = 'AppIcon-60@3x.png'; Pixels = 180 }
)

foreach ($item in $sizes) {
    $scaled = New-Object System.Drawing.Bitmap($item.Pixels, $item.Pixels, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $context = [System.Drawing.Graphics]::FromImage($scaled)
    $context.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $context.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $context.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $context.DrawImage($bitmap, 0, 0, $item.Pixels, $item.Pixels)
    $context.Dispose()
    $scaled.Save((Join-Path $iconDir $item.Name), [System.Drawing.Imaging.ImageFormat]::Png)
    $scaled.Dispose()
}

$bitmap.Dispose()
Write-Output "Icon generated: $iconPath"
