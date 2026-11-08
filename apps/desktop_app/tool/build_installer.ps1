<#
.SYNOPSIS
    Compila J-SCAN para Windows y genera el instalador con Inno Setup.

.DESCRIPTION
    Por defecto ejecuta `flutter build windows --release`, lee la versión de
    pubspec.yaml y compila installer\jscan.iss con ISCC.exe.

.PARAMETER SkipBuild
    Reutiliza el build existente en build\windows\x64\runner\Release.

.PARAMETER NoTestInstall
    Omite la instalación silenciosa de verificación en una carpeta temporal.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File apps\desktop_app\tool\build_installer.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File apps\desktop_app\tool\build_installer.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$NoTestInstall
)

$ErrorActionPreference = 'Stop'

$appRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $appRoot)
$releaseDir = Join-Path $appRoot 'build\windows\x64\runner\Release'
$issFile = Join-Path $appRoot 'installer\jscan.iss'
$outputDir = Join-Path $appRoot 'build\installer'

function Resolve-Iscc {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw 'No se encontró Inno Setup 6 (ISCC.exe). Instálalo desde https://jrsoftware.org/isinfo.php o con: winget install JRSoftware.InnoSetup'
}

function Get-AppVersion {
    $pubspec = Get-Content -LiteralPath (Join-Path $appRoot 'pubspec.yaml') -Raw
    $match = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?')
    if (-not $match.Success) {
        throw 'No se pudo leer la versión desde pubspec.yaml'
    }
    return @{
        Version = $match.Groups[1].Value
        Build   = if ($match.Groups[2].Success) { $match.Groups[2].Value } else { '1' }
    }
}

$appVersion = Get-AppVersion

if (-not $SkipBuild) {
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutter) {
        throw 'Flutter no está en PATH. Agrega <flutter>\bin al PATH o usa -SkipBuild.'
    }
    Write-Host "Compilando J-SCAN $($appVersion.Version) para Windows..." -ForegroundColor Cyan
    Push-Location $appRoot
    try {
        & $flutter.Source build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build windows falló con código $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'desktop_app.exe'))) {
    throw "No existe $releaseDir\desktop_app.exe. Ejecuta sin -SkipBuild para compilar primero."
}

$iscc = Resolve-Iscc
Write-Host "Generando instalador con $iscc..." -ForegroundColor Cyan

& $iscc `
    "/DMyAppVersion=$($appVersion.Version)" `
    "/DMyAppBuild=$($appVersion.Build)" `
    "/DSourceDir=$releaseDir" `
    $issFile

if ($LASTEXITCODE -ne 0) {
    throw "ISCC falló con código $LASTEXITCODE"
}

$setup = Join-Path $outputDir "JScan-Setup-$($appVersion.Version).exe"
if (-not (Test-Path -LiteralPath $setup)) {
    throw "El instalador no se generó en $setup"
}

$sizeMb = [math]::Round((Get-Item -LiteralPath $setup).Length / 1MB, 1)
Write-Host "Instalador listo: $setup ($sizeMb MB)" -ForegroundColor Green

if (-not $NoTestInstall) {
    $testDir = Join-Path $env:TEMP ("jscan_install_test_" + [guid]::NewGuid().ToString('N'))
    Write-Host "Verificando instalación silenciosa en $testDir..." -ForegroundColor Cyan
    try {
        $install = Start-Process -FilePath $setup -ArgumentList @(
            '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER',
            "/DIR=$testDir"
        ) -Wait -PassThru
        if ($install.ExitCode -ne 0) {
            throw "La instalación de prueba falló con código $($install.ExitCode)"
        }

        $installedExe = Join-Path $testDir 'desktop_app.exe'
        $installedData = Join-Path $testDir 'data\flutter_assets\AssetManifest.bin'
        if (-not (Test-Path -LiteralPath $installedExe)) {
            throw "Falta $installedExe tras la instalación"
        }
        if (-not (Test-Path -LiteralPath $installedData)) {
            throw "Faltan los datos de Flutter en $testDir\data"
        }

        $uninstaller = Join-Path $testDir 'unins000.exe'
        if (Test-Path -LiteralPath $uninstaller) {
            $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @(
                '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
            ) -Wait -PassThru
            if ($uninstall.ExitCode -ne 0) {
                Write-Warning "El desinstalador devolvió código $($uninstall.ExitCode)"
            }
        }
        Write-Host 'Instalación y desinstalación de prueba correctas.' -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $testDir) {
            Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ''
Write-Host 'Distribución:' -ForegroundColor Cyan
Write-Host "  Instalador: $setup"
Write-Host "  Portable:   $releaseDir"
Write-Host "  Repo:       $repoRoot"
