# Generates icon.ico for the Zerto Compliance Launcher (lion crest theme)
# Uses only System.Drawing so customers can regenerate without extra tools

Add-Type -AssemblyName System.Drawing

function New-RoundedRectPath {
    param(
        [System.Drawing.RectangleF]$Rect,
        [float]$Radius = 16
    )
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2
    $arc = New-Object System.Drawing.RectangleF $Rect.X, $Rect.Y, $diameter, $diameter

    $path.AddArc($arc, 180, 90)
    $arc.X = $Rect.Right - $diameter
    $path.AddArc($arc, 270, 90)
    $arc.Y = $Rect.Bottom - $diameter
    $path.AddArc($arc, 0, 90)
    $arc.X = $Rect.X
    $path.AddArc($arc, 90, 90)
    $path.CloseFigure()
    return $path
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$iconPath = Join-Path $scriptDir "icon.ico"

$size = 256
$bmp = New-Object System.Drawing.Bitmap -ArgumentList @($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$bgColor = [System.Drawing.Color]::FromArgb(12,27,42)
$shieldDark = [System.Drawing.Color]::FromArgb(15,36,53)
$shieldStroke = [System.Drawing.Color]::FromArgb(23,59,82)
$accentStart = [System.Drawing.Color]::FromArgb(28,210,163)
$accentEnd = [System.Drawing.Color]::FromArgb(21,114,232)
$checkColor = [System.Drawing.Color]::FromArgb(127,242,210)

# Background with soft corners
$g.Clear([System.Drawing.Color]::FromArgb(0,0,0,0))
$bgRect = New-Object System.Drawing.RectangleF 4, 4, 248, 248
$bgPath = New-RoundedRectPath -Rect $bgRect -Radius 32
$bgBrush = New-Object System.Drawing.SolidBrush $bgColor
$g.FillPath($bgBrush, $bgPath)

# Shield
$shieldPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$shieldPath.AddLine(128, 40, 200, 70)
$shieldPath.AddLine(200, 70, 200, 138)
$shieldPath.AddLine(200, 138, 128, 220)
$shieldPath.AddLine(128, 220, 56, 138)
$shieldPath.AddLine(56, 138, 56, 70)
$shieldPath.CloseFigure()

$shieldBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @([System.Drawing.RectangleF]::new(72, 60, 112, 160), $shieldDark, ([System.Drawing.Color]::FromArgb(20,44,64)), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$shieldPen = New-Object System.Drawing.Pen $shieldStroke, 4
$shieldPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.FillPath($shieldBrush, $shieldPath)
$g.DrawPath($shieldPen, $shieldPath)

# Lion silhouette (simplified crest shape)
$lionPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$lionPath.AddBezier(112, 132, 116, 104, 140, 92, 160, 102)
$lionPath.AddBezier(160, 102, 182, 114, 186, 140, 178, 158)
$lionPath.AddBezier(178, 158, 170, 178, 150, 190, 130, 186)
$lionPath.AddBezier(130, 186, 112, 182, 100, 162, 104, 140)
$lionPath.CloseFigure()

$lionBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @([System.Drawing.RectangleF]::new(96, 96, 96, 104), $accentStart, $accentEnd, [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
$g.FillPath($lionBrush, $lionPath)

# Eye highlight
$eyeBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230,255,255))
$g.FillEllipse($eyeBrush, 152, 132, 6, 6)

# Check mark accent
$checkPen = New-Object System.Drawing.Pen $checkColor, 10
$checkPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$checkPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$checkPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.DrawLines($checkPen, @([System.Drawing.PointF]::new(110,156), [System.Drawing.PointF]::new(134,180), [System.Drawing.PointF]::new(178,132)))

# Save to .ico
$hIcon = $bmp.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($hIcon)
$fileStream = [System.IO.File]::Create($iconPath)
try {
    $icon.Save($fileStream)
}
finally {
    $fileStream.Dispose()
    $icon.Dispose()
    $g.Dispose()
    $bmp.Dispose()
}

Write-Host "Icon generated at: $iconPath" -ForegroundColor Green
