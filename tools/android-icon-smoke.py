"""Capture the installed launcher icon and open the app on a disposable AVD."""
import argparse
import json
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from PIL import Image


def adb(*args, binary=False):
    data = subprocess.run(['adb', *args], capture_output=True, check=True, timeout=60).stdout
    return data if binary else data.decode('utf-8', 'replace')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('startup-evidence/launcher'))
    output = parser.parse_args().output
    output.mkdir(parents=True, exist_ok=True)
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(2)
    width, height = map(int, re.findall(r'\d+', adb('shell', 'wm', 'size'))[-2:])
    node = None
    for _ in range(3):
        adb('shell', 'input', 'swipe', str(width//2), str(height*4//5), str(width//2), str(height//5), '400')
        time.sleep(2)
        adb('shell', 'uiautomator', 'dump', '/sdcard/manxia-launcher.xml')
        xml = adb('shell', 'cat', '/sdcard/manxia-launcher.xml')
        matches = [n for n in ET.fromstring(xml).iter('node')
                   if n.get('text') == '漫匣' or n.get('content-desc') == '漫匣']
        if matches:
            node = matches[-1]
            break
    (output/'launcher.xml').write_text(xml, encoding='utf-8')
    (output/'launcher.png').write_bytes(adb('exec-out', 'screencap', '-p', binary=True))
    if node is None:
        raise RuntimeError('Installed Manxia launcher entry was not visible')
    left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
    with Image.open(output/'launcher.png') as screen:
        screen.crop((max(0,left-16), max(0,top-100), min(width,right+16), min(height,bottom+10))).save(output/'icon-crop.png')
    adb('shell', 'input', 'tap', str((left+right)//2), str((top+bottom)//2))
    time.sleep(3)
    windows = adb('shell', 'dumpsys', 'window', 'windows')
    (output/'launched-window.txt').write_text(windows, encoding='utf-8')
    opened = bool(re.search(r'mCurrentFocus=.*io\.manxia\.manxia/', windows))
    result = {'launcher_entry_present':True, 'launch_from_icon':opened,
              'scope':'Installed launcher entry and launch; visual appearance requires PNG inspection',
              'passed':opened}
    (output/'verdict.json').write_text(json.dumps(result,indent=2), encoding='utf-8')
    print(json.dumps(result))
    if not opened:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
