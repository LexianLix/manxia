"""Cold-start an installed release APK and reject a blank Flutter surface.

Run only against a disposable emulator: this installs/replaces the test app.
Requires adb on PATH and Pillow. Preserves logcat, screenshots, and verdict.
"""

import argparse
import io
import json
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

from PIL import Image
from android_surface import home_title_evidence


def adb(*args, binary=False, check=True, timeout=30):
    result = subprocess.run(
        ["adb", *args], capture_output=True, timeout=timeout, check=check
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


def read_ui():
    adb("shell", "rm", "-f", "/sdcard/startup.xml")
    adb("shell", "uiautomator", "dump", "/sdcard/startup.xml")
    return adb("shell", "cat", "/sdcard/startup.xml")


def has_shelf(xml):
    try:
        nodes = ET.fromstring(xml).iter("node")
        labels = {node.get("content-desc") or node.get("text") for node in nodes
                  if node.get("package") == "io.manxia.manxia"}
        return {"我的书架", "书架", "设置"}.issubset(labels)
    except ET.ParseError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("startup-evidence"))
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--renderer", choices=("platform", "skia"), default="platform",
                        help="Diagnostic override; normal release checks use platform defaults")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    package = "io.manxia.manxia"
    print(adb("install", "-r", str(args.apk)), flush=True)
    adb("shell", "am", "force-stop", package)
    adb("logcat", "-c")
    start = time.monotonic()
    renderer_args = ("--ez", "enable-impeller", "false") if args.renderer == "skia" else ()
    print(adb("shell", "am", "start", "-W", "-n", f"{package}/.MainActivity", *renderer_args), flush=True)
    frames = []
    passed = False
    xml = ""
    command_errors = []
    title = {"painted": False}
    try:
        while time.monotonic() - start < args.timeout:
            time.sleep(2)
            data = adb("exec-out", "screencap", "-p", binary=True)
            (args.output / "screen.png").write_bytes(data)
            stats = surface_stats(data)
            stats["seconds"] = round(time.monotonic() - start, 1)
            frames.append(stats)
            print(json.dumps(stats), flush=True)
            # Use actual home controls, not palette richness: the offline shelf
            # deliberately uses pale paper/green and may have very few colors.
            if stats["colors"] > 8:
                activity = adb("shell", "dumpsys", "activity", "activities")
                if re.search(r"(?:mResumedActivity|topResumedActivity)[^\n]*io\.manxia\.manxia/", activity):
                    xml = read_ui()
                    if has_shelf(xml):
                        data = adb("exec-out", "screencap", "-p", binary=True)
                        (args.output / "screen.png").write_bytes(data)
                        title = home_title_evidence(xml, data)
                        passed = surface_stats(data)["colors"] > 8 and title["painted"]
                        if passed:
                            break
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        command_errors.append(str(error))
    finally:
        def diagnostic(*command):
            try:
                return adb(*command, timeout=10)
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
                command_errors.append(str(error))
                return ""

        logs = diagnostic("logcat", "-d", "-v", "threadtime")
        (args.output / "logcat.txt").write_text(logs, encoding="utf-8")
        focus = diagnostic("shell", "dumpsys", "window", "windows")
        (args.output / "window.txt").write_text(focus, encoding="utf-8")
        if not xml:
            try:
                xml = read_ui()
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
                command_errors.append(str(error))
        (args.output / "ui.xml").write_text(xml, encoding="utf-8")
        errors = [line for line in logs.splitlines() if any(
            s in line for s in (
                "Unhandled Exception", "FATAL EXCEPTION", "Error registering plugin",
                "Manxia startup", "Fatal signal",
            )
        )]
        (args.output / "verdict.json").write_text(json.dumps({
            "passed": passed and not errors and not command_errors,
            "shelf_controls_present": has_shelf(xml),
            "frames": frames, "startup_errors": errors,
            "painted_home_title": title, "command_errors": command_errors,
            "renderer_override": args.renderer,
        }, indent=2), encoding="utf-8")
        for line in errors:
            print(line, flush=True)
        screen = args.output / "screen.png"
        if screen.exists():
            # Keep the original PNG; RGB also provides a reliable image preview.
            Image.open(screen).convert("RGB").save(args.output / "screen-rgb.jpg", quality=92)
    if not passed or errors or command_errors:
        raise SystemExit("FAIL: release did not render its first screen, or startup threw. See startup-evidence.")
    print("PASS: installed release rendered content after a cold launch.")


if __name__ == "__main__":
    main()
