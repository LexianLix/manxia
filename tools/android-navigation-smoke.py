"""Exercise shared headers, navigation and network callbacks on a disposable AVD."""
import argparse
import hashlib
import io
import json
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from PIL import Image

PACKAGE = 'io.manxia.manxia'
DATA = f'/data/user/0/{PACKAGE}'
OUT = pathlib.Path('navigation-evidence')
system_dialogs = 0

def adb(*args, binary=False, check=True, timeout=90):
    r = subprocess.run(['adb', *args], capture_output=True, check=check, timeout=timeout)
    return r.stdout if binary else r.stdout.decode('utf-8', 'replace')

def read_ui():
    adb('shell','uiautomator','dump','/sdcard/manxia-navigation.xml')
    return adb('shell','cat','/sdcard/manxia-navigation.xml')

def has_label(xml, word):
    return any(word in n.get('text','')+' '+n.get('content-desc','')
               for n in ET.fromstring(xml).iter('node'))

def capture(name):
    xml = read_ui()
    png = adb('exec-out','screencap','-p',binary=True)
    (OUT/f'{name}.xml').write_text(xml,encoding='utf-8')
    (OUT/f'{name}.png').write_bytes(png)
    return xml, png

def tap(word, resource=False):
    nodes = [n for n in ET.fromstring(read_ui()).iter('node') if word in
             (n.get('resource-id','') if resource else n.get('text','')+' '+n.get('content-desc',''))]
    if not nodes: raise RuntimeError('Missing action: '+word)
    node = ([n for n in nodes if n.get('clickable')=='true'] or nodes)[-1]
    x,y,r,b = map(int,re.findall(r'\d+',node.get('bounds')))
    adb('shell','input','tap',str((x+r)//2),str((y+b)//2));time.sleep(.6)

def wait_ui(word, timeout=45):
    global system_dialogs
    until = time.monotonic()+timeout
    while time.monotonic()<until:
        xml = read_ui()
        titles = [n.get('text') for n in ET.fromstring(xml).iter('node')
                  if n.get('package')=='android' and n.get('resource-id')=='android:id/alertTitle']
        if any(t in ["Pixel Launcher isn't responding","System UI isn't responding"] for t in titles):
            if system_dialogs>=2: raise RuntimeError('Repeated emulator system failure')
            system_dialogs+=1;capture(f'emulator-dialog-{system_dialogs}')
            tap('android:id/aerr_wait' if "System UI isn't responding" in titles else 'android:id/aerr_close',resource=True)
            continue
        if has_label(xml, word):return xml
        time.sleep(.5)
    raise RuntimeError('UI did not show '+word)

def scroll_to(word):
    width,height = map(int,re.findall(r'\d+',adb('shell','wm','size'))[-2:])
    for _ in range(10):
        nodes = [n for n in ET.fromstring(read_ui()).iter('node')
                 if word in n.get('text','')+' '+n.get('content-desc','')]
        for node in nodes:
            _,top,_,bottom = map(int,re.findall(r'\d+',node.get('bounds')))
            # A semantic node can remain visible behind the floating dock.
            # Move actions into the clear viewport before tapping them.
            if height*.15 <= (top+bottom)/2 <= height*.75:return
        adb('shell','input','swipe',str(width//2),str(height*4//5),str(width//2),str(height//3),'300')
    raise RuntimeError('Cannot scroll to '+word)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('apk',type=pathlib.Path);args=p.parse_args()
    OUT.mkdir(exist_ok=True);result={}
    try:
        adb('install','-r',str(args.apk));adb('root');adb('wait-for-device')
        adb('shell','am','start','-W','-n',PACKAGE+'/.MainActivity');time.sleep(7)
        adb('shell','am','force-stop',PACKAGE)
        owner=adb('shell','stat','-c','%u',DATA).strip();assert owner.isdigit() and int(owner)>=10000
        image=Image.new('RGB',(40,80),(58,111,133));raw=io.BytesIO();image.save(raw,format='PNG');data=raw.getvalue();key=hashlib.sha256(data).hexdigest()
        wallpaper=OUT/'synthetic-wallpaper.png';wallpaper.write_bytes(data)
        directory=DATA+'/app_flutter/manxia/appearance'
        adb('shell','mkdir','-p',directory)
        for path in [DATA+'/app_flutter/manxia',directory]:adb('shell','chown',f'{owner}:{owner}',path)
        adb('push',str(wallpaper),directory+'/'+key);adb('shell','chown',f'{owner}:{owner}',directory+'/'+key);adb('shell','restorecon','-R',directory)
        values={'options':{'startTab':3,'language':'en','quality':'standard','appearance':{'wallpaper':key,'seed':0xff3a6f85,'follow':False,'veil':.1,'blur':0}}}
        root=ET.Element('map');ET.SubElement(root,'string',name='flutter.features.v2').text=json.dumps(values)
        prefs=OUT/'synthetic-preferences.xml';prefs.write_bytes(ET.tostring(root,encoding='utf-8'))
        remote=DATA+'/shared_prefs/FlutterSharedPreferences.xml'
        adb('push',str(prefs),remote);adb('shell','chown',f'{owner}:{owner}',remote);adb('shell','restorecon',remote)
        adb('shell','am','start','-W','-n',PACKAGE+'/.MainActivity');wait_ui('Preferences')
        for tab,title in [('Downloads','Downloads & local library'),('Plugins','Plugin store')]:
            tap(tab);xml=wait_ui(title);_,png=capture(tab.lower())
            node=next(n for n in ET.fromstring(xml).iter('node') if title in n.get('text','')+' '+n.get('content-desc',''))
            _,top,_,bottom=map(int,re.findall(r'\d+',node.get('bounds')))
            pixel=Image.open(io.BytesIO(png)).convert('RGB').getpixel((5,(top+bottom)//2))
            assert pixel[0]<150 and pixel[2]-pixel[0]>20, f'{tab} header hides wallpaper: {pixel}'
            result[tab.lower()+'_header_pixel']=pixel
        width,height=map(int,re.findall(r'\d+',adb('shell','wm','size'))[-2:])
        adb('shell','input','swipe',str(width//2),str(height*4//5),str(width//2),str(height//3),'240')
        xml=wait_ui('Expand navigation')
        handle=next(n for n in ET.fromstring(xml).iter('node') if 'Expand navigation' in n.get('content-desc','')+' '+n.get('text',''))
        left,_,right,_=map(int,re.findall(r'\d+',handle.get('bounds')))
        assert right < width*.3, f'Compact navigation did not settle on the left: {left},{right}'
        capture('compact-navigation');tap('Expand navigation');wait_ui('Library');capture('expanded-navigation')
        result['glass_navigation_folds_and_expands']=True
        tap('Settings');wait_ui('Preferences')
        for i in range(5):
            tap('Reading preferences');wait_ui('Reading defaults')
            adb('shell','input','swipe','540','1450','540','600','220')
            adb('shell','input','keyevent','4');wait_ui('Preferences')
        result['repeated_route_return']=True;capture('returned-settings')
        tap('Library');xml=wait_ui('Library')
        assert 'Follow calendar' not in xml
        result['calendar_removed']=True
        tap('Settings');tap('Downloads & cache');scroll_to('Download network:')
        process=adb('shell','pidof',PACKAGE).strip()
        try:
            adb('shell','svc','data','disable');adb('shell','svc','wifi','enable');wait_ui('Download network: Wi-Fi');capture('network-wifi')
            adb('shell','svc','wifi','disable');wait_ui('Download network: Offline');capture('network-offline')
            adb('shell','svc','wifi','enable');wait_ui('Download network: Wi-Fi');capture('network-restored')
            assert adb('shell','pidof',PACKAGE).strip()==process
        except Exception:
            capture('network-failure')
            (OUT/'network-failure-connectivity.txt').write_text(adb('shell','dumpsys','connectivity'),encoding='utf-8')
            (OUT/'network-failure-wifi.txt').write_text(adb('shell','cmd','wifi','status'),encoding='utf-8')
            raise
        finally:
            adb('shell','svc','wifi','enable');adb('shell','svc','data','enable')
        result['network_callbacks_without_restart']=True
        (OUT/'gfxinfo.txt').write_text(adb('shell','dumpsys','gfxinfo',PACKAGE,'framestats'),encoding='utf-8')
        result['passed']=True
    finally:
        try:capture('final')
        except Exception:pass
        (OUT/'verdict.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        (OUT/'logcat.txt').write_text(adb('logcat','-d',check=False),encoding='utf-8')
    print(json.dumps(result))

if __name__=='__main__':main()
