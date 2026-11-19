"""Exercise the installed AppWidget and offline resume on a disposable AVD."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
import zipfile

from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location('navigation', Path(__file__).with_name('android-navigation-smoke.py'))
nav = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nav)
nav.OUT = Path('startup-evidence/reading-widget')
HOST = 'io.manxia.widgetsmoke'
TITLE = 'Widget Offline Comic'
CHAPTER = 'Widget offline chapter'


def build_host(work):
    sdk = Path(os.environ['ANDROID_HOME'])
    tools = sdk / 'build-tools' / '36.0.0'
    platform = sdk / 'platforms' / 'android-36' / 'android.jar'
    sources = Path(__file__).with_name('android-widget-host')
    def run(*args):
        subprocess.run(list(map(str, args)), check=True, timeout=60)
    run('javac', '--release', '8', '-classpath', platform, '-d', work, sources / 'WidgetHostActivity.java')
    run(tools / 'd8', '--lib', platform, '--min-api', 24, '--output', work,
        work / 'io/manxia/widgetsmoke/WidgetHostActivity.class')
    apk = work / 'widget-test.apk'
    run(tools / 'aapt2', 'link', '-I', platform, '--manifest', sources / 'AndroidManifest.xml', '-o', apk)
    with zipfile.ZipFile(apk, 'a') as archive:
        archive.write(work / 'classes.dex', 'classes.dex')
    store = work / 'test-key.jks'
    run('keytool', '-genkeypair', '-keystore', store, '-storepass', 'android', '-keypass', 'android',
        '-alias', 'host', '-dname', 'CN=Manxia test widget host', '-keyalg', 'RSA', '-validity', '7', '-noprompt')
    run(tools / 'apksigner', 'sign', '--ks', store, '--ks-pass', 'pass:android', '--key-pass', 'pass:android', apk)
    nav.adb('install', '-r', str(apk))


def seed_library(work):
    nav.adb('root')
    nav.adb('wait-for-device')
    nav.adb('shell', 'am', 'force-stop', nav.PACKAGE)
    owner = nav.adb('shell', 'stat', '-c', '%u', nav.DATA).strip()
    assert owner.isdigit() and int(owner) >= 10000
    remote_prefs = nav.DATA + '/shared_prefs/FlutterSharedPreferences.xml'
    root = ET.fromstring(nav.adb('shell', 'cat', remote_prefs))
    paths = []
    for number, color in enumerate(['#6F5375', '#285751', '#514E87'], 1):
        image = Image.new('RGB', (360, 500), color)
        draw = ImageDraw.Draw(image)
        draw.rectangle((45, 50, 315, 450), outline='#F8EBD2', width=7)
        draw.text((70, 90), f'Widget page {number}', fill='white')
        file = work / f'{number}.png'
        image.save(file)
        digest = hashlib.sha256(file.read_bytes()).hexdigest()
        paths.append(digest)
        remote = nav.DATA + '/app_flutter/manxia/pages/' + digest
        nav.adb('push', str(file), remote)
        nav.adb('shell', 'chown', f'{owner}:{owner}', remote)
        nav.adb('shell', 'restorecon', remote)
    comic = {'path':'local:widget-test', 'title':TITLE, 'cover':'offline:' + paths[0], 'sourceId':'local'}
    chapter = {'path':'local:widget-chapter', 'title':CHAPTER}
    event = {'comic':comic, 'chapterPath':chapter['path'], 'chapterTitle':CHAPTER,
             'page':1, 'total':3, 'updatedAt':int(time.time()*1000), 'position':0}
    offline = {'id':'widget-fixture', 'comic':comic, 'chapter':chapter,
               'status':'complete', 'keys':paths, 'urls':[], 'bytes':0}
    values = {'favorites':[comic], 'history':[event], 'offline.v1':[offline],
              'features.v2':{'options':{'language':'en','startTab':0}, 'metadata':{}}}
    for name, value in values.items():
        key = 'flutter.' + name
        for node in list(root):
            if node.get('name') == key:
                root.remove(node)
        ET.SubElement(root, 'string', name=key).text = json.dumps(value)
    fixture = work / 'preferences.xml'
    fixture.write_bytes(ET.tostring(root, encoding='utf-8'))
    nav.adb('push', str(fixture), remote_prefs)
    nav.adb('shell', 'chown', f'{owner}:{owner}', remote_prefs)
    nav.adb('shell', 'restorecon', remote_prefs)


def host():
    nav.adb('shell', 'am', 'start', '-W', '-n', HOST + '/.WidgetHostActivity')


def main():
    nav.OUT.mkdir(parents=True, exist_ok=True)
    result = {'scope':'Android AppWidget host with synthetic offline book, no physical launcher claim'}
    try:
        with tempfile.TemporaryDirectory() as work:
            path = Path(work)
            build_host(path)
            seed_library(path)
        nav.adb('shell', 'appwidget', 'grantbind', '--package', HOST)
        nav.adb('shell', 'svc', 'wifi', 'disable')
        nav.adb('shell', 'svc', 'data', 'disable')
        nav.adb('shell', 'am', 'start', '-W', '-n', nav.PACKAGE + '/.MainActivity')
        nav.wait_ui(TITLE)
        # The bridge runs after the Flutter shell has mounted; check that its
        # thumbnail was generated from the local book before killing the app.
        widget_prefs = nav.DATA + '/shared_prefs/continue_reading_widget.xml'
        deadline = time.monotonic() + 15
        while 'coverBytes' not in nav.adb('shell', 'cat', widget_prefs, check=False):
            if time.monotonic() >= deadline:
                raise RuntimeError('Widget cover was not stored')
            time.sleep(.25)
        host()
        nav.wait_ui('2/3')
        nav.capture('widget-page-2')
        dead = False
        for _ in range(8):
            nav.adb('shell', 'am', 'kill', nav.PACKAGE)
            if not nav.adb('shell', 'pidof', nav.PACKAGE, check=False).strip():
                dead = True
                break
            time.sleep(1)
        if not dead:
            raise RuntimeError('App did not exit while the widget host was visible')
        nav.tap(TITLE)
        nav.wait_ui('2 / 3')
        nav.capture('cold-resume-offline')
        result['cold_resume_saved_page'] = 2
        nav.tap('Next page')
        nav.wait_ui('3 / 3')
        host()
        nav.wait_ui('3/3')
        nav.capture('widget-page-3')
        assert nav.adb('shell', 'pidof', nav.PACKAGE, check=False).strip()
        nav.tap(TITLE)
        nav.wait_ui('3 / 3')
        result['warm_resume_updated_page'] = 3
        nav.adb('shell', 'input', 'keyevent', '4')
        assert not nav.has_label(nav.wait_ui('Library'), CHAPTER)
        result['offline'] = True
        result['passed'] = True
    finally:
        if not result.get('passed'):
            nav.capture('failure')
        nav.adb('shell', 'svc', 'wifi', 'enable', check=False)
        nav.adb('shell', 'svc', 'data', 'enable', check=False)
        (nav.OUT / 'verdict.json').write_text(json.dumps(result, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
