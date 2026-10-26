$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$source = [System.Drawing.Image]::FromFile((Join-Path $root 'assets/brand/walkabout-app-icon.png'))

function Write-Icon([string]$relativePath, [int]$size) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, $size, $size))
        $path = Join-Path $root $relativePath
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $check = [System.Drawing.Image]::FromFile($path)
        try {
            if ($check.Width -ne $size -or $check.Height -ne $size) { throw "Invalid icon dimensions: $relativePath" }
        } finally { $check.Dispose() }
        Write-Host "$relativePath : ${size}x${size}"
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    if ($source.Width -ne $source.Height) { throw 'Launcher artwork must be square.' }
    $densities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
    foreach ($density in $densities.Keys) {
        Write-Icon "android/app/src/main/res/mipmap-$density/ic_launcher.png" $densities[$density]
    }
    $catalog = Get-Content -Raw (Join-Path $root 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json') | ConvertFrom-Json
    foreach ($entry in $catalog.images | Sort-Object filename -Unique) {
        $points = [double]::Parse($entry.size.Split('x')[0], [System.Globalization.CultureInfo]::InvariantCulture)
        $scale = [int]$entry.scale.TrimEnd('x')
        Write-Icon "ios/Runner/Assets.xcassets/AppIcon.appiconset/$($entry.filename)" ([int]($points * $scale))
    }
} finally { $source.Dispose() }
