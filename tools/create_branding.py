"""Draw the original Manxia bookcase mark at platform icon sizes."""
from pathlib import Path
from PIL import Image, ImageDraw
import json

root = Path(__file__).resolve().parent.parent
canvas = Image.new('RGB', (1024, 1024), '#47775E')
draw = ImageDraw.Draw(canvas)
paper = '#F7F7F2'
draw.rounded_rectangle((196, 205, 340, 755), radius=12, fill=paper)
draw.line((244, 260, 294, 260), fill='#47775E', width=8)
draw.line((244, 688, 294, 688), fill='#47775E', width=8)
draw.polygon([(387, 232), (690, 170), (690, 718), (387, 780)], fill=paper)
draw.polygon([(690, 170), (748, 200), (748, 748), (690, 718)], fill='#D8E2D6')
draw.line((425, 306, 648, 260), fill='#47775E', width=10)
draw.line((425, 343, 648, 297), fill='#47775E', width=5)
draw.line((160, 810, 810, 810), fill=paper, width=12)

def save(path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.resize((size,size),Image.Resampling.LANCZOS).save(path)

save(root/'assets/branding/icon.png',512)
save(root/'web/favicon.png',48)
for name in ['Icon-192.png','Icon-maskable-192.png']: save(root/'web/icons'/name,192)
for name in ['Icon-512.png','Icon-maskable-512.png']: save(root/'web/icons'/name,512)
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    save(root/f'android/app/src/main/res/mipmap-{density}/ic_launcher.png',size)
manifest_path=root/'web/manifest.json'
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
manifest.update(name='漫匣 · Manxia',short_name='漫匣',description='把喜欢的故事，留在手边。',background_color='#F7F7F2',theme_color='#47775E')
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Manxia platform icons created')
