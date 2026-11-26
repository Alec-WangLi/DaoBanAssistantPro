# 小红书图文用的 3:4 配图（1080×1440）。
#
#   python scripts/make_xhs_images.py
#
# 小红书的信息流是 3:4 竖图，酷安那套是 1:2.38 的长截图 —— 直接发上去两边留白、
# 字小得看不见。这里把同一批 promo 截图重新排成 3:4：渐变底 + 一句标题 + 一台机器。
#
# 产物 dist/xhs/v0140/01-cover.png … 09-dark.png（dist/ 已 gitignore）。
# 截图源在 app/build/promo/，必须先跑：
#   toolchain/flutter/bin/flutter test tool/promo/render_promo_test.dart
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))

from make_promo_images import ACCENT, ACCENT_D  # noqa: E402
from make_promo_images import _font, _gradient, framed  # noqa: E402

SOFT = (216, 221, 255)

W, H = 1080, 1440
OUT = ROOT / 'dist' / 'xhs' / 'v0140'

# (源截图 slug, 输出名, 标题)  —— 标题一行，超过 12 字会自己缩字号
CARDS = [
    ('01_calendar_light', '02-calendar', '这个月怎么倒，一眼看完'),
    ('11_stats', '03-stats', '上了多少小时，它自己算'),
    ('02_alarm', '04-alarm', '闹钟跟着排班自己走'),
    ('05_ringing', '05-ringing', '锁屏、后台都会顶上来'),
    ('06_templates', '06-templates', '20 种倒班方式，挑一个最像的'),
    ('04_todos', '07-todos', '交班开会，按班次自动出现'),
    ('10_profile_permissions', '08-permissions', '不开会怎样，每一项都写清'),
    ('08_calendar_dark', '09-dark', '深色模式，字号四档'),
]


def _fit(d, text, max_w, start):
    """标题一行放不下就缩字号，不折行 —— 3:4 的顶部放不下两行。"""
    size = start
    while size > 40:
        f = _font('msyhbd.ttc', size)
        if d.textlength(text, font=f) <= max_w:
            return f
        size -= 2
    return _font('msyhbd.ttc', 40)


def _center(d, text, font, y, fill):
    d.text(((W - d.textlength(text, font=font)) / 2, y), text, font=font, fill=fill)


def cover():
    img = _gradient(W, H, ACCENT, ACCENT_D)
    d = ImageDraw.Draw(img)
    _center(d, '倒班助手 Pro', _font('msyhbd.ttc', 116), 88, (255, 255, 255))
    _center(d, '排班日历 · 班次闹钟 · 待办日程', _font('msyh.ttc', 46), 240, SOFT)
    _center(d, '无广告 · 无账号 · 纯本地 · 开源', _font('msyh.ttc', 40), 310, (196, 204, 255))

    # 两台机器而不是三台：3:4 比酷安首图窄，三台挤进来每台只有 1/3 宽，
    # 上面那行小字就看不见了。两台底对齐 —— 顶对齐时高的统计屏会顶到副标题。
    shots = [framed(s, 370) for s in ('01_calendar_light', '11_stats')]
    gap = 16
    total = sum(i.width for i in shots) + gap
    x = (W - total) // 2
    base = 1410
    for im in shots:
        img.alpha_composite(im, (x, base - im.height))
        x += im.width + gap
    return img.convert('RGB')


def card(slug, headline):
    img = _gradient(W, H, ACCENT, ACCENT_D)
    d = ImageDraw.Draw(img)
    _center(d, headline, _fit(d, headline, W - 140, 68), 92, (255, 255, 255))

    phone = framed(slug, 470)
    # 统计那屏是 840×2000（比别的长一截），按同一宽度套框会顶到标题、下沿还会被裁。
    # 统一限高到「标题下方 230 ～ 底边 60」这一条带里，超了就等比缩。
    max_h = H - 290
    if phone.height > max_h:
        k = max_h / phone.height
        phone = phone.resize((round(phone.width * k), max_h), Image.LANCZOS)
    # 底对齐：3:4 图在信息流里会被裁掉一点下沿，留出 60px 余量才不会切到手机的下巴。
    y = H - 60 - phone.height
    img.alpha_composite(phone, ((W - phone.width) // 2, max(y, 230)))
    return img.convert('RGB')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    cover().save(OUT / '01-cover.png', optimize=True)
    print(f'dist/xhs/v0140/01-cover.png  {W}×{H}')
    for slug, name, headline in CARDS:
        card(slug, headline).save(OUT / f'{name}.png', optimize=True)
        print(f'dist/xhs/v0140/{name}.png  {W}×{H}  {headline}')
    total = sum(p.stat().st_size for p in OUT.glob('*.png')) / 1024 / 1024
    print(f'\n{len(CARDS) + 1} 张，合计 {total:.1f} MB')


if __name__ == '__main__':
    main()
