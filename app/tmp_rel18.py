# v0.9.18 收尾：版本号、更新日志、使用帮助、AGENTS、PRODUCT_SPEC。
import io
import re

LF = chr(10)
BS = chr(92)
ESC = BS + 'n'
APP = ''


def patch(path, pairs):
    s = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert old in s, '找不到锚点: %r' % old[:70]
        s = s.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8', newline=LF).write(s)


def changelog_entry(const_name, ver, lines):
    out = "const String %s = 'v%s%s'%s" % (const_name, ver, ESC, LF)
    for t in lines:
        out += "    '%s%s'%s" % (t, ESC, LF)
    return out + LF


# ── 1. 版本号 ──
patch(APP + 'pubspec.yaml', [('version: 0.9.17+121', 'version: 0.9.18+122')])
patch(APP + 'lib/core/app_info.dart',
      [("const String appVersion = '0.9.17';", "const String appVersion = '0.9.18';")])

# ── 2. 更新日志 ──
P = APP + 'lib/features/profile/app_dialogs.dart'
s = io.open(P, encoding='utf-8').read()

zh = changelog_entry('_changelogZh', '0.9.18', [
    '· 桌面小组件那张月历能翻的范围，从「前后各一个月」放宽到「前后各三个月」—— 标题行两边的箭头点一下翻一月。顺带一个好处：你更久不开 App，卡片上的数据也还够用',
    '· 装完新版请先打开一次 App：小组件上的班次是 App 上次运行时算好的，不打开的话卡片还是旧样子（重启桌面也能让它重画，但没必要）。这条从这一版起写进更新说明，免得你以为升级把桌面弄乱了',
    '· 修好待办与闹钟列表的一个毛病：条目多的时候，最后一行会被右下角那颗悬浮按钮（以及闹钟页底部那条按钮条）压住，删除键点不到。现在滑到底能把它绕到按钮上面',
    '· 「排班时段 → 添加时段」那个弹层的字体与同一页对齐了：里面三个标签原来又小又轻一档（13/w400），现在与打开它的那一行一样（14/w500）',
    '· 顺手修掉小窗（200×400）下这个弹层的两处布局毛病：三个按钮挤不下时横向溢出、日期那两行的取值放不下',
    '',
]) + "    'v0.9.17" + ESC + "'"
old_zh = "const String _changelogZh = 'v0.9.17" + ESC + "'"
assert old_zh in s
s = s.replace(old_zh, zh, 1)

en = changelog_entry('_changelogEn', '0.9.18', [
    '· The month widget now steps three months back or forward instead of one: tap the arrows either side of its title. As a bonus, the card keeps working for longer while the app stays closed',
    '· Open the app once after an update: the shifts on the card are worked out the last time the app ran, so until you do, the card still shows the old picture. (Restarting the launcher redraws it too, but that is not needed.) That note now lives in the update notes, so an update never looks like it broke your home screen',
    '· Fixed the end of the todo and alarm lists: once there are enough entries, the last row sat under the floating button (or the button bar on the alarm page) and its delete button could not be tapped. Scrolling to the end now lifts it clear',
    '· The "Add a period" dialog now matches the row that opens it: its three labels were a size and a weight lighter (13/w400) and are now 14/w500, like the rest of the page',
    '· Also fixed two layout faults in that dialog in a small window (200×400): its buttons overflowed sideways, and the date rows could not fit their value',
    '',
]) + "    'v0.9.17" + ESC + "'"
old_en = "const String _changelogEn = 'v0.9.17" + ESC + "'"
assert old_en in s
s = s.replace(old_en, en, 1)

# 滚掉最旧一条（v0.9.8：中英各一处）
pattern = re.compile(r"    'v0\.9\.8" + re.escape(ESC) + "'.*?;", re.S)
s, n = pattern.subn(';', s)
assert n == 2, '应当删掉两条，实际 %d' % n
io.open(P, 'w', encoding='utf-8', newline=LF).write(s)

