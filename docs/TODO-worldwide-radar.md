# Task: Expand Drizzle to Worldwide Coverage

## Baseline / Return Point

This work happens on branch `mr-worldwide`, forked from `master` at:

- **Commit:** `66b9044e62d23842be0581c2790a62ad8e6089e2` (`66b9044`)
- **Subject:** Add Garmin Connect IQ target (Venu X1 / D2 Mach 2) with self-hosted CI and build script
- **Date:** 2026-06-07
- **Nearest tag:** `v2.3.8` (build 21) at `2117fc9`
- **Baseline tag:** `pre-worldwide` points at `66b9044` for easy return.

To get back to the pre-worldwide state at any time:
`git switch master` (or `git checkout pre-worldwide`). The shipping app is
unchanged on `master`; all worldwide work is isolated on `mr-worldwide`.

---

## What We Actually Are

Before anything else: Drizzle is a single `Assets/radar-map.html` page running
inside a WebView shell on Android, iOS, and Windows. There is no region logic in
the native apps — Android `MainActivity.kt` and iOS `RadarViewController.swift`
are download/cache plumbing and thin bridge wiring. Everything that matters —
URL building, region data, Leaflet map, GIF overlay, geographic calibration — is
JavaScript in that one HTML file. Any change to worldwide coverage is almost
entirely a change to `radar-map.html`.

---

## The Real Opportunity

AccuWeather's Sirocco CDN also serves **satellite Enhanced Infrared (EI) GIFs**
for international regions at a different base path (`sat_mosaic` / `ei` layer)
using the same 640×480 format. This means we can expand the picker to cover the
whole world using the exact same fetch-and-overlay pipeline we already have —
no new platform code, no new dependencies.

The visual difference is intentional and expected:
- **US/Canada Doppler (`nx_mosaic/sir`):** green/yellow/red rain radar with
  the dark basemap users know.
- **International satellite IR (`sat_mosaic/ei`):** cloud-top thermal imagery —
  white/grey cloud masses on a dark ocean/land background. Different look, still
  useful, and clearly labeled so the user isn't confused.

---

## URL Verification Results (tested via HTTP HEAD probes)

Actual probing of `sirocco.accuweather.com` on the `mr-worldwide` branch:

**CONFIRMED REAL (`200 image/gif`):**
- `nx_mosaic_640x480_public/sir/inmasirus_.gif` — US national (existing)
- US states and regional sectors (existing) — the only confirmed coverage.

**FALSE POSITIVE (do not use):**
- `nx_mosaic_640x480_public/sir/inmasircan.gif` returned `200`, but `can` is
  **not Canada** — the sirocco server is case-insensitive and `inmasircan.gif`
  resolves to the existing `inmasirCAn.gif` = **California North (NORCAL)**,
  which the app already has. There is NO Canada radar. Lesson: case-insensitive
  matching makes `200` responses untrustworthy unless the returned image is
  confirmed to be a distinct region.

**CONFIRMED FABRICATED (every variant returned `404`):**
- All of Gemini's `sat_mosaic` / `ei` satellite URLs, across every tested
  path prefix (`sat_mosaic`, `sat_ir`, `ei_mosaic`, `inmosat`, etc.), layer
  (`ei`, `ir`, `sat`, `vis`), and filename pattern (`inmosatei{code}`,
  `inma{code}`, `{code}`, `{code}_`).
- International codes under the known-good radar path (`mex`, `car`, `eur`)
  all 404 — the radar mosaic covers **the US only** (plus US-internal sectors).

**Dead ends for discovery:**
- Blind brute-force: the CDN returns `403` for any directory path and `404`
  for any missing file, and `200` responses can collide with existing US
  region files via case-insensitive matching — no reliable signal.
- Scraping accuweather.com: `403` bot protection blocks scripted fetches.

**The only authoritative way to find real international URLs** is a browser
DevTools Network capture: open AccuWeather's international radar/satellite map
in a real browser, F12 -> Network -> filter `.gif`, let it animate, and copy the
actual requested URLs. Treat those as the source of truth; verify each with a
HEAD probe before adding it to the region index.

**Net:** the genuinely available expansion via sirocco today is North America
(US + Canada). True global satellite depends on capturing real endpoints that
have not yet been confirmed to exist on the public CDN.

---

## (Superseded) Earlier Verification Notes

