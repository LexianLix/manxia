"""Live built-in discovery/search/reader acceptance on a disposable rooted AVD.

Only source selection and recent search terms are seeded. No comic, chapter,
image or source response is injected. Physical-phone acceptance is separate.
"""
import importlib.util
import json
import time
import xml.etree.ElementTree as ET
from pathlib import Path

spec = importlib.util.spec_from_file_location('script_smoke', Path(__file__).with_name('android-script-source-smoke.py'))
flow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flow)
nav = flow.nav
nav.OUT = Path('startup-evidence/builtin-sources')
nav.OUT.mkdir(parents=True, exist_ok=True)


def select_source(source, query):
    nav.adb('root')
    nav.adb('wait-for-device')
    nav.adb('shell', 'am', 'force-stop', nav.PACKAGE)
    remote = nav.DATA + '/shared_prefs/FlutterSharedPreferences.xml'
    owner = nav.adb('shell', 'stat', '-c', '%u', nav.DATA).strip()
    assert owner.isdigit() and int(owner) >= 10000
    preferences = ET.fromstring(nav.adb('shell', 'cat', remote))
    node = next((n for n in preferences if n.get('name') == 'flutter.features.v2'), None)
    if node is None:
        node = ET.SubElement(preferences, 'string', name='flutter.features.v2')
    features = json.loads(node.text or '{}')
    features.setdefault('options', {}).update(source=source, startTab=1, language='en', quality='standard', mode='page')
    features['searchHistory'] = [query]
    node.text = json.dumps(features)
    fixture = nav.OUT / 'selection-preferences.xml'
    fixture.write_bytes(ET.tostring(preferences, encoding='utf-8'))
    nav.adb('push', str(fixture), remote)
    nav.adb('shell', 'chown', f'{owner}:{owner}', remote)
    nav.adb('shell', 'restorecon', remote)
    nav.adb('shell', 'am', 'start', '-W', '-n', nav.PACKAGE + '/.MainActivity')


def main():
    results = {'scope': 'Live native adapters and decoded reader on Android emulator; no physical-phone FPS claim', 'sources': {}}
    try:
        for source, query, discovery_book, search_book in [
            ('mangabz', '火影', '鬼滅之刃', '火影忍者'),
            ('dongman', '女儿', '如出一辙的女儿', '如出一辙的女儿'),
        ]:
            select_source(source, query)
            nav.wait_ui('All comics')
            nav.tap('All comics')
            nav.wait_ui(discovery_book, timeout=90)
            nav.capture(source + '-discovery')
            nav.tap('Search comics, authors or keywords')
            nav.wait_ui('Search comics')
            flow.hide_keyboard()
            nav.tap('All enabled sources')
            nav.tap(query)
            nav.wait_ui(search_book, timeout=75)
            nav.capture(source + '-search')
            nav.tap(search_book)
            flow.open_reader()
            deadline = time.monotonic() + 150
            while time.monotonic() < deadline:
                remote = nav.DATA + '/shared_prefs/FlutterSharedPreferences.xml'
                root = ET.fromstring(nav.adb('shell', 'cat', remote))
                text = next((n.text for n in root if n.get('name') == 'flutter.history'), '[]')
                records = json.loads(text)
                row = next((r for r in records if r['comic'].get('sourceId') == source and r['chapterPath'].startswith('builtin:' + source + ':')), None)
                # ReaderPage commits a new scene/position only after its first
                # image has decoded. An address-only check cannot satisfy this.
                if row and row['total'] > 0:
                    nav.capture(source + '-reader')
                    results['sources'][source] = {'discovery': True, 'search': True, 'reader_first_image_decoded': True, 'pages': row['total']}
                    break
                time.sleep(1)
            else:
                raise RuntimeError(source + ': reader never committed a decoded chapter')
        results['passed'] = True
    finally:
        if not results.get('passed'):
            nav.capture('failure')
        (nav.OUT / 'logcat.txt').write_text(nav.adb('logcat', '-d', '-v', 'threadtime'), encoding='utf-8')
        (nav.OUT / 'verdict.json').write_text(json.dumps(results, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
