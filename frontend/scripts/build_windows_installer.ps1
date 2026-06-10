param(
    [string]$FlutterExe = "flutter",
    [string]$IsccExe = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$pubspec = Get-Content "$root\pubspec.yaml"
$versionLine = $pubspec | Where-Object { $_ -match '^version:\s+' } | Select-Object -First 1
if (-not $versionLine) {
    throw "Impossible de lire la version depuis pubspec.yaml."
}

$version = ($versionLine -replace '^version:\s+', '') -replace '\+.*$', ''

& $FlutterExe build windows --release

if (-not $IsccExe) {
    $candidates = @(
        "ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
    )

    foreach ($candidate in $candidates) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) {
            $resolved = (Get-Command $candidate).Source
            if ($resolved) {
                $IsccExe = $resolved
                break
            }
        } elseif (Test-Path $candidate) {
            $IsccExe = $candidate
            break
        }
    }
}

if (-not $IsccExe) {
    throw "ISCC.exe introuvable. Installe Inno Setup 6 puis relance ce script."
}

& $IsccExe `
    "/DMyAppVersion=$version" `
    "/DMyAppPublisher=Up2School" `
    "/DMyAppName=UY1-Lib" `
    "/DMyAppExeName=up2school.exe" `
    "/DMyAppSourceDir=$root\build\windows\x64\runner\Release" `
    "$root\packaging\windows\up2school.iss"

Write-Host ""
Write-Host "Installateur Windows généré dans build\windows\installer"
