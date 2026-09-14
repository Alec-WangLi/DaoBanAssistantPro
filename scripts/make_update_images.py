# 把真机截图合成 v0.8.0 的**更新说明配图**。
#
#   python scripts/make_update_images.py
#
# 与 make_promo_images.py 的分工：那个出的是「App 长什么样」的宣传图（图形来源是
# 应用自己渲染的 tool/promo），这里出的是「这一版改了什么」的说明图 —— 所以图形
# 来源是**真机截图**（Redmi K90 Pro Max，1200×2608，adb 抓的），本文件只负责裁切、
# 套机身与标注。
#
# 原始素材在 `docs/images/raw/`，都是按下面这些框裁好、缩过半尺寸入库的：
#
#   miui-off.png   0.7.x：闹钟在响、锁屏上什么都没弹（「后台弹出界面」没开）
#   miui-on.png    v0.8.0：锁屏上弹出响铃界面（两项权限都开）  —— 同一台机器、同一张卡
#                  （这两张从 1200×2608 的原图裁 y 560..2480 再缩到 520 宽：上边去掉
#                   状态栏与运营商，下边留全「再睡一会」—— 裁到 2450 会把按钮拦腰截断，
#                   剩一条亮蓝色横带，第一版就是这么出的）
#   perm-old.png   0.7.4 的权限卡（6 项 / 3 组，中文名套错了小米的说法）
#   perm-new.png   v0.8.0 的权限卡（每行写「不开会怎样」，小米多两项引导）
#   cal-before.png 0.7.3：滑块与格子圆角差一档，四个角露出底下的卡片
#   cal-after.png  v0.8.0：两者同源，齐平
#
# 换素材就换 raw/ 里的图再跑一次；**别改 docs/images/v080-*.png**，那是生成物。
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
RAW = os.path.join(ROOT, 'docs', 'images', 'raw')
OUT = os.path.join(ROOT, 'docs', 'images')

ACCENT = (91, 108, 255)
ACCENT_D = (44, 34, 130)
BODY = (22, 23, 28)
INK = (255, 255, 255)
INK_SUB = (216, 221, 255)
OK = (94, 214, 145)
BAD = (255, 122, 122)


def _font(name, size):
    try:
        return ImageFont.truetype(f'C:/Windows/Fonts/{name}', size)
    except OSError:
        return ImageFont.load_default()


def _rounded_mask(w, h, r):
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)
    return m


def _gradient(W, H, c1=ACCENT, c2=ACCENT_D):
    ys, xs = np.mgrid[0:H, 0:W]
    t = np.clip(xs / max(1, W - 1) * 0.6 + ys / max(1, H - 1) * 0.4, 0, 1)
    arr = np.zeros((H, W, 3), np.float64)
    for i in range(3):
        arr[:, :, i] = c1[i] + (c2[i] - c1[i]) * t
    return Image.fromarray(arr.astype(np.uint8), 'RGB').convert('RGBA')


def _device(path, width):
    """截图 → 深色机身 + 圆角，返回 RGBA（与宣传图的 `framed` 同一套比例）。"""
    shot = Image.open(os.path.join(RAW, path)).convert('RGB')
    shot = shot.resize((width, round(shot.height * width / shot.width)),
                       Image.LANCZOS)
    bezel = max(8, round(width * 0.035))
    radius = round(width * 0.115)
    w, h = shot.size
    body = Image.new('RGBA', (w + bezel * 2, h + bezel * 2), BODY + (255,))
    body.putalpha(_rounded_mask(*body.size, radius + bezel))
    screen = shot.convert('RGBA')
    screen.putalpha(_rounded_mask(w, h, radius))
    body.alpha_composite(screen, (bezel, bezel))
    return body


def _panel(img, box, radius=28, alpha=26):
    """半透明白色圆角面板 —— 深色底上给内容分块，别用实心（会盖掉渐变）。"""
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=radius,
                                            fill=(255, 255, 255, alpha))
    img.alpha_composite(layer)