# ── 3. 使用帮助：小组件那条补一句，并把「能翻」写进去 ──
patch(APP + 'lib/core/l10n.dart', [
    ("        t('三张固定尺寸的卡：本周条（4×1）、今日卡（4×3，底栏那张信息卡的完整版）、整月（4×5，42 格月历）',\n"
     "            'Three fixed-size cards: a week strip (4×1), a today card (4×3 — the full version of the info card at the bottom of the app) and a month view (4×5, a 42-cell calendar)'),",
     "        t('三张固定尺寸的卡：本周条（4×1）、今日卡（4×3，底栏那张信息卡的完整版）、整月（4×5，42 格月历，标题行两边的箭头能翻前后各三个月）',\n"
     "            'Three fixed-size cards: a week strip (4×1), a today card (4×3 — the full version of the info card at the bottom of the app) and a month view (4×5, a 42-cell calendar whose title arrows step three months either way)'),"),
    ("        t('放上去之后不能拉伸', 'They cannot be resized once placed'),",
     "        t('放上去之后不能拉伸', 'They cannot be resized once placed'),\n"
     "        t('装完新版先打开一次 App —— 卡片上的班次是上次打开 App 时算好的，不打开就还是旧样子',\n"
     "            'Open the app once after an update — the shifts on the card were worked out the last time the app ran, so until then they are the old ones'),"),
])

# ── 4. AGENTS.md ──
patch('AGENTS.md', [
    # 版本史
    ('→ 0.9.17(+121) 测试版（**月历小组件连月 + 翻月**：42 格改成连续 42 天、相邻月日数变灰；'
     '标题行 ‹ › 翻月、点月份回今天；每个实例落盘一份月份锚点（存绝对值）；快照窗口扩到上月+本月+下月，**协议版本不动**）。更早见',
     '→ 0.9.17(+121) 测试版（**月历小组件连月 + 翻月**：42 格改成连续 42 天、相邻月日数变灰；'
     '标题行 ‹ › 翻月、点月份回今天；每个实例落盘一份月份锚点（存绝对值）；快照窗口扩到上月+本月+下月，**协议版本不动**）。'
     '→ 0.9.18(+122) 测试版（**能翻 ±3 个月**（窗口 105 → 231 天，上限 240）；回前台重推一次快照（推失败不再是死局）；'
     '待办 / 闹钟列表补底部留白（悬浮按钮不再压住最后一行的删除键，两个具名常量 + 几何用例）；'
     '时段弹层三个标签对齐到 rowPrimary；屏单补 `33_span_editor`，当场抓出小窗下两个布局溢出（`ListTile` trailing 吃掉整行 + 按钮行溢出 → `GlassDialog` 的 actions 改 `Wrap`））。更早见'),
    # 小组件那段：窗口与「装完要开一次 App」
    ('快照窗口是**「上月 + 本月 + 下月」的绝对窗口**（v0.9.17 改的；整周对齐、最坏 105 天，'
     '上限 `kWidgetSnapshotMaxDays = 112`；**协议版本仍是 v2**，只改范围不动字段）',
     '快照窗口是**「−3 ~ +3 个月」的绝对窗口**（v0.9.18 从三个月放宽；整周对齐、最坏 **231 天**，'
     '上限 `kWidgetSnapshotMaxDays = 240`；**协议版本仍是 v2**，只改范围不动字段 —— 放宽窗口就是改算式，'
     '能翻多远、箭头灰不灰仍由 `monthCovered` 现算）。**装完新版必须打开一次 App**：数据只能由 Dart 算，'
     '不打开的话卡片还挂着升级前那一次的渲染字节（`MY_PACKAGE_REPLACED` 到「App 第一次运行」之间没有触发点）——'
     '这条写进了更新日志与使用帮助'),
    # 测试条数
    ('`flutter test` 全绿（当前 **527** 条', '`flutter test` 全绿（当前 **531** 条'),
    ('`flutter test tool/visual/` 246 条', '`flutter test tool/visual/` 254 条'),
])
print('ok')
