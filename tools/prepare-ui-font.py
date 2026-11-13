"""Derive the full-character static UI font; requires fonttools >= 4.60.

Usage: python tools/prepare-ui-font.py path/to/upstream/NotoSansSC[wght].ttf
The upstream SIL OFL and copyright remain in assets/fonts/NotoSansSC-OFL.txt.
"""
import sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

source = TTFont(sys.argv[1])
font = instantiateVariableFont(source, {"wght": 400}, inplace=False)
assert set(font.getBestCmap()) == set(source.getBestCmap()), "Character coverage changed"
names = {1: "Manxia Sans SC", 2: "Regular", 3: "ManxiaSansSC-Regular-1.0",
         4: "Manxia Sans SC Regular", 6: "ManxiaSansSC-Regular",
         16: "Manxia Sans SC", 17: "Regular"}
for record in list(font["name"].names):
    if record.nameID in names:
        font["name"].removeNames(nameID=record.nameID, platformID=record.platformID,
                                 platEncID=record.platEncID, langID=record.langID)
for name_id, value in names.items():
    font["name"].setName(value, name_id, 3, 1, 0x409)
    font["name"].setName(value, name_id, 1, 0, 0)
destination = Path(__file__).resolve().parent.parent / "assets/fonts/ManxiaSansSC-Regular.ttf"
font.save(destination)
print(f"Saved {destination.name}: {destination.stat().st_size} bytes, "
      f"{len(font.getBestCmap())} codepoints (full upstream coverage)")
