"""Check a signed in-place upgrade on a disposable, rootable emulator only.

Seeds synthetic preferences and a files-dir marker in the old public release,
then uses install -r, verifies their retention and checks the rendered library.
This checks APK/data compatibility, not the in-app download permission flow.
"""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

from android_surface import home_title_evidence

PACKAGE = 'io.manxia.manxia'
DATA = f'/data/user/0/{PACKAGE}'
PREFS = f'{DATA}/shared_prefs/FlutterSharedPreferences.xml'

def adb(*args, binary=False):
    output = subprocess.run(['adb', *args], check=True, capture_output=True, timeout=90).stdout
    return output if binary else output.decode('utf-8', 'replace')

def uid():
    value = adb('shell', 'stat', '-c', '%u', DATA).strip()
    if not re.fullmatch(r'\d+', value) or int(value) < 10000:
        raise RuntimeError('Package UID unavailable')
    return value

def read_preferences():
    root = ET.fromstring(adb('shell', 'cat', PREFS))
    return {node.get('name'): node.text for node in root if node.tag == 'string'}

def capture(output, name):
    adb('shell', 'uiautomator', 'dump', '/sdcard/manxia-upgrade.xml')
    xml = adb('shell', 'cat', '/sdcard/manxia-upgrade.xml')
    screen = adb('exec-out', 'screencap', '-p', binary=True)
    (output / f'{name}.xml').write_text(xml, encoding='utf-8')
    (output / f'{name}.png').write_bytes(screen)
    return xml, screen

def launch():
    adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity')
    time.sleep(7)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('old_apk', type=pathlib.Path)
    parser.add_argument('new_apk', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('startup-evidence/upgrade'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    print(adb('install', '--no-incremental', '-r', str(args.old_apk)), flush=True)
    launch()
    adb('root')
    adb('wait-for-device')
    owner = uid()
    adb('shell', 'am', 'force-stop', PACKAGE)
    raw = subprocess.run(['adb', 'shell', 'cat', PREFS], capture_output=True, text=True, timeout=30)
    root = ET.fromstring(raw.stdout) if raw.returncode == 0 else ET.Element('map')
    for directory in [f'{DATA}/shared_prefs', f'{DATA}/files']:
        adb('shell', 'mkdir', '-p', directory)
        adb('shell', 'chown', f'{owner}:{owner}', directory)
        adb('shell', 'restorecon', directory)
    comic = {'path':'/manhua-upgrade-check/', 'title':'升级校验书', 'cover':'', 'sourceId':'dm5'}
    record = {'comic':comic,'chapterPath':'/m123/','chapterTitle':'升级校验章节','page':3,'total':10,'updatedAt':1790000000000,'position':.35}
    values = {
        'flutter.favorites':json.dumps([comic], ensure_ascii=False),
        'flutter.history':json.dumps([record], ensure_ascii=False),
        'flutter.features.v2':json.dumps({'metadata':{comic['path']:{'group':'升级校验组'}},'options':{'startTab':0,'language':'zh_CN'},'searchHistory':['升级保留关键字']}, ensure_ascii=False),
    }
    for key, value in values.items():
        for node in list(root):
            if node.get('name') == key:
                root.remove(node)
        ET.SubElement(root, 'string', name=key).text = value
    fixture = args.output / 'synthetic-preferences.xml'
    fixture.write_bytes(ET.tostring(root, encoding='utf-8', xml_declaration=True))
    adb('push', str(fixture), PREFS)
    adb('shell', 'chown', f'{owner}:{owner}', PREFS)
    adb('shell', 'chmod', '600', PREFS)
    adb('shell', 'restorecon', PREFS)
    marker = args.output / 'synthetic-files-marker.bin'
    marker.write_bytes(b'Manxia synthetic upgrade retention check\n')
    remote_marker = f'{DATA}/files/upgrade-retention.bin'
    adb('push', str(marker), remote_marker)
    adb('shell', 'chown', f'{owner}:{owner}', remote_marker)
    adb('shell', 'restorecon', remote_marker)
    launch()
    old_xml, _ = capture(args.output, 'old-library')
    if comic['title'] not in old_xml:
        raise RuntimeError('Old release did not load the synthetic library')
    before = read_preferences()
    adb('shell', 'am', 'force-stop', PACKAGE)
    install = adb('install', '--no-incremental', '-r', str(args.new_apk))
    if 'Success' not in install:
        raise RuntimeError('In-place installation failed')
    launch()
    new_xml, screen = capture(args.output, 'upgraded-library')
    after = read_preferences()
    kept = all(json.loads(after.get(key, 'null')) == json.loads(before[key]) for key in values)
    marker_kept = hashlib.sha256(adb('exec-out', 'cat', remote_marker, binary=True)).digest() == hashlib.sha256(marker.read_bytes()).digest()
    painted = home_title_evidence(new_xml, screen)
    result = {'in_place_install':True,'same_uid':uid()==owner,'preferences_retained':kept,'files_retained':marker_kept,
              'library_visible':comic['title'] in new_xml,'home_painted':painted,'scope':'synthetic library, signed APK replacement on emulator'}
    (args.output / 'upgrade-verdict.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False), flush=True)
    if not all([result['same_uid'],kept,marker_kept,result['library_visible'],painted['painted']]):
        raise SystemExit(1)

if __name__ == '__main__':
    main()
