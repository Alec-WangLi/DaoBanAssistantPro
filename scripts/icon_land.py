# 落地应用图标到全部尺寸：python scripts/icon_land.py
#
# 产物分两类，别混：
#
#   · 自适应图标（Android 8.0+）—— 本项目 minSdk 26，所以真机上**永远**走这套。
#     `mipmap-anydpi-v26/ic_launcher.xml` 指向 drawable-*/ 下的三层 PNG：
#     background（满幅渐变）/ foreground（安全区内的符号，四周留白给蒙版）/
#     monochrome（白色剪影，Android 13+ 主题图标用，系统自己上色）。
#     三层都按 108dp 画布出五档密度。
#
#   · 旧式方形图标（iOS / Web / 非自适应启动器）：满幅方形，符号放大到画布 66%。
#     `mipmap-*/ic_launcher.png` 属于这一类的兜底 —— 有 anydpi-v26 在，真机用不到它，
#     留着是防「把 anydpi 删了」那天图标直接没有。
#
# 改图形请改 scripts/icon_gen.py，本文件只管落地。
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icon_gen as g  # noqa: E402

ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
RES = 'app/android/app/src/main/res'

# Android 密度名 → 缩放倍数（108dp 画布在 mdpi 上是 108px）
DENSITIES = [('mdpi', 1.0), ('hdpi', 1.5), ('xhdpi', 2.0),
             ('xxhdpi', 3.0), ('xxxhdpi', 4.0)]

ICON_XML = '''<?xml version="1.0" encoding="utf-8"?>
<!-- 由 scripts/icon_land.py 生成，不要手改 —— 图形改 scripts/icon_gen.py。 -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''


def write(rel, img):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    print(f'{rel}  {img.size[0]}x{img.size[1]}')


# ---- Android：自适应三层 + 旧式兜底 ----
for dpi, scale in DENSITIES:
    px = int(round(g.CANVAS * scale))
    write(f'{RES}/drawable-{dpi}/ic_launcher_background.png',
          g.adaptive_background(px))
    write(f'{RES}/drawable-{dpi}/ic_launcher_foreground.png',
          g.adaptive_foreground(px))
    write(f'{RES}/drawable-{dpi}/ic_launcher_monochrome.png',
          g.adaptive_monochrome(px))

for dpi, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                ('xxhdpi', 144), ('xxxhdpi', 192)]:
    write(f'{RES}/mipmap-{dpi}/ic_launcher.png', g.square_icon(px))

xml_rel = f'{RES}/mipmap-anydpi-v26/ic_launcher.xml'
xml_abs = os.path.join(ROOT, xml_rel)
os.makedirs(os.path.dirname(xml_abs), exist_ok=True)
with open(xml_abs, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write(ICON_XML)
print(f'{xml_rel}')

# ---- iOS ----
master = g.square_icon(1024)
IOS = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
}
for fname, size in IOS.items():
    write(f'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/{fname}',
          master.resize((size, size), Image.LANCZOS))

# ---- Web ----
write('app/web/icons/Icon-192.png', master.resize((192, 192), Image.LANCZOS))
write('app/web/icons/Icon-512.png', master.resize((512, 512), Image.LANCZOS))
# maskable 要求内容落在直径 80% 的圆内，比 Android 的 66/108 宽松；
# 直接用自适应那套尺度（符号最外沿 56%）压平成整张，别另立一套比例。
write('app/web/icons/Icon-maskable-192.png', g.adaptive_composite(192))
write('app/web/icons/Icon-maskable-512.png', g.adaptive_composite(512))
write('app/web/favicon.png', master.resize((16, 16), Image.LANCZOS))

print('\nAll done.')
