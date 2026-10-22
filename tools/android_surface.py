"""Check that home text is painted, rather than only present in semantics.

Replay saved emulator evidence with: python tools/android_surface.py <directory>
The fresh-install smoke test uses the default home screen and its title bounds.
"""

import argparse
import io
import json
import pathlib
import re
import statistics
import xml.etree.ElementTree as ET

from PIL import Image


def home_title_evidence(xml, screenshot):
    image = Image.open(io.BytesIO(screenshot)).convert("RGB")
    try:
        nodes = ET.fromstring(xml).iter("node")
        title = next((n for n in nodes if
                      n.get("package") == "io.manxia.manxia" and
                      (n.get("content-desc") or n.get("text")) == "我的书架"), None)
    except ET.ParseError:
        title = None
    bounds = [int(v) for v in re.findall(r"\d+", title.get("bounds", ""))] if title is not None else []
    if len(bounds) != 4:
        return {"painted": False, "reason": "home title bounds unavailable"}
    x1, y1, x2, y2 = bounds
    if not (0 <= x1 < x2 <= image.width and 0 <= y1 < y2 <= image.height):
        return {"painted": False, "reason": "home title outside screenshot"}
    crop = image.crop(tuple(bounds))
    pixels = list(crop.get_flattened_data() if hasattr(crop, "get_flattened_data") else crop.getdata())
    paper = tuple(statistics.median(p[c] for p in pixels) for c in range(3))
    ink_fraction = sum(max(abs(p[c] - paper[c]) for c in range(3)) >= 50
                       for p in pixels) / len(pixels)
    return {"painted": ink_fraction >= .01, "bounds": bounds,
            "ink_fraction": round(ink_fraction, 4)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=pathlib.Path)
    args = parser.parse_args()
    result = home_title_evidence(
        (args.directory / "ui.xml").read_text(encoding="utf-8"),
        (args.directory / "screen.png").read_bytes(),
    )
    print(json.dumps(result))
    raise SystemExit(0 if result["painted"] else 1)
