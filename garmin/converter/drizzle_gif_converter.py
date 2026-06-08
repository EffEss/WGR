#!/usr/bin/env python3
"""Tiny local GIF-to-frame service for Garmin Connect IQ testing."""

from __future__ import annotations

import argparse
import io
import json
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict
from urllib.parse import unquote, urlparse

from PIL import Image, ImageSequence


RADAR_BASE = "https://sirocco.accuweather.com/nx_mosaic_640x480_public/sir/"
FRAME_DELAYS_MS = [500, 500, 500, 500, 500, 2000]
CACHE_TTL_SECONDS = 300

REGION_FILES: Dict[str, str] = {
    "NORCAL": "inmasirCAn.gif",
    "CENTRALCAL": "inmasirCAc.gif",
    "SOCAL": "inmasirCAs.gif",
    "TXW": "inmasirTXw.gif",
    "TXE": "inmasirTXe.gif",
    "TXS": "inmasirTXs.gif",
    "NORTHEAST": "inmasirne.gif",
    "NORTHCENTRAL": "inmasirnc.gif",
    "NORTHWEST": "inmasirnw.gif",
    "SOUTHEAST": "inmasirse.gif",
    "SOUTHCENTRAL": "inmasirsc.gif",
    "SOUTHWEST": "inmasirsw.gif",
    "USA": "inmasirus_.gif",
}


def radar_url(key: str) -> str:
    key = key.upper()
    if key in REGION_FILES:
        return RADAR_BASE + REGION_FILES[key]
    return RADAR_BASE + f"inmasir{key.lower()}_.gif"


class FrameCache:
    def __init__(self, cache_dir: Path) -> None:
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def frames_for(self, key: str) -> list[bytes]:
        key = key.upper()
        stamp = self.cache_dir / f"{key}.stamp"
        frames = [self.cache_dir / f"{key}-{index}.png" for index in range(6)]

        if self._fresh(stamp) and all(frame.exists() for frame in frames):
            return [frame.read_bytes() for frame in frames]

        data = self._download(radar_url(key))
        decoded = self._decode_frames(data)
        for index, frame in enumerate(decoded):
            frames[index].write_bytes(frame)
        stamp.write_text(str(time.time()), encoding="utf-8")
        return decoded

    def _fresh(self, stamp: Path) -> bool:
        if not stamp.exists():
            return False
        try:
            cached_at = float(stamp.read_text(encoding="utf-8"))
        except ValueError:
            return False
        return (time.time() - cached_at) < CACHE_TTL_SECONDS

    def _download(self, url: str) -> bytes:
        request = urllib.request.Request(url, headers={"User-Agent": "DrizzleGarminConverter/1.0"})
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.read()

    def _decode_frames(self, data: bytes) -> list[bytes]:
        with Image.open(io.BytesIO(data)) as image:
            rendered: list[bytes] = []
            for frame in ImageSequence.Iterator(image):
                output = io.BytesIO()
                frame.convert("RGBA").save(output, format="PNG", optimize=True)
                rendered.append(output.getvalue())
                if len(rendered) == 6:
                    break

        if not rendered:
            raise ValueError("GIF did not contain any frames")

        while len(rendered) < 6:
            rendered.append(rendered[-1])

        return rendered


class Handler(BaseHTTPRequestHandler):
    cache: FrameCache

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        parts = [unquote(part) for part in parsed.path.split("/") if part]

        try:
            if parts == ["health"]:
                self._send_json({"ok": True})
                return

            if len(parts) == 2 and parts[0] == "manifest":
                self._send_json({"frames": 6, "delaysMs": FRAME_DELAYS_MS})
                return

            if len(parts) == 3 and parts[0] == "frame":
                key = parts[1].upper()
                frame_name = parts[2]
                index = int(frame_name.removesuffix(".png"))
                if index < 0 or index >= 6:
                    self.send_error(404, "Frame index out of range")
                    return
                frames = self.cache.frames_for(key)
                self._send_png(frames[index])
                return

            self.send_error(404, "Unknown endpoint")
        except (urllib.error.URLError, OSError, ValueError) as exc:
            self.send_error(502, str(exc))

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"{self.client_address[0]} - {fmt % args}")

    def _send_png(self, data: bytes) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Cache-Control", "max-age=300")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_json(self, payload: object) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve AccuWeather GIF frames as PNGs for Garmin testing.")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", default=8798, type=int)
    parser.add_argument("--cache-dir", default=str(Path(__file__).parent / "cache"))
    args = parser.parse_args()

    Handler.cache = FrameCache(Path(args.cache_dir))
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Serving Garmin radar frames on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
