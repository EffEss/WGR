# Drizzle for Garmin Venu X1 and D2 Mach 2

This is a standalone Garmin Connect IQ watch app target for the Venu X1 and D2
Mach 2. It is kept outside the Windows, Android, and iOS build systems so those
existing targets do not pick up any Garmin files.

## What It Ports

- Uses the same 640 x 480 AccuWeather Sirocco radar GIF endpoints as Windows, Android,
  iOS, and watchOS.
- Targets the Venu X1 Connect IQ device id `venux1`.
- Targets the D2 Mach 2 Connect IQ device id `d2mach2`.
- Scales radar images for the Venu X1's 448 x 486 rectangular AMOLED screen.
- Adapts the radar viewport for the D2 Mach 2's 454 x 454 round AMOLED screen.
- Supports tap-to-zoom on the current radar view, with drag, swipe, and
  directional-button panning while zoomed.
- Supports an optional local GIF frame converter for six-frame radar animation.
- Provides native Connect IQ menu selection for USA, regional, and state radar.
- Enables the Venu X1 action-menu indicator for radar-level selection.
- Mirrors the watchOS state redirect and region fallback behavior.
- Keeps an in-memory five-minute radar cache while the app is running.

The Garmin app uses the 640 x 480 Sirocco GIF feed and Garmin image requests for
radar display. The zoomed view scales the decoded frame to 2x and pans locally
instead of reloading the same image. The app loads the normal static radar first,
then tries to upgrade to the six-frame animation in the background. Connect IQ
does not expose raw GIF bytes to apps, and Garmin's native animation downloader
expects Garmin's own animation content type rather than ordinary GIFs. For
animation testing, the local converter serves the six GIF frames as PNG images
and the watch loops them at 500 ms for frames 1-5 and 2000 ms for frame 6.

## Local Animation Converter

The build points at `http://localhost:8798/frame/` by default. Set
`FRAME_CONVERTER_BASE` in `source/DrizzleData.mc` to the host running the converter
on your network.

```sh
python garmin/converter/drizzle_gif_converter.py --host 0.0.0.0 --port 8798
```

The converter caches each radar GIF for five minutes and exposes frame URLs like
`/frame/USA/0.png` through `/frame/USA/5.png`.

If the watch never animates but static radar still loads, the most likely causes
are a firewall blocking inbound port `8798`, the watch and converter host being on
isolated WiFi networks, or `FRAME_CONVERTER_BASE` pointing at the wrong host.

## Build

Install the Garmin Connect IQ SDK with the SDK Manager (sign in with your Garmin
developer account) and download the `venux1` and `d2mach2` devices. Then build all
artifacts with one command:

```powershell
pwsh garmin/build.ps1
```

This produces, in `garmin/bin/`:

- `Drizzle.iq` — Connect IQ Store bundle (all products)
- `DRZLX1.prg` — Venu X1 side-load
- `DRZLD2.prg` — D2 Mach 2 side-load

The script auto-discovers the SDK (`$env:CIQ_HOME`, the SDK Manager's active SDK,
or the newest installed SDK) and the developer key (`$env:GARMIN_DEV_KEY` or
`garmin/local-dev-key.der`). Override either explicitly:

```powershell
pwsh garmin/build.ps1 -Sdk C:\path\to\sdk -Key C:\keys\developer_key.der
pwsh garmin/build.ps1 -PrgOnly   # skip the .iq store bundle
```

Or invoke `monkeyc` directly:

```sh
cd garmin
monkeyc -e -f monkey.jungle -o bin/Drizzle.iq -y path/to/developer_key.der
monkeyc -f monkey.jungle -o bin/DRZLX1.prg -y path/to/developer_key.der -d venux1
monkeyc -f monkey.jungle -o bin/DRZLD2.prg -y path/to/developer_key.der -d d2mach2
```

Then copy a `.prg` to `GARMIN/APPS` on the device, or run it from the Connect IQ
simulator.

> **License note:** the `venux1`/`d2mach2` device definitions are Garmin
> "Program Materials". The Connect IQ SDK License forbids redistributing or hosting
> them, so they are never committed to this repo — install them through the SDK
> Manager under your own developer account. CI obtains them only from a self-hosted
> runner or the encrypted `GARMIN_CIQ_DEVICES_TGZ_BASE64` secret.

This project has been compiler-verified with Connect IQ Compiler 9.1.0 for both
targets.
