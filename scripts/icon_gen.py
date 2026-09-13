# 应用图标：单一符号源 + 两套尺度
#
# 符号 = 白色圆角日历卡（主色日期格）+ 环绕的两枚换班箭头，点「倒班」这个题。
#
# 为什么要两套尺度：Android 自适应图标的安全区是**直径 66dp 的圆**（画布 108dp），
# 方形符号要内接这个圆，边长上限是 66/√2 ≈ 46.7dp，即画布的 43%。把旧式方形图标
# 那套尺寸直接塞进自适应前景层，圆角就会被蒙版削掉 —— 这正是本文件存在的理由。
# 旧式方形图标（iOS / 非自适应启动器 / Web）没有这个约束，符号可以放到 66%。
#
# 预览：python scripts/icon_gen.py   → work/icon-preview.png
# 落地：python scripts/icon_land.py  → Android / iOS / Web 全套
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ACCENT = (91, 108, 255)          # #5B6CFF 默认主色
ACCENT_DARK = (69, 82, 204)      # 渐变落点：主色加深 24%
WHITE = (255, 255, 255)

CANVAS = 108.0                   # 自适应图标画布边长（dp）
SAFE_DIAM = 66.0 / CANVAS        # 安全圆直径占画布的比例
K_ADAPT = 1.0                    # 自适应前景层的符号尺度
K_LEGACY = 1.45                  # 旧式方形图标：符号缩放到画布的 66%
SUPERSAMPLE = 4                  # 先在 N 倍画布上画，再降采样 —— 细描边需要它

# 符号几何，全部以「画布边长」为单位（k=1.0 时即自适应前景层）
#
# 这几个数是互相咬合的，改一个要连带验另两个：
#   · 环外沿 RING_R + RING_TH/2 ≤ 33/108（安全圆半径，否则圆形蒙版切到箭头）
#   · 卡的圆角外沿 ≤ 环内沿 − 一点余量（否则白卡和箭头粘成一块，monochrome 层尤其明显）
CARD_SIDE = 0.318                # 白卡边长
CARD_RADIUS = 0.30               # 白卡圆角，相对卡的半边长（越大角收得越进）
RING_R = 0.256                   # 箭头环半径（到描边中线）
RING_TH = 0.050                  # 箭头环描边宽度
HEAD_LEN = 0.062                 # 箭头长度
HEAD_HALF_W = 0.038              # 箭头半宽
RING_SPANS = ((128, 292), (-52, 112))   # 两段弧；缺口留给箭头
RING_HEADS = (292, 112)          # 箭头落在每段弧的行进端


def _gradient(W, c1, c2):
    ys, xs = np.mgrid[0:W, 0:W]
    t = (xs + ys).astype(np.float64) / (2.0 * W - 2.0)
    out = np.zeros((W, W, 3), np.float64)
    for i in range(3):
        out[:, :, i] = c1[i] + (c2[i] - c1[i]) * t
    return out.astype(np.uint8)


def _card(W, k):
    c = W / 2.0
    half = W * CARD_SIDE * k / 2.0
    return c, half


def _cells(W, k):
    """3×3 日期格，返回 (x0, y0, x1, y1, radius)。"""
    c, half = _card(W, k)
    gl, gr = c - half * 0.66, c + half * 0.66
    gt, gb = c - half * 0.46, c + half * 0.68
    cw, ch = (gr - gl) / 3.0, (gb - gt) / 3.0
    peg = min(cw, ch) * 0.42
    out = []
    for i in range(3):
        for j in range(3):
            x, y = gl + cw * (j + 0.5), gt + ch * (i + 0.5)
            out.append((x - peg, y - peg, x + peg, y + peg, peg * 0.34))
    return out


def _ring(W, k):
    c = W / 2.0
    return c, W * RING_R * k, W * RING_TH * k


