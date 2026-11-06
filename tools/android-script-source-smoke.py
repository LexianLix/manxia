"""Exercise the bundled author example with the Android JavaScript sandbox."""
import importlib.util
import io
import json
from pathlib import Path
import time
import xml.etree.ElementTree as ET

from PIL import Image


spec = importlib.util.spec_from_file_location(
    'navigation_smoke', Path(__file__).with_name('android-navigation-smoke.py')
)
nav = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nav)
nav.OUT = Path('startup-evidence/script-source')
nav.OUT.mkdir(parents=True, exist_ok=True)


def open_plugins():
    nav.adb('root')
    nav.adb('wait-for-device')
    nav.adb('shell', 'am', 'force-stop', nav.PACKAGE)
    owner = nav.adb('shell', 'stat', '-c', '%u', nav.DATA).strip()
    assert owner.isdigit() and int(owner) >= 10000
    remote = nav.DATA + '/shared_prefs/FlutterSharedPreferences.xml'
    preferences = ET.fromstring(nav.adb('shell', 'cat', remote))
    feature = next((node for node in preferences if node.get('name') == 'flutter.features.v2'), None)
    if feature is None:
        feature = ET.SubElement(preferences, 'string', name='flutter.features.v2')
    values = json.loads(feature.text or '{}')
    values.setdefault('options', {}).update(startTab=5, language='en', quality='standard')
    feature.text = json.dumps(values)
    fixture = nav.OUT / 'synthetic-preferences.xml'
    fixture.write_bytes(ET.tostring(preferences, encoding='utf-8'))
    nav.adb('push', str(fixture), remote)
    nav.adb('shell', 'chown', f'{owner}:{owner}', remote)
    nav.adb('shell', 'restorecon', remote)
    nav.adb('shell', 'am', 'start', '-W', '-n', nav.PACKAGE + '/.MainActivity')
    nav.wait_ui('Plugin store')


def type_query(label, text):
    nav.tap(label)
    nav.adb('shell', 'input', 'text', text.replace(' ', '%s'))
    nav.adb('shell', 'input', 'keyevent', '4')


def main():
    result = {'scope': 'Android isolated runtime, live example catalog and image on emulator'}
    try:
        (nav.OUT / 'webview.txt').write_text(nav.adb('shell', 'dumpsys', 'webviewupdate'), encoding='utf-8')
        open_plugins()
        type_query('Search plugins, authors or purpose', 'Xiaxia Demo')
        nav.wait_ui('Xiaxia Demo Source')
        nav.tap('Install')
        nav.wait_ui('Script request domains')
        nav.capture('install-permissions')
        nav.tap('Install & enable')
        nav.wait_ui('Test script source')
        result['installed'] = True
        nav.tap('Test script source')
        nav.wait_ui('Test keyword')
        type_query('Test keyword', 'Manxia Demo')
        nav.tap('Run source test')
        nav.wait_ui('First image decoded', timeout=50)
        nav.capture('source-test')
        result['search_detail_image'] = True
        nav.adb('shell', 'input', 'keyevent', '4')
        nav.wait_ui('Plugin store')
        nav.tap('Set as discovery source')
        nav.wait_ui('Current discovery source')
        nav.tap('Explore')
        nav.wait_ui('漫匣试读', timeout=50)
        nav.tap('漫匣试读')
        nav.wait_ui('小夏的阅读室')
        nav.tap('Read')
        nav.wait_ui('Next page')
        time.sleep(4)
        _, png = nav.capture('reader')
        image = Image.open(io.BytesIO(png)).convert('RGB')
        w, h = image.size
        center = image.crop((w // 6, h // 5, w * 5 // 6, h * 4 // 5))
        colors = center.getcolors(w * h)
        purple = sum(n for n, (r, g, b) in colors if r > g + 7 and b > g + 18)
        if purple < 300:
            raise RuntimeError('Reader did not render the example image')
        result['reader_rendered'] = True
        result['passed'] = True
    finally:
        if not result.get('passed'):
            try:
                nav.capture('failure')
            except Exception:
                pass
        (nav.OUT / 'script-source-verdict.json').write_text(json.dumps(result, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