Gemini produced the endpoint shape and region code list, but it did not actually
test these URLs — and probing proved them wrong (see results above). The list
below is retained only as a starting point for DevTools capture, not as
confirmed URLs:

1. Confirm the sat_mosaic animated GIF URL pattern. Expected shape:
   `https://sirocco.accuweather.com/sat_mosaic_640x480_public/ei/inmosatei{code}.gif`
   — but verify the exact path prefix and filename pattern for a handful of codes
   (`car`, `eur`, `asia`, `aus`) by curling or opening them in a browser.

2. Confirm which codes are real and which 404. The list from Gemini is a good
   starting point but treat every code as unverified until tested:
   `namer`, `mex`, `camer`, `car`, `hatl`, `epac`, `samer`, `samn`, `sams`,
   `eur`, `eurw`, `eure`, `uk`, `scan`, `afr`, `afrn`, `afrs`, `mide`,
   `asia`, `asiae`, `asias`, `seasia`, `aus`, `spac`, `wpac`.
   Also check `can` for a Doppler radar variant (it may exist under `nx_mosaic`).

3. For each confirmed URL, note the **geographic bounding box** of the image
   (what lat/lng extent does the 640×480 frame actually cover?). This is the
   single hardest part — see calibration section below.

---

## The Calibration Problem (The Real Work)

The current app doesn't just slap a GIF on the screen. It overlays the GIF onto
a Leaflet map using precise calibration parameters so state/country polygon
outlines line up with what's in the image. For US regions this involved
per-region LCC projection parameters (`lat_0`, `lon_0`, `lat_1`, `lat_2`,
`rotation`, `left`, `right`, `top`, `bottom`) that were tuned by hand.

For international satellite GIFs:
- The projection will be different (satellite IR is typically a fixed-grid
  projection, not LCC).
- Each region has a different geographic extent.
- Getting the polygons to align means either finding AccuWeather's published
  bounding boxes for each frame or tuning them visually the same way the US
  regions were tuned.

**This is the majority of the work** and cannot be automated — it is per-region
calibration. Plan for it taking longer than the URL/picker work combined. The
existing `regionCalibMap` / `_defaultRegionCalib` structure in `radar-map.html`
already supports per-region params; international regions will just get entries
in the same map. The UI for in-app calibration adjustment (via `localStorage`)
is already there too.

A reasonable phased approach:
- Phase 1: Get the URLs and rough bounds. Use `gifBounds` as a simple lat/lng
  rectangle per region (the same `[[minLat, minLng], [maxLat, maxLng]]` already
  used for US). Polygons will be misaligned initially but the image will display.
- Phase 2: Tune calibration per region until country outlines line up.

---

## URL Builder Change (Small)

Currently `resolveRadarUrl(region)` in `radar-map.html` hardcodes the
`nx_mosaic` base and always returns a `sir/inmasir{code}.gif` URL. It needs to
become type-aware:

```js
// Rough sketch — do not treat as final
const SAT_BASE = 'https://sirocco.accuweather.com/sat_mosaic_640x480_public/ei/';

function resolveRadarUrl(region) {
  const entry = RegionIndex[region]; // new unified region lookup
  if (!entry) return null;
  if (entry.type === 'radar') {
	if (RegionFiles[region]) return RADAR_BASE + RegionFiles[region];
	return RADAR_BASE + 'inmasir' + region.toLowerCase() + '_.gif';
  }
  // sat_ei — verify the exact filename pattern against real URLs first
  return SAT_BASE + 'inmosat' + region.toLowerCase() + '.gif';
}
```

The Android URL whitelist in `MainActivity.kt` currently only allows
`https://sirocco.accuweather.com/`. The `sat_mosaic` path is on the same
hostname, so the whitelist check passes unchanged — verify this when testing.

---

## Region Data Structure

Replace/extend the existing flat `RegionKeys` / `RegionFiles` / `StateNames`
constants with a grouped structure. Keep existing US keys exactly as they are —
they are working and calibrated. Add international groups alongside them.

Suggested shape (names and codes subject to URL verification):

