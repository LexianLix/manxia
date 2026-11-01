"""Package the approved transparent Xiaxia artwork into launcher resources."""
from pathlib import Path
import math
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/xiaxia-source.png'


def artwork():
    image = Image.open(SOURCE).convert('RGBA')
    if image.getextrema()[3][0] != 0:
        raise ValueError('The launcher artwork must preserve its transparency')
    return image.crop(image.getchannel('A').getbbox())


def icon(image, size, safe_circle=None):
    """Resize only; Android and PWA masks must not cut the character's ears."""
    factor = size * .92 / max(image.size)
    if safe_circle is not None:
        alpha = image.getchannel('A')
        pixels = alpha.load()
        cx, cy = image.width / 2, image.height / 2
        radius = max(
            math.hypot(x - cx, y - cy)
            for y in range(image.height)
            for x in range(image.width)
            if pixels[x, y] > 8
        )
        factor = min(factor, size * safe_circle / radius)
    scaled = image.resize(
        (max(1, round(image.width * factor)), max(1, round(image.height * factor))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new('RGBA', (size, size))
    canvas.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    return canvas


def generate():
    image = artwork()
    icon(image, 512).save(ROOT / 'assets/branding/icon.png')
    for bucket, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
        icon(image, size).save(ROOT / f'android/app/src/main/res/mipmap-{bucket}/ic_launcher.png')
    for size in (192, 512):
        icon(image, size).save(ROOT / f'web/icons/Icon-{size}.png')
        icon(image, size, safe_circle=.38).save(ROOT / f'web/icons/Icon-maskable-{size}.png')
    icon(image, 64).save(ROOT / 'web/favicon.png')
    # Adaptive layers are 108dp; keep the artwork within the 66dp safe circle.
    icon(image, 432, safe_circle=32/108).save(
        ROOT / 'android/app/src/main/res/drawable/manxia_launcher_foreground.png'
    )
    (ROOT / 'android/app/src/main/res/values/manxia_colors.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>'
        '<color name="manxia_launcher_background">#00000000</color></resources>\n',
        encoding='utf-8',
    )
    print('Transparent Xiaxia Android, web and branding icons packaged.')


if __name__ == '__main__':
    generate()
