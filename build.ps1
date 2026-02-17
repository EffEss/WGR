param([string]$Arch = "x64")
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$out  = "$root\out"

# ── Step 1: Get WebView2 SDK ──────────────────────────────────────
$wv2Ver = "1.0.3179.45"
$wv2Dir = "$root\deps\Microsoft.Web.WebView2.$wv2Ver"

if (-not (Test-Path "$wv2Dir\build\native\include\WebView2.h")) {
    Write-Host "Downloading WebView2 SDK..." -ForegroundColor Cyan
    $null = New-Item "$root\deps" -ItemType Directory -Force
    $nupkg = "$root\deps\webview2.zip"
    Invoke-WebRequest "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$wv2Ver" -OutFile $nupkg
    Expand-Archive $nupkg "$root\deps\Microsoft.Web.WebView2.$wv2Ver" -Force
    Remove-Item $nupkg -Force
    if (-not (Test-Path "$wv2Dir\build\native\include\WebView2.h")) {
        Write-Error "WebView2 SDK download failed."
        exit 1
    }
}

$wv2Inc = "$wv2Dir\build\native\include"
$wv2Lib = "$wv2Dir\build\native\$Arch\WebView2LoaderStatic.lib"

# ── Step 2: Find MSVC ────────────────────────────────────────────
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
if (-not $vsPath) { Write-Error "Visual Studio with C++ not found"; exit 1 }

# Import the VS developer environment
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
$envBlock = cmd /c "`"$vcvars`" $Arch >nul 2>&1 && set" 2>$null
foreach ($line in $envBlock) {
    if ($line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

# ── Step 3: Compile ──────────────────────────────────────────────
Write-Host "=== Compiling WeatherGlance-Lite ($Arch) ===" -ForegroundColor Cyan
$null = New-Item $out -ItemType Directory -Force

# Compile resource (icon)
$resFile = ""
if (Test-Path "$root\radar.ico") {
    rc /nologo /fo "$out\res.res" "$root\WeatherGlance.rc"
    $resFile = "$out\res.res"
} else {
    Write-Host "  No radar.ico found, skipping icon" -ForegroundColor Yellow
}

# Compile + link
$srcFiles = @("$root\main.cpp")
if ($resFile) { $srcFiles += $resFile }
cl /nologo /O1 /GS- /GL /std:c++17 /EHsc `
   /I"$wv2Inc" `
   /Fe"$out\WRG.exe" `
   @srcFiles `
   /link /LTCG /OPT:REF /OPT:ICF /SUBSYSTEM:WINDOWS `
   /MANIFEST:EMBED "/MANIFESTINPUT:$root\app.manifest" `
   "$wv2Lib" user32.lib ole32.lib oleaut32.lib gdi32.lib shell32.lib shlwapi.lib advapi32.lib

if ($LASTEXITCODE -ne 0) { Write-Error "Compilation failed"; exit 1 }

# Clean intermediate files
Remove-Item "$out\*.obj" -Force -EA SilentlyContinue
Remove-Item "$out\res.res" -Force -EA SilentlyContinue

# ── Step 4: Report ───────────────────────────────────────────────
$exe = Get-Item "$out\WRG.exe"

Write-Host ""
Write-Host "  WRG.exe : $([math]::Round($exe.Length/1KB, 1)) KB" -ForegroundColor Green
Write-Host ""

# ── Step 5: Create distributable zip ─────────────────────────────
$zip = "$root\WRG.zip"
Remove-Item $zip -Force -EA SilentlyContinue
Compress-Archive -Path "$out\WRG.exe" -DestinationPath $zip
$zipSize = (Get-Item $zip).Length
Write-Host "  WRG.zip : $([math]::Round($zipSize/1KB, 1)) KB" -ForegroundColor Green

if ($exe.Length -lt 1MB) {
    Write-Host "  ✓ UNDER 1 MB!" -ForegroundColor Green
} else {
    Write-Host "  ✗ Over 1 MB — need further optimization" -ForegroundColor Red
}