```
United States        — type: radar  (all existing state + sector codes, unchanged)
Canada               — type: radar (can), fallback sat_ei
North America Full   — type: sat_ei (namer)
Mexico               — type: sat_ei (mex)
Central America      — type: sat_ei (camer)
Caribbean            — type: sat_ei (car)   ← the one that started this
Atlantic Basin       — type: sat_ei (hatl)
Eastern Pacific      — type: sat_ei (epac)
South America Full   — type: sat_ei (samer)
  Northern SA        — type: sat_ei (samn)
  Southern SA        — type: sat_ei (sams)
Europe Full          — type: sat_ei (eur)
  Western Europe     — type: sat_ei (eurw)
  Eastern Europe     — type: sat_ei (eure)
  UK & Ireland       — type: sat_ei (uk)
  Scandinavia        — type: sat_ei (scan)
Africa Full          — type: sat_ei (afr)
  Northern Africa    — type: sat_ei (afrn)
  Southern Africa    — type: sat_ei (afrs)
Middle East          — type: sat_ei (mide)
Asia Full            — type: sat_ei (asia)
  East Asia          — type: sat_ei (asiae)
  South Asia         — type: sat_ei (asias)
  Southeast Asia     — type: sat_ei (seasia)
Australia & NZ       — type: sat_ei (aus)
South Pacific        — type: sat_ei (spac)
Western Pacific      — type: sat_ei (wpac)
```

Prune any codes that don't return valid GIFs after verification.

---

## UI Changes (Minimal by Design)

The existing toolbar has a single `USA` button that calls `loadUSA()`. That
button becomes a continent/group picker. Everything else stays identical.

**Top toolbar** — replace the `USA` button with a dropdown or modal that shows
the top-level groups (USA, Americas, Europe, Africa & Middle East, Asia &
Oceania). Keep Refresh and Cache buttons unchanged.

**Bottom bar chips** — currently shows the 6 US regional sectors when viewing
USA. When an international group is selected, swap those chips to the sub-regions
of that group (e.g., Europe → Full / West / East / UK / Scan). When a group
has no sub-regions, hide the chip bar or show just "Full".

**Region title** — already shows in `regionTitle` span. Update the text to
include type: `{Name} — Radar` for Doppler, `{Name} — Satellite (IR)` for sat_ei.
This is the primary UX signal for the visual difference.

**No globe-spinning needed** — the Leaflet map already supports free worldwide
pan. When a user selects an international region, `map.flyToBounds()` to that
region's bounds the same way `setRegionRadar()` already does for US sectors.
The "continuous pan" experience is already there; we're just adding more GIF
overlays to land on.

---

## Cache Key

Currently GIFs are cached as `{region}.gif` on disk (e.g., `USA.gif`,
`NORTHEAST.gif`). International codes are short and globally unique so there's
no collision risk. No change needed here unless two regions from different types
happen to share a code — check for that during URL verification.

---

## Steps

1. **Verify URLs** — manually test sat_mosaic GIF URLs for a sample of codes.
   Document which work, which 404, and what the actual filename pattern is.
   Correct the URL template above based on findings.

2. **Document bounds** — for each confirmed international code, record the
   approximate lat/lng bounding box of the GIF frame (the extent AccuWeather
   renders). This can be estimated from the visible geography in the image.

3. **Extend region data** in `radar-map.html` — add the grouped region index
   with verified codes, types, display names, and rough bounds.

4. **Update `resolveRadarUrl`** in `radar-map.html` to be type-aware.

5. **Replace USA toolbar button** with a group picker that loads the top-level
   continent groups. Keep the click-path as short as possible — one tap to
   continent, one tap to sub-region if desired.

6. **Update bottom bar** to swap chips based on selected group.

7. **Update region title** to append `— Radar` or `— Satellite (IR)`.

8. **Add calibration entries** for international regions — start with rough
   `gifBounds` rectangles, then tune `regionCalibMap` params until polygon
   outlines align acceptably. This step repeats per region.

9. **Smoke test on all three platforms** (Windows WebView2, Android, iOS).
   The Android URL whitelist and iOS ATS allow `sirocco.accuweather.com` HTTPS
   already — confirm sat_mosaic falls under the same hostname.

---

## Out of Scope for This Pass

- Garmin — set aside, see `garmin/README.md`.
- watchOS — the watch app (`RadarService.swift`) uses the same region/URL logic;
  international expansion there is a separate follow-up once the HTML side is
  stable.
- Any kind of map tile or basemap change — keep the existing dark Leaflet basemap.
- Per-country drill-down (the way US has per-state GIFs) — international codes
  are coarse regional views only; AccuWeather does not appear to offer
  country-level Doppler equivalents outside North America.
