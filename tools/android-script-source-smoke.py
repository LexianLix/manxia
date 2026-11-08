"""Exercise the bundled author example with the Android JavaScript sandbox."""
import importlib.util
import io
import json
from pathlib import Path
import re
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


def tap_node(node):
    left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
    nav.adb('shell', 'input', 'tap', str((left + right) // 2), str((top + bottom) // 2))


def hide_keyboard():
    ime = nav.adb('shell', 'dumpsys', 'input_method')
    if re.search(r'\bm(?:InputShown|IsInputViewShown)=true\b', ime):
        nav.adb('shell', 'input', 'keyevent', '4')


def type_query(text):
    fields = [node for node in ET.fromstring(nav.read_ui()).iter('node')
              if node.get('class') == 'android.widget.EditText']
    if len(fields) != 1:
        raise RuntimeError(f'Expected one search field, found {len(fields)}')
    tap_node(fields[0])
    time.sleep(.5)
    nav.adb('shell', 'input', 'text', text.replace(' ', '%s'))
    hide_keyboard()


def open_reader():
    until = time.monotonic() + 35
    while time.monotonic() < until:
        for node in ET.fromstring(nav.read_ui()).iter('node'):
            if ('Read' in (node.get('text'), node.get('content-desc'))
                    and node.get('enabled') == 'true'):
                tap_node(node)
                return
        time.sleep(.5)
    raise RuntimeError('Missing enabled Read button')


def main():
    result = {'scope': 'Android isolated runtime, live example catalog and image on emulator'}
    try:
        (nav.OUT / 'webview.txt').write_text(nav.adb('shell', 'dumpsys', 'webviewupdate'), encoding='utf-8')
        open_plugins()
        type_query('Xiaxia Demo')
        nav.wait_ui('Xiaxia Demo Source')
        nav.tap('Install')
        nav.wait_ui('Script request domains')
        nav.capture('install-permissions')
        nav.tap('Install & enable')
        nav.wait_ui('Installed 1')
        result['installed'] = True
        nav.tap('Installed 1')
        nav.scroll_to('Test script source')
        nav.tap('Test script source')
        nav.wait_ui('Run source test')
        type_query('Manxia Demo')
        nav.tap('Run source test')
        nav.wait_ui('First image decoded', timeout=50)
        nav.capture('source-test')
        result['search_detail_image'] = True
        nav.adb('shell', 'input', 'keyevent', '4')
        nav.wait_ui('Plugin store')
        nav.scroll_to('Set as discovery source')
        nav.tap('Set as discovery source')
        nav.wait_ui('Current discovery source')
        if nav.has_label(nav.read_ui(), 'Expand navigation'):
            nav.tap('Expand navigation')
            nav.wait_ui('Explore')
        nav.tap('Explore')
        nav.wait_ui('漫匣试读', timeout=50)
        nav.tap('漫匣试读')
        open_reader()
        until = time.monotonic() + 40
        while time.monotonic() < until:
            png = nav.adb('exec-out', 'screencap', '-p', binary=True)
            image = Image.open(io.BytesIO(png)).convert('RGB')
            w, h = image.size
            center = image.crop((w // 6, h // 5, w * 5 // 6, h * 4 // 5))
            colors = center.getcolors(w * h)
            purple = sum(n for n, (r, g, b) in colors if r > g + 7 and b > g + 18)
            if purple >= 300 and nav.has_label(nav.read_ui(), 'Next page'):
                nav.capture('reader')
                break
            time.sleep(1)
        else:
            raise RuntimeError('Reader did not render the example image')
        result['reader_rendered'] = True
        time.sleep(6)
        nav.tap('Next page')
        time.sleep(3)
        nav.adb('shell', 'input', 'keyevent', '4')
        nav.wait_ui('My ratings & reviews')
        nav.tap('My ratings & reviews')
        nav.wait_ui('Rate 4 stars')
        nav.tap('Rate 4 stars')
        type_query('Release verification review')
        nav.tap('Save')
        nav.wait_ui('More actions')
        nav.tap('More actions')
        nav.wait_ui('Reading position history')
        nav.tap('Reading position history')
        nav.wait_ui('1 / 3')
        nav.capture('reading-positions')
        nav.tap('1 / 3')
        nav.wait_ui('Next page')
        nav.capture('restored-reader')
        nav.adb('shell', 'input', 'keyevent', '4')
        nav.wait_ui('More actions')
        nav.adb('shell', 'input', 'keyevent', '4')
        if nav.has_label(nav.read_ui(), 'Expand navigation'):
            nav.tap('Expand navigation')
        nav.tap('Settings')
        nav.wait_ui('Preferences')
        nav.tap('Reading statistics')
        nav.wait_ui('Reading time')
        nav.capture('reading-statistics')
        preferences = ET.fromstring(nav.adb('shell','cat',nav.DATA+'/shared_prefs/FlutterSharedPreferences.xml'))
        features = json.loads(next(n.text for n in preferences if n.get('name') == 'flutter.features.v2'))
        activity = features['journal']['activity']
        assert sum(row['milliseconds'] for row in activity.values()) >= 2000
        assert any(any(pages for pages in row['pages'].values()) for row in activity.values())
        assert any(meta.get('personalReview',{}).get('rating') == 4 and meta.get('personalReview',{}).get('text') == 'Release verification review' for meta in features['metadata'].values())
        assert len(features['journal']['positions']) >= 2
        result['reading_time_and_pages_recorded'] = True
        result['personal_review_persisted'] = True
        result['position_history_restored'] = True
        result['passed'] = True
    finally:
        (nav.OUT / 'flow-logcat.txt').write_text(
            nav.adb('logcat', '-d', '-v', 'threadtime'), encoding='utf-8')
        if not result.get('passed'):
            try:
                nav.capture('failure')
            except Exception:
                pass
        (nav.OUT / 'script-source-verdict.json').write_text(json.dumps(result, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