def _title(img, text, sub=None, y=54):
    d = ImageDraw.Draw(img)
    d.text((img.width / 2, y), text, font=_font('msyhbd.ttc', 54),
           fill=INK, anchor='ma')
    if sub:
        d.text((img.width / 2, y + 74), sub, font=_font('msyh.ttc', 30),
               fill=INK_SUB, anchor='ma')


def cover():
    """更新说明首图：一句话讲清这一版最重要的三件事。"""
    W, H = 1400, 900
    img = _gradient(W, H)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 108), '倒班助手 Pro', font=_font('msyhbd.ttc', 60),
           fill=INK_SUB, anchor='ma')
    d.text((W / 2, 196), 'v0.8.0　正式稳定版', font=_font('msyhbd.ttc', 96),
           fill=INK, anchor='ma')
    d.text((W / 2, 330), '归纳 v0.7.1 ~ v0.7.5 五个测试版的全部更新',
           font=_font('msyh.ttc', 34), fill=INK_SUB, anchor='ma')

    items = [
        ('小米机型锁屏真的能弹出响铃界面了',
         '查清了真因：少开一项 MIUI 私有的系统权限，不是「OS 限制」'),
        ('重启手机后闹钟与待办提醒都不再丢',
         '开机自动排回去，不必再手动打开一次 App'),
        ('权限页按「不开会怎样」重做',
         '分组与说明都改了，小米机型多两项引导'),
    ]
    y = 432
    for i, (head, tail) in enumerate(items):
        _panel(img, (180, y, W - 180, y + 116))
        d.ellipse((216, y + 40, 252, y + 76), fill=ACCENT)
        d.text((234, y + 58), str(i + 1), font=_font('msyhbd.ttc', 26),
               fill=INK, anchor='mm')
        d.text((286, y + 22), head, font=_font('msyhbd.ttc', 36), fill=INK)
        d.text((286, y + 70), tail, font=_font('msyh.ttc', 27), fill=INK_SUB)
        y += 140
    return img.convert('RGB')


def miui_ring():
    """锁屏响铃的前后对比 —— 这一版最大的一件事。"""
    W, H = 1400, 1000
    img = _gradient(W, H)
    _title(img, '小米机型：锁屏 / 后台弹出响铃界面',
           '以前只响不弹，现在会点亮屏幕并顶掉锁屏')

    # 记号用 × / √ 而不是 ✕ / ✓：微软雅黑没有后者这两个码位，会渲染成豆腐块
    # （第一版就是这么出的两个空心方框）。
    pair = [('miui-off.png', '不开「后台弹出界面」', '闹钟响了、屏幕也亮了，', '但只有锁屏 —— 界面不弹',
             BAD, '×'),
            ('miui-on.png', '这两项权限都开上', '到点自动点亮屏幕、顶掉锁屏，', '直接弹出响铃界面',
             OK, '√')]
    dev_w = 372
    gap = 120
    total = dev_w * 2 + gap
    x0 = (W - total) // 2
    for i, (path, head, l1, l2, color, mark) in enumerate(pair):
        x = x0 + i * (dev_w + gap)
        d = ImageDraw.Draw(img)
        pos = x + dev_w // 2
        # 勾/叉与标题当成**一组**居中：各自定位会在窄标签上叠起来（第一版就叠了）
        f_head = _font('msyhbd.ttc', 32)
        w_mark = d.textlength(mark, font=f_head)
        w_head = d.textlength(head, font=f_head)
        gap_mark = 14
        start = pos - (w_mark + gap_mark + w_head) / 2
        d.text((start, 236), mark, font=f_head, fill=color, anchor='lm')
        d.text((start + w_mark + gap_mark, 236), head, font=f_head, fill=color,
               anchor='lm')
        dev = _device(path, dev_w)
        img.alpha_composite(dev, (x, 268))
        d.text((pos, 268 + dev.height + 22), l1, font=_font('msyh.ttc', 27),
               fill=INK_SUB, anchor='ma')
        d.text((pos, 268 + dev.height + 58), l2, font=_font('msyh.ttc', 27),
               fill=INK_SUB, anchor='ma')
    d = ImageDraw.Draw(img)
    d.text(((x0 + dev_w + gap / 2), 268 + 420), '→', font=_font('msyhbd.ttc', 64),
           fill=INK, anchor='mm')
    return img.convert('RGB')


