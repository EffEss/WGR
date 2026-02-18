# Drizzle

The best*, smallest weather application ever made.

A single ~400 KB `.exe` that shows live NEXRAD radar for the entire United States — national, regional, and state-level — with no installer, no frameworks, no Electron, and no apologies.

![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows)
![C++17](https://img.shields.io/badge/C%2B%2B-17-00599C?logo=cplusplus)
![Size](https://img.shields.io/badge/exe-~400%20KB-green)

---

## What It Does

Drizzle displays animated radar GIF mosaics

- **Click any state** → loads that state's dedicated radar GIF
- **Click a region button** → loads a multi-state regional composite
- **Click 🌎 USA** → returns to the national radar mosaic
- Large states (California, Texas) are split into sub-regions with click-zone detection

There is no forecast, no temperature, no hourly breakdown. Just radar. That's it.

## Why

Most weather apps ship 100+ MB of runtime to show you a web page. Drizzle does the same thing in under 500 KB

The goal: **how small and self-contained can a useful weather radar viewer be?**

---

## How It Works

| Layer | Technology |
|---|---|
| **Window** | Win32 `WNDCLASSW` + `CreateWindowExW` — no framework |
| **Rendering** | WebView2 (Edge/Chromium, already on Windows 10/11) |
| **Radar source** | AccuWeather `inmasir*.gif` animated mosaics (640×480) |
| **Map projection** | proj4js LCC → CRS.Simple pixel mapping in Leaflet |
| **State boundaries** | Embedded GeoJSON, projected to match each GIF |
| **Assets** | HTML + GeoJSON compiled into the `.exe` as `RCDATA` resources |
| **Downloads** | `URLDownloadToFileW` on background threads, cached to `radar/` |

### Radar Coverage

- **1 national** mosaic (full CONUS)
- **6 regional** composites (NE, NW, NC, SE, SW, SC) with per-region LCC calibrations
- **45+ state** mosaics with per-state scale/offset calibrations
- **5 sub-state** splits (NorCal, CentralCal, SoCal, TX East/South/West)
- States without dedicated GIFs fall back to their containing region

---

## Building

**Prerequisites:** Visual Studio 2022 (or Build Tools) with C++ desktop workload, CMake ≥ 3.20, Ninja.

```powershell
# One-step build (downloads WebView2 SDK automatically)
.\build.ps1
```

Or manually:

```powershell
nuget install Microsoft.Web.WebView2 -Version 1.0.3179.45 -OutputDirectory deps
cmake -B out/build/x64-Release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build out/build/x64-Release
```

The output is a single `Drizzle.exe`.

---

## Project Structure

```
Drizzle/
├── main.cpp              # Win32 host, WebView2 init, download threads
├── WeatherGlance.rc      # Resource script (icon, embedded HTML/JSON)
├── Assets/
│   ├── radar-map.html    # All UI, map, projection, and radar logic
│   └── us-states.geo.json
├── app.manifest          # DPI awareness, common controls
├── radar.ico
├── build.ps1             # One-step build script
└── CMakeLists.txt
```

---

## License

Do whatever you want with it. It's a weather radar viewer.
