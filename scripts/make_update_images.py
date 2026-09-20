# 把截图合成**更新说明配图**（v0.8.0 与 v0.9.0 两组）。
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
# 换素材就换 raw/ 里的图再跑一次；**别改生成物**（docs/images/v080-*.png、v090-*.png）。
#
# v0.9.0 那一组（见文件末尾）：四张用**应用自己渲染**的界面（app/build/visual/，与
# 回归工装同源）—— 它们要么在真机上要点很多步才到得了（撞班提示、零点班的
# 「前一天」），要么本身就是给用户看的浅色界面；只有桌面小组件那三张卡是例外，
# 它走原生 RemoteViews，工装画不出来，只能用**真机桌面截图**（raw/v090-widgets.png）。
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


def _device(path, width, base=None):
    """截图 → 深色机身 + 圆角，返回 RGBA（与宣传图的 `framed` 同一套比例）。

    [base] 换素材根目录：v0.9.0 那组有一部分用应用自己渲染的界面（见文件头）。
    """
    shot = Image.open(os.path.join(base or RAW, path)).convert('RGB')
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


def calendar_chips():
    """日历格子的三处改动：班次胶囊、选中实心、信息卡待办数。

    整屏只裁「网格 + 信息卡日期行」—— 上下各去掉状态栏与底部导航，那两处与
    这张图要说的事无关，留着只是把主体压小。
    """
    W, H = 1500, 1080
    img = _gradient(W, H)
    _title(img, '日历格子重做 · 今天有几项待办一眼看到',
           '班次变成带底色的胶囊，选中那天的胶囊变实心')

    shot = Image.open(os.path.join(RAW, 'cal-full.png')).convert('RGBA')
    shot.putalpha(_rounded_mask(*shot.size, 24))
    sx, sy = 110, 236
    img.alpha_composite(shot, (sx, sy))

    # 圈号直接标在截图上（坐标是量出来的），右侧配文字说明 —— 用引线连来连去
    # 反而更难对齐，而且截图一换就得重算角度。
    #
    # 位置都**偏在指的东西旁边**、不压在上面：第一版把圈号摆在正中心，结果 ② 和 ③
    # 把「实心胶囊」与「1 项待办」徽章整个盖住了 —— 指的东西被自己的圈挡住。
    marks = [
        ((244, 86), '班次胶囊', '格子里写明哪天是什么班 —— 一眼扫出这个月怎么倒'),
        ((18, 322), '选中那天变实心', '滑块落在哪一格，一眼就能锁定'),
        ((466, 733), '今日信息卡待办数', '不用翻到待办页，就知道今天有 N 件事'),
    ]
    d = ImageDraw.Draw(img)
    for i, ((mx, my), head, tail) in enumerate(marks):
        cx, cy = sx + mx, sy + my
        d.ellipse((cx - 21, cy - 21, cx + 21, cy + 21), fill=ACCENT,
                  outline=(255, 255, 255), width=3)
        d.text((cx, cy + 1), str(i + 1), font=_font('msyhbd.ttc', 26),
               fill=INK, anchor='mm')
        ly = 430 + i * 200
        d.ellipse((760, ly - 24, 808, ly + 24), fill=ACCENT)
        d.text((784, ly + 1), str(i + 1), font=_font('msyhbd.ttc', 28),
               fill=INK, anchor='mm')
        d.text((836, ly - 14), head, font=_font('msyhbd.ttc', 36), fill=INK)
        d.text((836, ly + 42), tail, font=_font('msyh.ttc', 27), fill=INK_SUB)
    return img.convert('RGB')


JOBS = [
    ('v080-cover.png', cover),
    ('v080-miui-ring.png', miui_ring),
    ('v080-reboot.png', reboot),
    ('v080-permissions.png', permissions),
    ('v080-calendar.png', calendar),
    ('v080-calendar-chips.png', calendar_chips),
]


def main():
    missing = [f for f in os.listdir(RAW) if f.endswith('.png')]
    need = ['miui-off.png', 'miui-on.png', 'perm-old.png', 'perm-new.png',
            'cal-before.png', 'cal-after.png', 'cal-full.png']
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


# ---------------------------------------------------------------------------
# v0.9.0 那一组
# ---------------------------------------------------------------------------

VIS = os.path.join(ROOT, 'app', 'build', 'visual')


