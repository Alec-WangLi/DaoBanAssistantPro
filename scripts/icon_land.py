# 落地应用图标到全部尺寸：python scripts/icon_land.py
# 读取 scripts/icon_gen.py 的 render_icon，输出 Android / iOS / Web 全部图标文件。
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from icon_gen import render_icon  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))


def write(rel, img):
    p = os.path.join(ROOT, rel)
    img.save(p)
    print(f'{rel}  {img.size[0]}x{img.size[1]}')


master = render_icon('calendar', 1024, 1.0)

for dpi, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                  ('xxhdpi', 144), ('xxxhdpi', 192)]:
    write(f'app/android/app/src/main/res/mipmap-{dpi}/ic_launcher.png',
          master.resize((size, size), Image.LANCZOS))

ios = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
}
for fname, size in ios.items():
    write(f'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/{fname}',
          master.resize((size, size), Image.LANCZOS))

write('app/web/icons/Icon-192.png', master.resize((192, 192), Image.LANCZOS))
write('app/web/icons/Icon-512.png', master.resize((512, 512), Image.LANCZOS))
# maskable：符号缩进中心安全区（card_scale 0.70），避免系统蒙版裁掉圆角卡
masked = render_icon('calendar', 1024, 0.70)
write('app/web/icons/Icon-maskable-192.png', masked.resize((192, 192), Image.LANCZOS))
write('app/web/icons/Icon-maskable-512.png', masked.resize((512, 512), Image.LANCZOS))
write('app/web/favicon.png', master.resize((16, 16), Image.LANCZOS))

print('\nAll done.')