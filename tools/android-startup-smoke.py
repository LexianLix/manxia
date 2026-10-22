"""Cold-start an installed release APK and reject a blank Flutter surface.

Run only against a disposable emulator: this installs/replaces the test app.
Requires adb on PATH and Pillow. Preserves logcat, screenshots, and verdict.
"""

import argparse
import io
import json
import pathlib
import subprocess
import time

from PIL import Image


def adb(*args, binary=False, check=True):
    result = subprocess.run(
        ["adb", *args], capture_output=True, timeout=30, check=check
    )
    return result.stdout if binary else result.stdout.decode("utf-8", "replace")


def surface_stats(data):
    image = Image.open(io.BytesIO(data)).convert("RGB")
    w, h = image.size
    # Exclude Android's status/navigation bars and the launch icon at the center.
    crop = image.crop((int(w * .08), int(h * .16), int(w * .92), int(h * .84)))
    pixels = list(crop.resize((160, 160)).getdata())
    colors = {tuple(c // 16 for c in p) for p in pixels}
    dark = sum(max(p) < 185 for p in pixels) / len(pixels)
    return {"colors": len(colors), "dark_fraction": round(dark, 4)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("startup-evidence"))
    parser.add_argument("--timeout", type=int, default=45)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    package = "io.manxia.manxia"
    print(adb("install", "-r", str(args.apk)), flush=True)
    adb("shell", "am", "force-stop", package)
    adb("logcat", "-c")
    start = time.monotonic()
    print(adb("shell", "am", "start", "-W", "-n", f"{package}/.MainActivity"), flush=True)
    frames = []
    passed = False
    try:
        while time.monotonic() - start < args.timeout:
            time.sleep(2)
            data = adb("exec-out", "screencap", "-p", binary=True)
            (args.output / "screen.png").write_bytes(data)
            stats = surface_stats(data)
            stats["seconds"] = round(time.monotonic() - start, 1)
            frames.append(stats)
            print(json.dumps(stats), flush=True)
            # A launch icon/spinner alone cannot satisfy this content threshold.
            if stats["colors"] > 70 and .06 < stats["dark_fraction"] < .95:
                passed = True
                break
    finally:
        logs = adb("logcat", "-d", "-v", "threadtime")
        (args.output / "logcat.txt").write_text(logs, encoding="utf-8")
        focus = adb("shell", "dumpsys", "window", "windows")
        (args.output / "window.txt").write_text(focus, encoding="utf-8")
        # Collect semantics as additional evidence; not all Android images expose it.
        adb("shell", "uiautomator", "dump", "/sdcard/startup.xml", check=False)
        xml = adb("shell", "cat", "/sdcard/startup.xml", check=False)
        (args.output / "ui.xml").write_text(xml, encoding="utf-8")
        errors = [line for line in logs.splitlines() if any(
            s in line for s in ("Unhandled Exception", "FATAL EXCEPTION", "Error registering plugin")
        )]
        (args.output / "verdict.json").write_text(json.dumps({
            "passed": passed and not errors,
            "frames": frames, "startup_errors": errors,
        }, indent=2), encoding="utf-8")
        for line in errors:
            print(line, flush=True)
    if not passed or errors:
        raise SystemExit("FAIL: release did not render its first screen, or startup threw. See startup-evidence.")
    print("PASS: installed release rendered content after a cold launch.")


if __name__ == "__main__":
    main()