def _head(c, R, ang, W, k):
    """弧末端箭头：沿切线指向前进方向。"""
    hs, hw = W * HEAD_LEN * k, W * HEAD_HALF_W * k
    ar = np.radians(ang)
    tx, ty = -np.sin(ar), np.cos(ar)      # 切线（角度增大的方向）
    nx, ny = np.cos(ar), np.sin(ar)       # 径向外
    px, py = c + R * np.cos(ar), c + R * np.sin(ar)
    bx, by = px - tx * hs * 0.15, py - ty * hs * 0.15
    return [(px + tx * hs, py + ty * hs),
            (bx + nx * hw, by + ny * hw),
            (bx - nx * hw, by - ny * hw)]


def _draw_color(d, W, k):
    c, half = _card(W, k)
    d.rounded_rectangle((c - half, c - half, c + half, c + half),
                        radius=half * CARD_RADIUS, fill=WHITE)
    for x0, y0, x1, y1, r in _cells(W, k):
        d.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=ACCENT)
    rc, R, th = _ring(W, k)
    for a0, a1 in RING_SPANS:
        d.arc((rc - R, rc - R, rc + R, rc + R), a0, a1,
              fill=WHITE, width=max(1, int(round(th))))
    for a in RING_HEADS:
        d.polygon(_head(rc, R, a, W, k), fill=WHITE)


def _draw_mono(m, W, k):
    """单色层：白色剪影 + 镂空的日期格。系统负责上色，我们只给形状。"""
    c, half = _card(W, k)
    m.rounded_rectangle((c - half, c - half, c + half, c + half),
                        radius=half * CARD_RADIUS, fill=255)
    for x0, y0, x1, y1, r in _cells(W, k):
        m.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=0)
    rc, R, th = _ring(W, k)
    for a0, a1 in RING_SPANS:
        m.arc((rc - R, rc - R, rc + R, rc + R), a0, a1,
              fill=255, width=max(1, int(round(th))))
    for a in RING_HEADS:
        m.polygon(_head(rc, R, a, W, k), fill=255)


