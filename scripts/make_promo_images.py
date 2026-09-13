# 把 app/tool/promo 渲染出来的原始截图合成宣传图。
#
#   python scripts/make_promo_images.py
#
# 产物分两处，别混：
#
#   docs/images/*.png    README 用：**透明底** + 套机身外框。透明底是有意的 ——
#                        GitHub 的 README 在浅色/深色主题下都会渲染，带底色的大图
#                        会在另一种主题上糊成一块。入库。
#   work/promo-out/*.png 酷安用：更大，另加一张带标题的封面图。不入库（work/ 已
#                        gitignore）—— 它只是拿去发帖的素材，不进仓库。
#
# 图形的唯一来源是 app/tool/promo/render_promo_test.dart，本文件只负责合成。
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
SRC = os.path.join(ROOT, 'app', 'build', 'promo')
OUT_WEB = os.path.join(ROOT, 'docs', 'images')
OUT_COOLAPK = os.path.join(ROOT, 'work', 'promo-out')

ACCENT = (91, 108, 255)
ACCENT_D = (44, 34, 130)
BODY = (22, 23, 28)

# (源文件, README 里的文件名, 封面/拼图用的短标题)
SHOTS = [
    ('01_calendar_light', 'shot-calendar.png', '日历'),
    ('02_alarm', 'shot-alarm.png', '班次闹钟'),
    ('03_editor', 'shot-editor.png', '排班编辑器'),
    ('04_todos', 'shot-todos.png', '待办'),
    ('06_templates', 'shot-templates.png', '倒班方式'),
    ('10_profile_permissions', 'shot-permissions.png', '权限自检'),
    ('05_ringing', 'shot-ringing.png', '响铃界面'),
    ('08_calendar_dark', 'shot-calendar-dark.png', '深色'),
    ('07_profile', 'shot-profile.png', '外观'),
    ('09_calendar_wide', 'shot-wide.png', '横屏分栏'),
]


def _font(name, size):
    try:
        return ImageFont.truetype(f'C:/Windows/Fonts/{name}', size)
    except OSError:
        return ImageFont.load_default()


def _rounded_mask(w, h, r):
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)
    return m


def framed(slug, width, bezel=None):
    """截图（传 slug，不带 .png）→ 圆角机身 + 柔和投影，透明底。"""
    shot = Image.open(os.path.join(SRC, f'{slug}.png')).convert('RGB')
    scale = width / shot.width
    shot = shot.resize((width, max(1, round(shot.height * scale))), Image.LANCZOS)
    bezel = bezel if bezel is not None else max(8, round(width * 0.035))
    radius = round(width * 0.115)
    w, h = shot.size
    W, H = w + bezel * 2, h + bezel * 2

    body = Image.new('RGBA', (W, H), BODY + (255,))
    body.putalpha(_rounded_mask(W, H, radius + bezel))
    screen = shot.convert('RGBA')
    screen.putalpha(_rounded_mask(w, h, radius))
    body.alpha_composite(screen, (bezel, bezel))

    pad = round(W * 0.10)
    canvas = Image.new('RGBA', (W + pad * 2, H + pad * 2), (0, 0, 0, 0))
    sh = Image.new('L', canvas.size, 0)
    sh.paste(body.getchannel('A'), (pad, pad + round(H * 0.02)))
    sh = sh.filter(ImageFilter.GaussianBlur(round(W * 0.045)))
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    layer.putalpha(sh.point(lambda v: int(v * 0.34)))
    canvas.alpha_composite(layer)
    canvas.alpha_composite(body, (pad, pad))
    return canvas


def _gradient(W, H, c1, c2):
    ys, xs = np.mgrid[0:H, 0:W]
    t = np.clip(xs / max(1, W - 1) * 0.6 + ys / max(1, H - 1) * 0.4, 0, 1)
    arr = np.zeros((H, W, 3), np.float64)
    for i in range(3):
        arr[:, :, i] = c1[i] + (c2[i] - c1[i]) * t
    return Image.fromarray(arr.astype(np.uint8), 'RGB').convert('RGBA')


def hero_strip(widths, gap_ratio=0.10):
    """透明底的三联拼图，给 README 开头用。"""
    imgs = [framed(p, widths) for p, _, _ in SHOTS[:3]]
    gap = round(widths * gap_ratio)
    W = sum(i.width for i in imgs) + gap * (len(imgs) - 1)
    H = max(i.height for i in imgs)
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    x = 0
    for i in imgs:
        out.alpha_composite(i, (x, (H - i.height) // 2))
        x += i.width + gap
    return out


def cover(W=1400, H=980):
    """酷安首图：品牌渐变底 + 标题 + 三台机器。

    高度与机器尺寸是咬合的：`framed()` 会在机身外再留一圈投影边距
    （机身宽 × 0.10），算漏了机器底部就会被画布切掉 —— 实际踩过一次。
    """
    img = _gradient(W, H, ACCENT, ACCENT_D)
    d = ImageDraw.Draw(img)
    f_t = _font('msyhbd.ttc', 82)
    f_s = _font('msyh.ttc', 40)

    title = '倒班助手 Pro'
    tw = d.textlength(title, font=f_t)
    d.text(((W - tw) / 2, 52), title, font=f_t, fill=(255, 255, 255))
    sub = '排班日历 · 班次闹钟 · 待办日程　|　无广告 · 无账号 · 纯本地 · 开源'
    sw = d.textlength(sub, font=f_s)
    d.text(((W - sw) / 2, 156), sub, font=f_s, fill=(216, 221, 255))

    widths = 290
    imgs = [framed(p, widths) for p, _, _ in SHOTS[:3]]
    gap = 34
    total = sum(i.width for i in imgs) + gap * 2
    x = (W - total) // 2
    y = 236
    assert y + imgs[0].height <= H, '封面画布太矮，机器会被切掉'
    for i in imgs:
        img.alpha_composite(i, (x, y + (imgs[0].height - i.height) // 2))
        x += i.width + gap
    return img.convert('RGB')


def main():
    missing = [p for p, _, _ in SHOTS
               if not os.path.exists(os.path.join(SRC, f'{p}.png'))]
    if missing:
        sys.exit('缺少渲染图：%s\n先跑 toolchain/flutter/bin/flutter test '
                 'tool/promo/render_promo_test.dart' % '、'.join(missing))

    os.makedirs(OUT_WEB, exist_ok=True)
    os.makedirs(OUT_COOLAPK, exist_ok=True)

    for src, name, _ in SHOTS:
        img = framed(src, 440)
        img.save(os.path.join(OUT_WEB, name), optimize=True)
        print(f'docs/images/{name}  {img.size[0]}x{img.size[1]}')

    strip = hero_strip(430)
    strip.save(os.path.join(OUT_WEB, 'hero.png'), optimize=True)
    print(f'docs/images/hero.png  {strip.size[0]}x{strip.size[1]}')

    cv = cover()
    cv.save(os.path.join(OUT_COOLAPK, 'cover.png'), optimize=True)
    print(f'work/promo-out/cover.png  {cv.size[0]}x{cv.size[1]}')
    for src, name, _ in SHOTS:
        big = framed(src, 640)
        big.save(os.path.join(OUT_COOLAPK, name), optimize=True)
        print(f'work/promo-out/{name}  {big.size[0]}x{big.size[1]}')

    total = sum(os.path.getsize(os.path.join(OUT_WEB, f))
                for f in os.listdir(OUT_WEB))
    print(f'\ndocs/images 合计 {total / 1024 / 1024:.2f} MB')


if __name__ == '__main__':
    main()
