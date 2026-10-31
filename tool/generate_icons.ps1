# Genera el icono de la bandeja y el icono de la app de Windows.
# Uso: powershell -ExecutionPolicy Bypass -File tool/generate_icons.ps1
param(
  [string]$OutputDir = "$PSScriptRoot\..\apps\desktop_app\assets"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

New-Item -ItemType Directory -Force $OutputDir | Out-Null

function New-IconPng {
  param([int]$Size)

  $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
      $rect,
      [System.Drawing.Color]::FromArgb(255, 63, 81, 181),
      [System.Drawing.Color]::FromArgb(255, 0, 172, 193),
      45.0
    )
    $padding = [Math]::Max(1, [int]($Size * 0.04))
    $diameter = $Size - (2 * $padding)
    $graphics.FillEllipse($brush, $padding, $padding, $diameter, $diameter)

    $fontSize = [Math]::Max(8, [int]($Size * 0.55))
    $font = New-Object System.Drawing.Font(
      'Segoe UI',
      $fontSize,
      [System.Drawing.FontStyle]::Bold,
      [System.Drawing.GraphicsUnit]::Pixel
    )
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $graphics.DrawString(
      'J',
      $font,
      [System.Drawing.Brushes]::White,
      (New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)),
      $format
    )

    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    return $stream.ToArray()
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

function Write-Ico {
  param(
    [string]$Path,
    [int[]]$Sizes
  )

  $images = New-Object 'System.Collections.Generic.List[byte[]]'
  foreach ($size in $Sizes) {
    $images.Add([byte[]](New-IconPng -Size $size))
  }

  $stream = New-Object System.IO.MemoryStream
  $writer = New-Object System.IO.BinaryWriter($stream)
  try {
    $writer.Write([uint16]0)          # reserved
    $writer.Write([uint16]1)          # type: icon
    $writer.Write([uint16]$Sizes.Count)

    $offset = 6 + (16 * $Sizes.Count)
    for ($i = 0; $i -lt $Sizes.Count; $i++) {
      $size = $Sizes[$i]
      $bytes = $images[$i]
      $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
      $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
      $writer.Write([byte]0)          # palette
      $writer.Write([byte]0)          # reserved
      $writer.Write([uint16]1)        # planes
      $writer.Write([uint16]32)       # bpp
      $writer.Write([uint32]$bytes.Length)
      $writer.Write([uint32]$offset)
      $offset += $bytes.Length
    }

    foreach ($bytes in $images) {
      $writer.Write($bytes, 0, $bytes.Length)
    }

    [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

Write-Ico -Path (Join-Path $OutputDir 'tray_icon.ico') -Sizes @(16, 24, 32, 48, 64, 256)

$preview = Join-Path $OutputDir 'app_icon.png'
[System.IO.File]::WriteAllBytes($preview, (New-IconPng -Size 512))

Write-Host "Iconos generados en $OutputDir"
