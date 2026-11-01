"""Normalize the approved expression sheet and index bundled character frames."""
import hashlib
import json
from pathlib import Path
from PIL import Image

root=Path(__file__).resolve().parents[1]
folder=root/'assets/characters/xiaxia'
image=Image.open(folder/'sheet.png').convert('RGBA')
w,h=image.size
images={};states={}
for i,name in enumerate(['idle','blink','happy','puzzled']):
    x=i%2*w//2;y=i//2*h//2
    frame=image.crop((x,y,x+w//2,y+h//2)).resize((232,232),Image.Resampling.LANCZOS)
    canvas=Image.new('RGBA',(256,256));canvas.alpha_composite(frame,(12,12))
    target=folder/(name+'.png');canvas.save(target)
    key=hashlib.sha256(target.read_bytes()).hexdigest()
    images[key]=target.relative_to(root).as_posix()
    states[name]={'file':name+'.png','sha256':key}
(root/'assets/characters/index.json').write_text(json.dumps({'schemaVersion':1,'images':images},indent=2)+'\n',encoding='utf-8',newline='\n')
manifest=json.loads((root/'plugins/packages/xiaxia.json').read_text(encoding='utf-8'))
manifest['contributes']['character']={'states':states}
(root/'plugins/packages/xiaxia.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
print('Bundled character frames, hashes and manifest generated.')