def reboot():
    """重启重排：三个状态的条数对照（数字全是真机实测的）。"""
    W, H = 1400, 740
    img = _gradient(W, H)
    _title(img, '重启手机后，闹钟与待办提醒都不再丢',
           '排定时落盘一份清单，开机由系统广播触发自动排回去')

    steps = [('重启前', '30', '条闹钟', '（另有 1 条待办提醒）', INK),
             ('重启后 · 未解锁', '0', '条', '系统清空了排定记录', INK_SUB),
             ('解锁的那一瞬间', '30', '条全部排回', '时间与重启前完全一致', OK)]
    cw, ch = 380, 300
    gap = 40
    x0 = (W - (cw * 3 + gap * 2)) // 2
    for i, (head, num, unit, note, color) in enumerate(steps):
        x = x0 + i * (cw + gap)
        _panel(img, (x, 250, x + cw, 250 + ch))
        d = ImageDraw.Draw(img)
        d.text((x + cw / 2, 288), head, font=_font('msyh.ttc', 30),
               fill=INK_SUB, anchor='ma')
        # 数字与单位当成一组居中：各自定位时「30」会压到「条全部排回」上（第一版就是）
        f_num, f_unit = _font('msyhbd.ttc', 96), _font('msyh.ttc', 28)
        w_num = d.textlength(num, font=f_num)
        w_unit = d.textlength(unit, font=f_unit)
        start = x + cw / 2 - (w_num + 10 + w_unit) / 2
        d.text((start, 400), num, font=f_num, fill=color, anchor='lm')
        d.text((start + w_num + 10, 424), unit, font=f_unit, fill=INK, anchor='lm')
        d.text((x + cw / 2, 496), note, font=_font('msyh.ttc', 24),
               fill=INK_SUB, anchor='ma')
        if i < 2:
            d.text((x + cw + gap / 2, 400), '→', font=_font('msyhbd.ttc', 48),
                   fill=INK_SUB, anchor='mm')
    d = ImageDraw.Draw(img)
    d.text((W / 2, 606), '不想手动开 App？现在不用了。关机期间已经错过的不会补响、也不补发。',
           font=_font('msyh.ttc', 26), fill=INK_SUB, anchor='ma')
    d.text((W / 2, 650), '真机实测：Redmi K90 Pro Max（小米 HyperOS）',
           font=_font('msyh.ttc', 24), fill=(170, 178, 220), anchor='ma')
    return img.convert('RGB')


def permissions():
    """权限卡重做的前后对比。"""
    # H=1280 是算出来的：250（图顶）+ 815（最高的那台机器含机身）+ 三条说明。
    # 第一版给 1060，三条说明直接压在机器下半截上。
    W, H = 1400, 1280
    img = _gradient(W, H)
    _title(img, '权限页重做：每行写清「不开会怎样」',
           '分组按用途重排，小米机型多两项引导')

    dev_w = 430
    devs = [_device('perm-old.png', dev_w), _device('perm-new.png', dev_w)]
    gap = 150
    total = sum(d.width for d in devs) + gap
    x0 = (W - total) // 2
    y = 250
    labels = ['v0.7.x', 'v0.8.0']
    for i, dev in enumerate(devs):
        x = x0 + sum(d.width for d in devs[:i]) + i * gap
        img.alpha_composite(dev, (x, y))
        d = ImageDraw.Draw(img)
        d.text((x + dev.width / 2, y - 26), labels[i],
               font=_font('msyhbd.ttc', 32), fill=INK if i else INK_SUB,
               anchor='mm')
    d = ImageDraw.Draw(img)
    d.text((x0 + devs[0].width + gap / 2, y + 300), '→',
           font=_font('msyhbd.ttc', 56), fill=INK, anchor='mm')
    d.text((W / 2, H - 175),
           '· 「显示悬浮窗」从「锁屏」组挪出来 —— 它管的是后台启动豁免，与锁屏无关',
           font=_font('msyh.ttc', 26), fill=INK_SUB, anchor='ma')
    d.text((W / 2, H - 125),
           '· 小米机型补上「锁屏显示」：与「后台弹出界面」缺一不可，只开一半就会以为好了',
           font=_font('msyh.ttc', 26), fill=INK_SUB, anchor='ma')
    d.text((W / 2, H - 75),
           '· 原来那行「后台弹出界面」其实是 Android 的「显示悬浮窗」，已正名',
           font=_font('msyh.ttc', 26), fill=INK_SUB, anchor='ma')
    return img.convert('RGB')


