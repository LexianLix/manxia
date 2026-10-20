from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
FONT=ROOT/'assets/fonts/SourceHanSerifCN-Regular.otf'
BG='#20382b'
PAPER='#f7f6ee'
def icon(size,foreground=False,maskable=False):
    scale=4
    image=Image.new('RGBA',(size*scale,size*scale),(0,0,0,0) if foreground else BG)
    draw=ImageDraw.Draw(image)
    if not foreground and not maskable:
        draw.rectangle((size*.14*scale,size*.14*scale,size*.86*scale,size*.86*scale),outline='#829b82',width=max(1,round(size*.012*scale)))
    font=ImageFont.truetype(str(FONT),round(size*scale*(.48 if maskable or foreground else .6)))
    box=draw.textbbox((0,0),'匣',font=font)
    x=(size*scale-(box[2]-box[0]))/2-box[0]
    y=(size*scale-(box[3]-box[1]))/2-box[1]
    draw.text((x,y),'匣',font=font,fill=PAPER)
    return image.resize((size,size),Image.Resampling.LANCZOS)
for bucket,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    path=ROOT/f'android/app/src/main/res/mipmap-{bucket}/ic_launcher.png'
    path.parent.mkdir(parents=True,exist_ok=True)
    icon(size).save(path)
for size in (192,512):
    icon(size).save(ROOT/f'web/icons/Icon-{size}.png')
    icon(size,maskable=True).save(ROOT/f'web/icons/Icon-maskable-{size}.png')
icon(64).save(ROOT/'web/favicon.png')
foreground=ROOT/'android/app/src/main/res/drawable/manxia_launcher_foreground.png'
icon(432,foreground=True).save(foreground)
adaptive=ROOT/'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'
adaptive.parent.mkdir(parents=True,exist_ok=True)
adaptive.write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/manxia_launcher_background" />
    <foreground android:drawable="@drawable/manxia_launcher_foreground" />
</adaptive-icon>
''',encoding='utf-8')
colors=ROOT/'android/app/src/main/res/values/manxia_colors.xml'
colors.write_text('<?xml version="1.0" encoding="utf-8"?><resources><color name="manxia_launcher_background">#20382B</color></resources>',encoding='utf-8')
print('Manxia launcher and web icons regenerated from the bundled OFL font.')
