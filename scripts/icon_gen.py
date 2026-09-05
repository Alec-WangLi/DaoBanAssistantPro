# 应用图标概念预览生成（三个方向：日历 / 时钟 / 日历+换班箭头）
# 中性底 #F5F6FA + 主色渐变玻璃符号（默认强调色 #5B6CFF）
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ACCENT = (91, 108, 255)          # #5B6CFF 默认主色
ACCENT_DARK = tuple(int(c * 0.76) for c in ACCENT)  # 渐变落点：加深 24%
BG = (245, 246, 250)             # #F5F6FA 中性「简约白」
WHITE = (255, 255, 255)
SHEET_BG = (236, 238, 244)
LABEL = (38, 40, 54)


def np_gradient(W, H, c1, c2):
    ys, xs = np.mgrid[0:H, 0:W]
    t = (xs + ys).astype(np.float64) / (W + H - 2.0)
    out = np.zeros((H, W, 3), np.float64)
    for i in range(3):
        out[:, :, i] = c1[i] + (c2[i] - c1[i]) * t
    return out.astype(np.uint8)


def rounded_mask(W, H, box, r):
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=r, fill=255)
    return np.asarray(m, np.float64) / 255.0


def _draw_calendar(d, W, c, half, swap=False):
    x0, y0 = c - half, c - half
    x1, y1 = c + half, c + half
    # 顶部双「装订环」
    bw, bh = int(W * 0.052), int(W * 0.085)
    bx, by = int(W * 0.052), -int(W * 0.016)
    rr = int(W * 0.02)
    d.rounded_rectangle((x0 + bx, y0 + by, x0 + bx + bw, y0 + by + bh), radius=rr, fill=WHITE)
    d.rounded_rectangle((x1 - bx, y0 + by, x1 - bx + bw, y0 + by + bh), radius=rr, fill=WHITE)
    # 日期格
    gl = x0 + int(W * 0.125)
    gr = x1 - int(W * 0.125)
    gt = y0 + int(W * 0.185)
    gb = y1 - int(W * 0.125)
    cell_w = (gr - gl) / 3.0
    cell_h = (gb - gt) / 3.0
    peg = min(cell_w, cell_h) * 0.52
    if swap:
        rows = (0, 2)  # 只留顶行与底行，中间放换班箭头
    else:
        rows = (0, 1, 2)
    for i in rows:
        for j in range(3):
            cx = gl + cell_w * (j + 0.5)
            cy = gt + cell_h * (i + 0.5)
            d.rounded_rectangle(
                (cx - peg, cy - peg * 0.9, cx + peg, cy + peg * 0.9),
                radius=int(peg * 0.32), fill=WHITE)
    if swap:
        cy = (gt + gb) / 2.0
        sz = cell_w * 0.36
        lx = gl + cell_w * 0.85
        rx = gr - cell_w * 0.85
        d.polygon([(lx, cy), (lx + sz, cy - sz * 0.75), (lx + sz, cy + sz * 0.75)], fill=WHITE)
        d.polygon([(rx, cy), (rx - sz, cy - sz * 0.75), (rx - sz, cy + sz * 0.75)], fill=WHITE)


def _draw_clock(d, W, c):
    R = int(W * 0.215)
    th = max(2, int(W * 0.040))
    d.ellipse((c - R, c - R, c + R, c + R), outline=WHITE, width=th)
    tr, td = int(W * 0.013), int(W * 0.195)
    for ang in (-90, 0, 90, 180):
        tx = c + td * np.cos(np.radians(ang))
        ty = c + td * np.sin(np.radians(ang))
        d.ellipse((tx - tr, ty - tr, tx + tr, ty + tr), fill=WHITE)
    d.line((c, c, c + W * 0.125 * np.cos(np.radians(120)),
            c + W * 0.125 * np.sin(np.radians(120))), fill=WHITE, width=int(W * 0.034))
    d.line((c, c, c + W * 0.185 * np.cos(np.radians(-90)),
            c + W * 0.185 * np.sin(np.radians(-90))), fill=WHITE, width=int(W * 0.026))
    cr = int(W * 0.030)
    d.ellipse((c - cr, c - cr, c + cr, c + cr), fill=WHITE)


def render_icon(variant, W=768, card_scale=1.0):
    H = W
    bg = np.zeros((H, W, 3), np.uint8)
    bg[:] = BG
    grad = np_gradient(W, H, ACCENT, ACCENT_DARK)
    c = W // 2
    half = int(W * 0.30 * card_scale)
    r = int(W * 0.10)
    box = (c - half, c - half, c + half, c + half)
    cm = rounded_mask(W, H, box, r)
    card = (grad * cm[..., None] + bg * (1 - cm[..., None])).astype(np.uint8)
    im = Image.fromarray(card, 'RGB')
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(box, radius=r, outline=WHITE, width=max(1, int(W * 0.012)))
    # 玻璃顶部高光（卡片内线性白→透明）
    ys, xs = np.mgrid[0:H, 0:W]
    span = 0.34 * (2 * half)
    a = np.clip(0.42 * (1.0 - (ys - (c - half)) / span), 0, 1) * cm
    im = Image.fromarray((np.asarray(im, np.float64) * (1 - a[..., None]) + WHITE * a[..., None]).astype(np.uint8), 'RGB')
    d = ImageDraw.Draw(im)
    if variant == 'calendar':
        _draw_calendar(d, W, c, half)
    elif variant == 'clock':
        _draw_clock(d, W, c)
    elif variant == 'calendars':
        _draw_calendar(d, W, c, half, swap=True)
    return im


def make_sheet():
    size, gap, top = 480, 48, 28
    fs = [('1  Calendar', 'calendar'), ('2  Clock', 'clock'),
          ('3  Calendar + shift arrows', 'calendars')]
    sw = 3 * size + 2 * gap
    sh = top + size + 92
    sheet = Image.new('RGB', (sw, sh), SHEET_BG)
    try:
        font = ImageFont.truetype('C:/Windows/Fonts/seguisb.ttf', 40)
    except OSError:
        font = ImageFont.load_default()
    for i, (label, variant) in enumerate(fs):
        icon = render_icon(variant).resize((size, size), Image.LANCZOS)
        sheet.paste(icon, (top + i * (size + gap), top))
        d = ImageDraw.Draw(sheet)
        tw = d.textlength(label, font=font)
        d.text((top + i * (size + gap) + (size - tw) / 2, top + size + 28),
               label, font=font, fill=LABEL)
    fname = os.environ.get('ICON_SHEET', 'work/icon-preview.png')
    os.makedirs(os.path.dirname(fname) or '.', exist_ok=True)
    sheet.save(fname)


if __name__ == '__main__':
    make_sheet()
    print('work/icon-preview.png written')