def _single(title, sub, src, notes, dev_w=430, base=None, W=1400):
    """标题 + 一张界面 + 下面几行说明。"""
    dev = _device(src, dev_w, base)
    H = 250 + dev.height + 40 + 46 * len(notes) + 40
    img = _gradient(W, H)
    _title(img, title, sub)
    img.alpha_composite(dev, ((W - dev.width) // 2, 250))
    d = ImageDraw.Draw(img)
    y = 250 + dev.height + 40
    for line in notes:
        d.text((W / 2, y), line, font=_font('msyh.ttc', 26), fill=INK_SUB,
               anchor='ma')
        y += 46
    return img.convert('RGB')


def _pair(title, sub, left, right, lcap, rcap, notes=(), dev_w=372, base=None,
          W=1400):
    """左右两台机器 + 各自**短**标签 + 中间箭头（「在哪儿改 → 看到什么」）。

    [lcap] / [rcap] 必须短（**≤ 12 个字**）：它们是按每台机器的宽度居中画的，
    句子一长左右两行就会在中间撞上（第一版就是这么出的两行糊在一起）。长解释
    放 [notes]，那是整幅居中排的。
    """
    assert len(lcap) <= 12 and len(rcap) <= 12, '副标题太长，会撞在一起'
    a, b = _device(left, dev_w, base), _device(right, dev_w, base)
    gap = 130
    x0 = (W - (a.width + b.width + gap)) // 2
    y = 250
    H = y + max(a.height, b.height) + 90 + 44 * len(notes) + 30
    img = _gradient(W, H)
    _title(img, title, sub)
    img.alpha_composite(a, (x0, y))
    img.alpha_composite(b, (x0 + a.width + gap, y))
    d = ImageDraw.Draw(img)
    # 箭头用 →，勾/叉用 × / √：微软雅黑没有 ✕/✓ 的码位，会渲染成豆腐块
    d.text((x0 + a.width + gap / 2, y + 320), '→', font=_font('msyhbd.ttc', 56),
           fill=INK, anchor='mm')
    for i, (dev, cap) in enumerate(((a, lcap), (b, rcap))):
        x = x0 + (0 if i == 0 else a.width + gap)
        d.text((x + dev.width / 2, y + dev.height + 22), cap,
               font=_font('msyhbd.ttc', 28), fill=INK, anchor='ma')
    yy = y + max(a.height, b.height) + 90
    for line in notes:
        d.text((W / 2, yy), line, font=_font('msyh.ttc', 26), fill=INK_SUB,
               anchor='ma')
        yy += 44
    return img.convert('RGB')


def cover_090():
    """更新说明首图：这一版最重要的四件事。"""
    W, H = 1400, 1000
    img = _gradient(W, H)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 96), '倒班助手 Pro', font=_font('msyhbd.ttc', 60),
           fill=INK_SUB, anchor='ma')
    d.text((W / 2, 178), 'v0.9.0　正式稳定版', font=_font('msyhbd.ttc', 96),
           fill=INK, anchor='ma')
    d.text((W / 2, 312), '对比上一个正式版 v0.8.0',
           font=_font('msyh.ttc', 34), fill=INK_SUB, anchor='ma')

    # 评论区回复用：一行一件事，不写副标题
    items = [
        '桌面小组件：三张固定尺寸的卡',
        '日历上按天改班（请假 / 换班）',
        '我的模板：自己的班表存下来',
        '零点班闹钟：改排上班前一天',
        '班组撞班：一键按周期均分',
    ]
    y = 414
    for i, head in enumerate(items):
        _panel(img, (180, y, W - 180, y + 88))
        d.ellipse((214, y + 26, 250, y + 62), fill=ACCENT)
        d.text((232, y + 44), str(i + 1), font=_font('msyhbd.ttc', 26),
               fill=INK, anchor='mm')
        d.text((284, y + 44), head, font=_font('msyhbd.ttc', 38), fill=INK,
               anchor='lm')
        y += 106
    return img.convert('RGB')