def _supersample(size, draw_fn, mode):
    """在 SUPERSAMPLE 倍画布上画，再降采样 —— 这是细描边唯一的平滑手段。"""
    W = int(size) * SUPERSAMPLE
    img = Image.new(mode, (W, W), 0 if mode == 'L' else (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(img), W)
    return img.resize((int(size), int(size)), Image.LANCZOS)


def square_icon(size):
    """旧式方形图标（iOS / 非自适应启动器 / Web）：满幅渐变底 + 大号符号。"""
    W = int(size) * SUPERSAMPLE
    img = Image.fromarray(_gradient(W, ACCENT, ACCENT_DARK), 'RGB')
    _draw_color(ImageDraw.Draw(img), W, K_LEGACY)
    return img.resize((int(size), int(size)), Image.LANCZOS)


def adaptive_background(size):
    """自适应背景层：满幅渐变（108dp 整块，系统只截中间可见的部分）。"""
    return Image.fromarray(
        _gradient(int(size) * SUPERSAMPLE, ACCENT, ACCENT_DARK), 'RGB'
    ).resize((int(size), int(size)), Image.LANCZOS)


def adaptive_foreground(size):
    """自适应前景层：符号按内接圆缩在安全区内，四周留白给系统蒙版。"""
    return _supersample(size, lambda d, W: _draw_color(d, W, K_ADAPT), 'RGBA')


def adaptive_monochrome(size):
    """自适应单色层（Android 13+ 主题图标）：白色剪影 + alpha 镂空。"""
    mask = _supersample(size, lambda m, W: _draw_mono(m, W, K_ADAPT), 'L')
    out = Image.new('RGBA', mask.size, WHITE + (0,))
    out.putalpha(mask)
    return out


def adaptive_composite(size):
    """背景 + 前景压平（Web maskable 用；自适应图标由系统自己叠）。"""
    bg = adaptive_background(size).convert('RGBA')
    return Image.alpha_composite(bg, adaptive_foreground(size)).convert('RGB')


def _mask_circle(W, inset):
    ys, xs = np.mgrid[0:W, 0:W]
    c = (W - 1) / 2.0
    r = c * (1.0 - inset)
    return np.clip((r - np.sqrt((xs - c) ** 2 + (ys - c) ** 2)) * 2 + 0.5, 0, 1)


def _mask_squircle(W, n=4.0, inset=0.0):
    ys, xs = np.mgrid[0:W, 0:W]
    c = (W - 1) / 2.0
    r = c * (1.0 - inset)
    v = (np.abs(xs - c) / r) ** n + (np.abs(ys - c) / r) ** n
    return np.clip((1.0 - v) * r * 1.2 + 0.5, 0, 1)


def _tint(mono, color):
    out = Image.new('RGBA', mono.size, color + (255,))
    out.putalpha(mono.getchannel('A'))
    return out


def _mono_plate(size, plate, ink):
    """按 Android 13 主题图标的画法预览单色层：系统给底色，符号被染成一色。"""
    img = Image.new('RGBA', (int(size), int(size)), plate + (255,))
    return Image.alpha_composite(img, _tint(adaptive_monochrome(size), ink))


def make_sheet(out='work/icon-preview.png'):
    """出图给眼睛看：方形 / 圆形蒙版 / 方圆蒙版 / 单色两层 / 48px 实尺。"""
    def masked(img, mask):
        a = np.asarray(img.convert('RGBA'), np.float64)
        return Image.fromarray((a * mask[..., None]).astype(np.uint8))

    tile, gap, left = 208, 22, 34
    heads = ['方形（iOS / 旧启动器）', '自适应 · 圆形蒙版', '自适应 · 方圆蒙版',
             '主题图标 · 浅色', '主题图标 · 深色', '48px 实尺']
    cols = len(heads)
    sw = left * 2 + cols * tile + (cols - 1) * gap
    sh = 132 + tile + 40
    sheet = Image.new('RGB', (sw, sh), (24, 24, 30))
    sd = ImageDraw.Draw(sheet)
    font = _font('msyhbd.ttc', 26)
    small = _font('msyh.ttc', 17)
    extent = (RING_R + RING_TH / 2) * 2 * K_ADAPT * 100
    sd.text((left, 20), '应用图标 · 倒班环箭头', font=font, fill=(238, 240, 248))
    sd.text((left, 56),
            f'符号最外沿占画布 {extent:.0f}%，安全圆是 {SAFE_DIAM * 100:.0f}% —— '
            '方形符号若不按内接圆缩，圆角会被蒙版削掉',
            font=small, fill=(150, 156, 176))
    for i, h in enumerate(heads):
        sd.text((left + i * (tile + gap), 88), h, font=small, fill=(150, 156, 176))

    y = 132
    W = 512
    square = square_icon(W)
    fg = adaptive_foreground(W)
    composite = Image.alpha_composite(adaptive_background(W).convert('RGBA'), fg)
    tiles = [square.convert('RGB'),
             masked(composite, _mask_circle(W, 0.335)).convert('RGB'),
             masked(composite, _mask_squircle(W, 4.0, 0.30)).convert('RGB')]
    for plate, ink in (((211, 227, 253), (4, 30, 73)),      # 浅色主题
                       ((8, 66, 160), (211, 227, 253))):    # 深色主题
        tiles.append(masked(_mono_plate(W, plate, ink),
                            _mask_circle(W, 0.335)).convert('RGB'))

    for i, t in enumerate(tiles):
        sheet.paste(t.resize((tile, tile), Image.LANCZOS),
                    (left + i * (tile + gap), y))
    tiny = composite.convert('RGB').resize((48, 48), Image.LANCZOS)
    cx = left + 5 * (tile + gap) + (tile - 48) // 2
    cy = y + (tile - 48) // 2
    sd.rectangle((cx - 6, cy - 6, cx + 54, cy + 54), outline=(74, 78, 96), width=1)
    sheet.paste(tiny, (cx, cy))

    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    sheet.save(out)
    print(f'{out}  {sheet.size[0]}x{sheet.size[1]}')


def _font(name, size):
    try:
        return ImageFont.truetype(f'C:/Windows/Fonts/{name}', size)
    except OSError:
        return ImageFont.load_default()


if __name__ == '__main__':
    make_sheet()
