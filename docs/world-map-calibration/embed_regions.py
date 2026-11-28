"""Embed per-region border datasets into radar-map.html's #regionCountryData.

Reads each docs/world-map-calibration/<KEY>-country-data.json and writes a
single JSON object { "<KEY>": [[name, packed], ...], ... } into the
<script id="regionCountryData"> placeholder.
"""
import argparse
import json
import re
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--data", type=Path, default=repo / "docs" / "world-map-calibration")
parser.add_argument("--html", type=Path, default=repo / "Assets" / "radar-map.html")
args = parser.parse_args()
calib, html = args.data, args.html

regions = {}
for f in sorted(calib.glob("*-country-data.json")):
    key = f.name[:-len("-country-data.json")]
    regions[key] = json.loads(f.read_text(encoding="utf8"))

payload = "{\n" + ",\n".join(
    json.dumps(k) + ":" + json.dumps(v, ensure_ascii=True, separators=(",", ":"))
    for k, v in regions.items()) + "\n}"

text = html.read_text(encoding="utf8")
pattern = re.compile(
    r'(<script id="regionCountryData" type="application/json">\n).*?(\n</script>)',
    re.S)
new, n = pattern.subn(lambda m: m.group(1) + payload + m.group(2), text)
assert n == 1, f"expected 1 replacement, got {n}"
newline = "\r\n" if b"\r\n" in html.read_bytes() else "\n"
html.write_text(new, encoding="utf8", newline=newline)
print("embedded regions:", list(regions), "payload bytes:", len(payload))
