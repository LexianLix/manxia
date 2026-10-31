"""Exercise reminders on a disposable, rootable Android emulator.

Uses synthetic preferences. Notification delivery is triggered through the real
private receiver with adb root; this does not assert exact alarm timing.
"""
import argparse
import datetime as dt
import json
import pathlib
import re
import time
import xml.etree.ElementTree as ET
from android_startup_smoke import adb, read_ui

PACKAGE = 'io.manxia.manxia'
DATA = f'/data/user/0/{PACKAGE}'
ACTION = 'io.manxia.FOLLOW_REMINDER'
OUT = pathlib.Path('follow-evidence')


def wait_ui(word, timeout=45):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        xml = read_ui()
        if word in xml:
            return xml
        time.sleep(1)
    raise RuntimeError(f'UI did not show {word}')


def tap(word, *, resource=False):
    root = ET.fromstring(read_ui())
    nodes = [n for n in root.iter('node') if
             word in (n.get('resource-id', '') if resource else
                      n.get('content-desc', '') + ' ' + n.get('text', ''))]
    if not nodes:
        raise RuntimeError(f'Cannot find action {word}')
    clickable = [n for n in nodes if n.get('clickable') == 'true']
    node = (clickable or nodes)[-1]
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    time.sleep(1)


def capture(name):
    (OUT / f'{name}.xml').write_text(read_ui(), encoding='utf-8')
    (OUT / f'{name}.png').write_bytes(adb('exec-out', 'screencap', '-p', binary=True))


def launch_calendar():
    adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity', '--ez', 'followCalendar', 'true')
    wait_ui('Follow calendar')


def alarm_present():
    text = adb('shell', 'dumpsys', 'alarm')
    (OUT / 'alarm-last.txt').write_text(text, encoding='utf-8')
    return re.search(r'(?m)^\s*tag=\*walarm\*:' + re.escape(ACTION) + r'\s*$', text) is not None


def receiver_notification():
    result = adb('shell', 'am', 'broadcast', '--receiver-foreground', '-n',
                 f'{PACKAGE}/.FollowReminderReceiver', '-a', ACTION)
    if 'Permission Denial' in result:
        raise RuntimeError('Emulator root did not permit private receiver test')
    time.sleep(2)
    text = adb('shell', 'dumpsys', 'notification', '--noredact')
    (OUT / 'notification.txt').write_text(text, encoding='utf-8')
    assert 'Time for your favorite stories' in text, 'Native notification was not posted'


def click_notification():
    adb('shell', 'cmd', 'statusbar', 'expand-notifications')
    wait_ui('Time for your favorite stories')
    capture('notification-drawer')
    tap('Time for your favorite stories')
    wait_ui('Follow calendar')


def root_emulator():
    adb('root'); adb('wait-for-device')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=pathlib.Path)
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    result = {}
    try:
        adb('install', '-r', str(args.apk), timeout=90)
        root_emulator()
        adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity')
        time.sleep(8)
        adb('shell', 'am', 'force-stop', PACKAGE)
        owner = adb('shell', 'stat', '-c', '%u', DATA).strip()
        assert owner.isdigit() and int(owner) >= 10000
        epoch = int(adb('shell', 'date', '+%s').strip())
        # Default emulator timezone UTC; derive local weekday/hour explicitly.
        stamp = adb('shell', 'date', '-d', '@'+str(epoch+120), '+%u:%H:%M').strip()
        day, hour, minute = map(int, stamp.split(':'))
        for name, raw in [
            ('FlutterSharedPreferences.xml', '<map><string name="flutter.features.v2">'+
             json.dumps({'options': {'language': 'en'}})+'</string></map>'),
            ('follow-reminder.xml', f'<map><boolean name="enabled" value="false"/><set name="days"><string>{day}</string></set><int name="hour" value="{hour}"/><int name="minute" value="{minute}"/></map>')]:
            file = OUT / name
            file.write_text(raw, encoding='utf-8')
            remote = f'{DATA}/shared_prefs/{name}'
            adb('push', str(file), remote)
            adb('shell', 'chown', f'{owner}:{owner}', remote)
            adb('shell', 'chmod', '600', remote)
            adb('shell', 'restorecon', remote)
        launch_calendar()
        tap('Reading reminder')
        wait_ui('Weekly reminder')
        capture('reminder-initial')
        sdk = int(adb('shell', 'getprop', 'ro.build.version.sdk').strip())
        if sdk >= 33:
            tap('Weekly reminder'); tap('Save')
            wait_ui('permission_deny_button')
            tap('permission_deny_button', resource=True)
            wait_ui('Notifications are blocked')
            result['denial_feedback'] = True
            capture('permission-denied')
            adb('shell', 'pm', 'grant', PACKAGE, 'android.permission.POST_NOTIFICATIONS')
        else:
            result['denial_feedback'] = 'Not applicable before Android 13'
        tap('Weekly reminder'); tap('Save')
        wait_ui('Follow calendar')
        assert alarm_present(), 'Enabled reminder has no pending alarm'
        result['alarm_registered'] = True
        capture('enabled')
        # Foreground click uses onNewIntent, then one Back returns to the shelf.
        adb('shell', 'input', 'keyevent', '4')
        wait_ui('My library')
        receiver_notification(); click_notification()
        capture('foreground-calendar')
        result['foreground_notification_navigation'] = True
        adb('shell', 'input', 'keyevent', '4'); wait_ui('My library')
        receiver_notification()
        adb('shell', 'input', 'keyevent', '3')
        adb('shell', 'am', 'kill', PACKAGE)
        time.sleep(2)
        assert not adb('shell', 'pidof', PACKAGE, check=False).strip(), 'App was not killed for cold navigation'
        click_notification(); capture('cold-calendar')
        result['cold_notification_navigation'] = True
        adb('reboot'); adb('wait-for-device', timeout=120)
        until = time.monotonic()+90
        while time.monotonic() < until and adb('shell', 'getprop', 'sys.boot_completed').strip() != '1':
            time.sleep(2)
        root_emulator(); time.sleep(8)
        assert alarm_present(), 'Boot did not restore the reminder'
        result['reboot_rescheduled'] = True
        launch_calendar(); tap('Reading reminder'); wait_ui('Weekly reminder')
        tap('Weekly reminder'); tap('Save'); wait_ui('Follow calendar')
        assert not alarm_present(), 'Disabled reminder still has a pending alarm'
        result['disable_cancelled'] = True
        capture('disabled')
        result['notification_delivery'] = 'Real receiver explicitly triggered by adb root; exact scheduled timing not asserted'
        result['passed'] = True
    finally:
        (OUT/'verdict.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        (OUT/'logcat.txt').write_text(adb('logcat', '-d', check=False), encoding='utf-8')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
