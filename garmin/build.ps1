<#
.SYNOPSIS
	Builds the Drizzle Garmin Connect IQ artifacts (.iq store bundle + per-device .prg).

.DESCRIPTION
	Convenience wrapper around `monkeyc` so a Garmin change can be rebuilt with a
	single command. Auto-discovers the Connect IQ SDK and developer key, verifies
	the required device definitions are installed, then compiles:
	  - bin/Drizzle.iq   (Connect IQ Store bundle, all products, via -e)
	  - bin/DRZLX1.prg   (Venu X1 side-load)
	  - bin/DRZLD2.prg   (D2 Mach 2 side-load)

	Device definitions (venux1, d2mach2) are Garmin "Program Materials": they are
	NOT redistributed in this repo. Install them through the Connect IQ SDK Manager
	under your own Garmin developer account; this script only reads them locally.

.PARAMETER Sdk
	Path to a Connect IQ SDK directory (the one containing bin\monkeyc[.bat]).
	Defaults to $env:CIQ_HOME, then the SDK Manager's current SDK, then the newest
	SDK found under %APPDATA%\Garmin\ConnectIQ\Sdks.

.PARAMETER Key
	Path to the developer key (.der). Defaults to $env:GARMIN_DEV_KEY, then
	garmin\local-dev-key.der, then garmin\developer_key.der.

.PARAMETER PrgOnly
	Skip the .iq store bundle and build only the per-device .prg files.

.EXAMPLE
	pwsh garmin\build.ps1

.EXAMPLE
	pwsh garmin\build.ps1 -Key C:\keys\developer_key.der -PrgOnly
#>
[CmdletBinding()]
param(
	[string]$Sdk,
	[string]$Key,
	[switch]$PrgOnly
)

$ErrorActionPreference = "Stop"

$garminDir = $PSScriptRoot
$binDir    = Join-Path $garminDir "bin"
$jungle    = Join-Path $garminDir "monkey.jungle"

# Products to build per device (id -> output .prg name), aligned with manifest.xml.
$devices = [ordered]@{
	"venux1"  = "DRZLX1.prg"
	"d2mach2" = "DRZLD2.prg"
}

function Find-MonkeyC {
	param([string]$SdkHint)

	$candidates = @()
	if ($SdkHint)        { $candidates += $SdkHint }
	if ($env:CIQ_HOME)   { $candidates += $env:CIQ_HOME }

	# SDK Manager records the active SDK here.
	$current = Join-Path $env:APPDATA "Garmin\ConnectIQ\current-sdk.cfg"
	if (Test-Path $current) {
		$candidates += (Get-Content $current -Raw).Trim()
	}

	foreach ($c in $candidates) {
		if (-not $c) { continue }
		foreach ($exe in @("bin\monkeyc.bat", "bin\monkeyc")) {
			$p = Join-Path $c $exe
			if (Test-Path $p) { return (Resolve-Path $p).Path }
		}
	}

	# Fall back to the newest installed SDK.
	$sdkRoot = Join-Path $env:APPDATA "Garmin\ConnectIQ\Sdks"
	if (Test-Path $sdkRoot) {
		$found = Get-ChildItem $sdkRoot -Directory |
			Sort-Object Name -Descending |
			ForEach-Object {
				foreach ($exe in @("bin\monkeyc.bat", "bin\monkeyc")) {
					$p = Join-Path $_.FullName $exe
					if (Test-Path $p) { return $p }
				}
			} | Select-Object -First 1
		if ($found) { return (Resolve-Path $found).Path }
	}

	return $null
}

function Find-Key {
	param([string]$KeyHint)

	$candidates = @(
		$KeyHint,
		$env:GARMIN_DEV_KEY,
		(Join-Path $garminDir "local-dev-key.der"),
		(Join-Path $garminDir "developer_key.der")
	)
	foreach ($c in $candidates) {
		if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
	}
	return $null
}

# ── Resolve toolchain ────────────────────────────────────────────
$monkeyc = Find-MonkeyC -SdkHint $Sdk
if (-not $monkeyc) {
	Write-Error @"
Could not locate monkeyc. Install the Connect IQ SDK via the SDK Manager, then
either pass -Sdk <path-to-sdk>, set `$env:CIQ_HOME, or select an active SDK in the
SDK Manager. (Looked under %APPDATA%\Garmin\ConnectIQ\Sdks.)
"@
	exit 1
}
Write-Host "monkeyc : $monkeyc" -ForegroundColor Cyan

$keyPath = Find-Key -KeyHint $Key
if (-not $keyPath) {
	Write-Error @"
Could not locate a developer key (.der). Generate one with the SDK or VS Code
Monkey C extension, then pass -Key <path>, set `$env:GARMIN_DEV_KEY, or place it at
garmin\local-dev-key.der. The key is git-ignored and must never be committed.
"@
	exit 1
}
Write-Host "key     : $keyPath" -ForegroundColor Cyan

# ── Verify device definitions are installed (not redistributed) ──
$devRoot = Join-Path $env:APPDATA "Garmin\ConnectIQ\Devices"
$missing = @()
foreach ($id in $devices.Keys) {
	if (-not (Test-Path (Join-Path $devRoot $id))) { $missing += $id }
}
if ($missing.Count -gt 0) {
	Write-Error @"
Missing Connect IQ device definition(s): $($missing -join ', ').
Open the Connect IQ SDK Manager, sign in with your Garmin developer account, and
download these devices. They are Garmin Program Materials and are intentionally not
included in this repository.
"@
	exit 1
}
Write-Host "devices : $($devices.Keys -join ', ')" -ForegroundColor Cyan

# ── Build ────────────────────────────────────────────────────────
$null = New-Item $binDir -ItemType Directory -Force
Push-Location $garminDir
try {
	if (-not $PrgOnly) {
		$iqOut = Join-Path $binDir "Drizzle.iq"
		Write-Host "`n=== Building store bundle: $iqOut ===" -ForegroundColor Green
		& $monkeyc -e -f $jungle -o $iqOut -y $keyPath
		if ($LASTEXITCODE -ne 0) { throw "monkeyc failed building Drizzle.iq (exit $LASTEXITCODE)" }
	}

	foreach ($id in $devices.Keys) {
		$prgOut = Join-Path $binDir $devices[$id]
		Write-Host "`n=== Building $id -> $prgOut ===" -ForegroundColor Green
		& $monkeyc -f $jungle -o $prgOut -y $keyPath -d $id
		if ($LASTEXITCODE -ne 0) { throw "monkeyc failed building $($devices[$id]) for $id (exit $LASTEXITCODE)" }
	}
}
finally {
	Pop-Location
}

Write-Host "`nBuild complete. Artifacts in $binDir" -ForegroundColor Cyan
Get-ChildItem $binDir -Filter "*.iq"  -ErrorAction SilentlyContinue | Select-Object Name, Length
Get-ChildItem $binDir -Filter "*.prg" -ErrorAction SilentlyContinue | Select-Object Name, Length