def widgets_090():
    """桌面小组件：两屏真机桌面截图 + 三处标注（三张卡在相邻两屏）。

    两屏是**用户手机上的真实排布**：本周条与今日卡同屏、整月在隔壁那一屏。
    素材来自 `raw/v090-widgets-a.png` / `-b.png`（真机截图裁到卡片区域，
    半尺寸入库）。
    """
    W = 1500
    dev_w = 330
    a = _device('v090-widgets-a.png', dev_w)
    b = _device('v090-widgets-b.png', dev_w)
    y = 236
    # 底部那两行说明要落在图例下方，别和图例的最后一行撞上（第一版就是撞了）
    H = y + max(a.height, b.height) + 280
    img = _gradient(W, H)
    _title(img, '桌面小组件：三张固定尺寸的卡',
           '放置后不能拉伸；在 App 里改了排班，桌面立刻跟着变')
    xa, xb = 150, 540
    img.alpha_composite(a, (xa, y))
    img.alpha_composite(b, (xb, y))
    d = ImageDraw.Draw(img)

    # 圈号贴在卡片旁边（不压住内容），右侧一列说明
    marks = [
        (xa + a.width * 0.5, y + a.height * 0.20, '本周条 4×1', '今天这一周'),
        (xa + a.width * 0.5, y + a.height * 0.62, '今日卡 4×3', '今日详情'),
        (xb + b.width * 0.5, y + b.height * 0.46, '整月 4×5', '整月网格'),
    ]
    for i, (cx, cy, head, tail) in enumerate(marks):
        d.ellipse((cx - 21, cy - 21, cx + 21, cy + 21), fill=ACCENT,
                  outline=(255, 255, 255), width=3)
        d.text((cx, cy + 1), str(i + 1), font=_font('msyhbd.ttc', 26),
               fill=INK, anchor='mm')
        ly = 330 + i * 190
        d.ellipse((960, ly - 24, 1008, ly + 24), fill=ACCENT)
        d.text((984, ly + 1), str(i + 1), font=_font('msyhbd.ttc', 28),
               fill=INK, anchor='mm')
        d.text((1036, ly - 14), head, font=_font('msyhbd.ttc', 34), fill=INK)
        d.text((1036, ly + 40), tail, font=_font('msyh.ttc', 25), fill=INK_SUB)
    d.text((W / 2, H - 76), '点某一天直接跳到那天的日历',
           font=_font('msyh.ttc', 26), fill=INK_SUB, anchor='ma')
    return img.convert('RGB')


def override_090():
    return _pair(
        '日历上按天改班',
        '长按格子拖选一段，或点信息卡上那行班次',
        '10_calendar_adjusted_light.png', '11_override_picker_light.png',
        '① 改过的那天', '② 选择层',
        ['只作用于我们班组；改了之后联动闹钟自动跟着变。'],
        base=VIS)


def templates_090():
    return _pair(
        '我的模板：自己的班表存下来',
        '下次新建排班直接从最上面那组里选',
        '13_editor_midnight_light.png', '16_template_picker_mine_light.png',
        '① 编辑器右上角', '② 新建排班时',
        [],
        base=VIS)


def midnight_090():
    return _pair(
        '零点班闹钟：改排上班前一天',
        '00:00 上班、响铃 23:00 —— 从前排在班后，现在排在上班前 1 小时',
        '13_editor_midnight_light_scrolled.png', '14_alarm_midnight_light.png',
        '① 班次设置', '② 闹钟列表',
        [],
        base=VIS)


def clash_090():
    return _single(
        '班组撞班：点名 + 一键均分',
        '把 5 天一轮改成 10 天之后，同一天有两个班组上同一个班',
        '15_editor_crew_clash_light_scrolled.png',
        ['编辑器的「周期设置」里点出相撞的班组，一键按周期长度均分'],
        dev_w=470, base=VIS)


JOBS_090 = [
    ('v090-cover.png', cover_090),
    ('v090-widgets.png', widgets_090),
    ('v090-override.png', override_090),
    ('v090-templates.png', templates_090),
    ('v090-midnight.png', midnight_090),
    ('v090-clash.png', clash_090),
]


def main_v090():
    """只出 v0.9.0 那一组（v0.8.0 那组的素材若不在，也不该拦着这一组）。"""
    for name, fn in JOBS_090:
        p = os.path.join(OUT, name)
        img = fn()
        img.save(p, optimize=True)
        print(f'docs/images/{name}  {img.size[0]}x{img.size[1]}'
              f'  {os.path.getsize(p) // 1024} KB')
