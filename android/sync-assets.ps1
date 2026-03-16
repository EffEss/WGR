# android/sync-assets.ps1 — Copies shared Assets into the Android project
# Run from repo root: .\android\sync-assets.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dest = "$PSScriptRoot\app\src\main\assets"

if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

Copy-Item "$root\Assets\radar-map.html" "$dest\radar-map.html" -Force
Copy-Item "$root\Assets\us-states.geo.json" "$dest\us-states.geo.json" -Force

# Generate foreground icon PNGs for Android adaptive icon
$src = "$root\Assets\1024a.png"
if (Test-Path $src) {
    python -c @"
from PIL import Image
src = Image.open(r'$src').convert('RGBA')
sizes = {'xxxhdpi':192, 'xxhdpi':144, 'xhdpi':96, 'hdpi':72, 'mdpi':48}
import os
for dpi, s in sizes.items():
    d = os.path.join(r'$PSScriptRoot', 'app', 'src', 'main', 'res', f'mipmap-{dpi}')
    os.makedirs(d, exist_ok=True)
    src.resize((s, s), Image.LANCZOS).save(os.path.join(d, 'ic_launcher_foreground.png'))
    print(f'  {dpi}: {s}x{s}')
print('Icons generated.')
"@
}

Write-Host "Assets synced to android/app/src/main/assets/"