def calendar():
    """日历滑块与格子对齐的前后对比（0.7.3 → 0.8.0）。"""
    # H=900 是算出来的：280（图顶）+ 480（图高）+ 角标注 + 底部注释，1000 以下会打架
    W, H = 1400, 900
    img = _gradient(W, H)
    _title(img, '日历：选中那天的滑块与格子对齐了',
           '此前两者圆角差一档（22 与 16），四个角各露出一条底下的卡片')

    box = 1.55
    imgs = []
    for f in ('cal-before.png', 'cal-after.png'):
        im = Image.open(os.path.join(RAW, f)).convert('RGB')
        imgs.append(im.resize((round(im.width * box), round(im.height * box)),
                              Image.LANCZOS))
    gap = 190
    total = sum(i.width for i in imgs) + gap
    x0 = (W - total) // 2
    y = 280
    for i, im in enumerate(imgs):
        x = x0 + sum(j.width for j in imgs[:i]) + i * gap
        layer = Image.new('RGBA', im.size, (0, 0, 0, 0))
        layer.paste(im.convert('RGBA'), (0, 0))
        layer.putalpha(_rounded_mask(*im.size, 24))
        img.alpha_composite(layer, (x, y))
        d = ImageDraw.Draw(img)
        d.text((x + im.width / 2, y - 30), ['修复前', 'v0.8.0'][i],
               font=_font('msyhbd.ttc', 32), fill=INK_SUB if i == 0 else OK,
               anchor='mm')
        # 把「格子露出来的那四个角」圈出来 —— 不然这张图上的差异得凑近了看才认得出
        color = BAD if i == 0 else OK
        for cx, cy in ((26, 24), (26, im.height - 92),
                       (im.width - 116, 24), (im.width - 116, im.height - 92)):
            d.ellipse((x + cx, y + cy, x + cx + 90, y + cy + 68),
                      outline=color, width=5)
        d.text((x + im.width / 2, y + im.height + 18),
               '四个角露出底下的卡片' if i == 0 else '齐平，不再露卡片',
               font=_font('msyh.ttc', 27), fill=color, anchor='ma')
    d = ImageDraw.Draw(img)
    d.text((x0 + imgs[0].width + gap / 2, y + 200), '→',
           font=_font('msyhbd.ttc', 56), fill=INK, anchor='mm')
    d.text((W / 2, H - 75),
           '两处圆角现在取自同一个来源，并有一条测试钉着它们相等 —— 不会再各走各的。',
           font=_font('msyh.ttc', 26), fill=INK_SUB, anchor='ma')
    return img.convert('RGB')


JOBS = [
    ('v080-cover.png', cover),
    ('v080-miui-ring.png', miui_ring),
    ('v080-reboot.png', reboot),
    ('v080-permissions.png', permissions),
    ('v080-calendar.png', calendar),
]


def main():
    missing = [f for f in os.listdir(RAW) if f.endswith('.png')]
    need = ['miui-off.png', 'miui-on.png', 'perm-old.png', 'perm-new.png',
            'cal-before.png', 'cal-after.png']
    lack = [n for n in need if n not in missing]
    if lack:
        raise SystemExit('docs/images/raw/ 缺素材：%s' % '、'.join(lack))

    for name, fn in JOBS:
        img = fn()
        p = os.path.join(OUT, name)
        img.save(p, optimize=True)
        print(f'docs/images/{name}  {img.size[0]}x{img.size[1]}'
              f'  {os.path.getsize(p) // 1024} KB')


if __name__ == '__main__':
    main()
