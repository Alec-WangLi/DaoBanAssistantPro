# 使用帮助改成两层 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把《使用帮助》从「一个弹窗、九条一条到底」改成「整页：简介 + 九条功能简介 + 一个入口」，入口进第二层「我想办一件事 / 它不对劲」清单页。

**Architecture:** 两级都是**整页**（`Scaffold` + `AppBar` + `CenteredContent` + `ListView`，照抄 `schedule_management_screen.dart` 的骨架）。第二层的内容是**纯数据**（一个新的 const 内容文件，用 `L10nText` 存双语，照 `domain/shift_templates.dart` 的路子），与渲染分离，于是内容可以被用例逐条查、也能被渲染层当普通列表吃。

**Tech Stack:** Flutter 3.47 / Riverpod / 设计令牌 `AppTokens` / 静态 i18n `L10n`（`L10nText` 用于数据层文案）/ `flutter_test` + 视觉工装 `tool/visual/`。

**Spec:** `docs/superpowers/specs/2026-10-13-help-center-design.md`

## Global Constraints

- **双语只有一处来源**。界面文案进 `lib/core/l10n.dart`；第二层那份成块的内容进 `lib/features/profile/help_content.dart`（用 `L10nText(zh, en)`）。**任何地方不许出现「英文缺省回退中文」**——`L10nText` 本来就不回退，别在渲染层再包一层。
- **事实必须与实现一致**。条目里出现数字（每班闹钟条数 / 闹钟页天数 / 主色调数 / 贪睡档位 / 归档上限 / 小组件月份范围），一律对着实现常量核，并由用例钉住（见 Task 2 步骤 1 与 Task 4 步骤 1）。
- **设计语言照旧**：间距/字号/图标一律走 `AppTokens` 的角色令牌，不写字面量；卡片配方照抄「我的」页与排班管理页（`GlassTile(translucentFill: false, padding: EdgeInsets.zero)` + `GlassPressable` + `ListTile`，条目之间用全 app 那条 `Divider(height: 1)`）。
- **不许跑 `dart format`**（工具链是新版 tall style，一跑就重排整个文件、制造几百行无关 diff）。只跑 `flutter analyze`。
- **验收线**：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿且**只增不减**（当前 1011 条）。
- **构建环境**（本机 bash）：`export PATH="$PWD/toolchain/flutter/bin:$PATH"`、`export PUB_CACHE="$PWD/toolchain/pub-cache"`（在仓库根跑；`flutter test` 一律在 `app/` 下跑）。
- **不碰原生**：这一版全是 Dart，Kotlin 一个字都不改。

## Review Focus

下面五类是这个 spec 暗示了、但没有哪个任务的用例会去跑的东西。每一条都归到某个任务里，用那条任务自己的步骤风格补一条用例：

1. **小窗（200×400）与大字号下的长条目**：第二层的答案句子比现在帮助里任何一句都长，窄屏 + 特大字号下会不会被截断或溢出。（归 Task 3 步骤 5）
2. **英文普遍比中文长**：卡片里折行之后的问题/答案间距、以及「问题 + 答案」两行是不是还分得开。（归 Task 3 步骤 5）
3. **从「我的 → 桌面」跳进去时，滚动落点**：列表还没布局完就 `ensureVisible` 会滚不动；用户到了之后自己滑走再返回，不该被再拽回去。（归 Task 5 步骤 3）
4. **深色档下正文与卡底的对比度**：这些条目整块是 `inkMuted` 的长段落，比现在只有几行圆点的帮助更容易踩到对比度线。（归 Task 6 步骤 2）
5. **切语言之后已经在栈上的页面**：`L10n.locale` 是全局静态，第二层页在栈上时切语言，返回重进必须是新语言。（归 Task 3 步骤 5）

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `app/lib/features/profile/help_entry.dart` | **新建**。共享件 `HelpEntry`：一条「图标圆钮 + 标题 + 圆点短句」。从 `app_dialogs.dart` 的私有 `_GuideEntry` 原样搬出来并公开。第一级页与「开始使用」弹窗共用。 |
| `app/lib/features/profile/help_content.dart` | **新建**。第二层的内容：分组 / 小节 / 条目，全部是 `L10nText` 常量。不含任何 widget。 |
| `app/lib/features/profile/help_faq_screen.dart` | **新建**。第二层整页，把 `help_content.dart` 渲染出来。 |
| `app/lib/features/profile/help_center_screen.dart` | **新建**。第一级整页：简介 + 九条 + 进第二层的入口。 |
| `app/lib/features/profile/app_dialogs.dart` | **改**。删掉 `_GuideEntry`（搬走了）、`showUsageGuideDialog`、`showWidgetGuideDialog`；`showGettingStartedDialog` 改用 `HelpEntry`。 |
| `app/lib/features/profile/profile_screen.dart` | **改**。两行入口改指向整页。 |
| `app/lib/core/l10n.dart` | **改**。新增第一级的简介/入口/页标题等文案；**补正九条**（事实错 + 四个缺席功能）。 |
| `app/tool/visual/visual_screens.dart` | **改**。屏单换掉两屏、新增两屏。 |

---

### Task 1: 把帮助条目抽成共享件 `HelpEntry`

**Files:**
- Create: `app/lib/features/profile/help_entry.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`（删 `_GuideEntry`，两处调用点改名）

**Interfaces:**
- Consumes: 无（这一条是纯搬运）
- Produces:
  ```dart
  class HelpEntry extends StatelessWidget {
    const HelpEntry({
      super.key,
      required this.icon,
      required this.title,   // 可空：为 null 时连标题那 8dp 间距一起不画
      required this.lines,
      this.bulleted = true,  // lines 多于一行时每行前加一个 4dp 圆点
    });
    final IconData icon;
    final String? title;
    final List<String> lines;
    final bool bulleted;
  }
  ```

- [ ] **Step 1: 先取一份「改之前」的基线图**

```bash
cd app
export PATH="/c/Users/Alec/Documents/DeepSeekHermesData/shiftassistant/toolchain/flutter/bin:$PATH"
flutter test tool/visual/render_screens_test.dart --plain-name "使用帮助 · 浅色"
mkdir -p /tmp/help-before && cp build/visual/18_usage_guide_light.png /tmp/help-before/
```

- [ ] **Step 2: 把 `_GuideEntry` 整体搬到新文件**

`app/lib/features/profile/app_dialogs.dart:396` 起那个类的**每一行照抄**，只改三处：类名 `_GuideEntry` → `HelpEntry`，构造函数加 `super.key`，去掉前导下划线；上面的文档注释一并搬过去。新文件顶部要 import `flutter/material.dart`、`../../core/design_tokens.dart`、`../../core/widgets/app_icon.dart`（`AppIcon` 的实际路径按仓库现有 import 抄——`app_dialogs.dart` 里就有）。

- [ ] **Step 3: 改 `app_dialogs.dart` 的两处调用点**

`showGettingStartedDialog` 里三处 `_GuideEntry(...)` 改成 `HelpEntry(...)`，并加 `import 'help_entry.dart';`。`_GuideEntry` 的类定义删除。

- [ ] **Step 4: 跑分析与全套测试**

```bash
flutter analyze     # 期望 0 error / 0 warning
flutter test        # 期望 1011 条全绿（这一条不新增用例）
```

- [ ] **Step 5: 出图比对，必须逐像素相同**

`scripts/diff_visual.py` 吃的是**两个目录**（逐张比同名文件），所以两边各放一个同名文件：

```bash
flutter test tool/visual/render_screens_test.dart --plain-name "使用帮助 · 浅色"
mkdir -p /tmp/help-after && cp build/visual/18_usage_guide_light.png /tmp/help-after/
python ../scripts/diff_visual.py /tmp/help-before /tmp/help-after --threshold 0
```
期望：**0 张不同**。差一个像素就说明搬运时改了东西，回去找。

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/profile/help_entry.dart app/lib/features/profile/app_dialogs.dart
git commit -m "refactor(help): 把帮助条目抽成共享件 HelpEntry（逐像素不变）"
```

---

### Task 2: 第二层的内容文件 + 内容护栏

**Files:**
- Create: `app/lib/features/profile/help_content.dart`
- Test: `app/test/help_content_test.dart`

**Interfaces:**
- Consumes: `L10nText`（`lib/core/l10n.dart`，`const L10nText(zh, en)`，`.value` 按当前语言取）；`maxAlarmsPerShift`（`lib/domain/shift_rotation.dart`）
- Produces:
  ```dart
  typedef HelpFaqItem = ({L10nText question, L10nText answer});
  typedef HelpFaqSection = ({L10nText? heading, List<HelpFaqItem> items});
  typedef HelpFaqGroup = ({L10nText title, List<HelpFaqSection> sections});

  /// 第二层的全部内容，顺序即渲染顺序。
  const List<HelpFaqGroup> helpFaqGroups = [ ... ];

  /// 组标题（第二层页头用不到，但内容用例与渲染层都要按 index 取，见 Task 3）。
  /// 渲染层直接用 helpFaqGroups[i].title.value。
  ```

- [ ] **Step 1: 写内容用例（先看着它红）**

`app/test/help_content_test.dart`：

```dart
// app/test/help_content_test.dart
//
// 第二层内容是**成块的文案**，最容易出的两种错都不会报错：英文漏翻（英文界面上
// 显示中文），以及**数字与实现漂了** —— 后者这个仓库真犯过：帮助里写着
// 「一个班次最多挂 6 条闹钟」，而 v0.11.1 早就放到 10 条了。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/profile/help_content.dart';

List<HelpFaqItem> _allItems() =>
    [for (final g in helpFaqGroups) for (final s in g.sections) ...s.items];

void main() {
  test('两组的条数下限（spec §4 那一份是下限，不许比它少）', () {
    expect(helpFaqGroups.length, 2, reason: '「我想办一件事」+「它不对劲」');
    expect(_allItems().length, greaterThanOrEqualTo(31),
        reason: 'spec §4 逐条数下来是 31 条；删条要回 spec 里改，别就地删');
  });

  test('每条的两种语言都写满了，且英文不是照抄中文', () {
    for (final it in _allItems()) {
      expect(it.question.zh.trim(), isNotEmpty);
      expect(it.question.en.trim(), isNotEmpty);
      expect(it.answer.zh.trim(), isNotEmpty);
      expect(it.answer.en.trim(), isNotEmpty,
          reason: '英文缺省会在英文界面上伪装成正常内容（L10nText 不回退，'
              '但空串同样看不出来）：${it.question.zh}');
      expect(it.question.en, isNot(it.question.zh),
          reason: '英文没翻：${it.question.zh}');
      expect(it.answer.en, isNot(it.answer.zh),
          reason: '英文没翻：${it.question.zh}');
    }
  });

  test('帮助文案里不许出现 markdown 标记', () {
    // 与 changelog_window_test 同一套路：更新日志真犯过两次（v0.7.1/v0.7.2、
    // v0.9.14），用户看到的是星号本身。帮助也是纯文本渲染。
    final bad = RegExp(r'\*\*|`|^#|\[[^\]]+\]\([^)]+\)', multiLine: true);
    for (final it in _allItems()) {
      for (final s in [it.question.zh, it.question.en, it.answer.zh, it.answer.en]) {
        expect(bad.hasMatch(s), isFalse, reason: '命中了 markdown 标记：$s');
      }
    }
  });

  test('闹钟条数的数字与 maxAlarmsPerShift 一致', () {
    final item = _allItems()
        .firstWhere((it) => it.question.zh.contains('响两次'));
    expect(item.answer.zh, contains('$maxAlarmsPerShift'),
        reason: '帮助里写的条数必须从常量来 —— 改了上限就要回来改这句');
    expect(item.answer.en, contains('$maxAlarmsPerShift'));
  });
}
```

- [ ] **Step 2: 跑它，确认红**

```bash
cd app && flutter test test/help_content_test.dart
```
期望：编译不过（`help_content.dart` 还不存在）。

- [ ] **Step 3: 写 `help_content.dart`**

文件头写清三条规矩（为什么这个文件不用 `L10n.xxx` getter 而用 `L10nText`：它是**成块内容**、量太大，`L10nText` 正是仓库为「数据层持有文案」准备的东西，见 `domain/shift_templates.dart`；以及「问句用用户的说法，不用我们的术语」「每条自己把话说完，不许互相指路」）。

内容照下面这份写（**中文逐字用这份**；英文由实现者翻，要求是完整的句子、不是逐字直译）：

组 1 `L10nText('我想办一件事', 'I want to…')`

*小节 `L10nText('排班', 'Shifts')`*
1. 我这个月跟下个月不一样 → 编辑排班页最上面那个分段器切到「按月」，然后按当月排；也可以去「我的 → 排班管理 → 排班时段」给不同的月份指定不同的班表。
2. 我们跟着法定节假日休、没有固定轮转 → 编辑排班页最下面打开「跟随法定节假日（无班次）」。这样日历上只画日期和农历，法定节假日照旧标红。
3. 我们上 12 休 24 这种不规则的 → 用「周期设置」，一天一天把班排出来。周期长度可以拉到 60 天，什么样的轮法都排得下。
4. 我们班组从哪天开始、怎么跟别的班组错开 → 「班组设置」里填每个班组从哪天起算。填的起始日跟周期长度对不上时会提示「撞班」，那里有一个按钮可以按周期长度自动均分。
5. 我想看别的班组那天上什么班 → 也是在「班组设置」里给每个班组起个名字，日历那一栏就会把它们列出来。
6. 我这套排班只用一段时间，之后换另一套 → 「我的 → 排班管理 → 排班时段」加两段，各指定用哪套班表。
7. 这套排班我以后还要用 → 编辑排班页右上角那个书签按钮，「存为模板」。下次新建排班时它排在最前面的「我的模板」里。

*小节 `L10nText('临时改班', 'One-off changes')`*
8. 这天我请假、或者跟同事换了班 → 在日历上点底栏那张信息卡里的班次那一行；要改连着好几天，就长按某一天往旁边拖，把一段日子圈出来。
9. 改错了想改回去 → 再点一次那几天，选择层最上面有「恢复轮转」。

*小节 `L10nText('闹钟', 'Alarms')`*
10. 一个班想响两次（起床一次、出门一次）→ 在编辑排班页那一班的卡片里，点「添加闹钟」。一个班最多配 10 条，每条可以起名字。
11. 夜班要提前叫我 → 也是在那张卡片里，把闹钟的钟点填成你要的时间就行。
12. 零点班配 23:00，到底响在哪天 → 列表里写着「前一天」或「次日」，那是按上班时间算出来的，不用自己判断。
13. 哪天我不想被吵 → 闹钟页列着未来 30 天，每一天都能单独关掉。
14. 早上想多躺十分钟 → 「我的 → 闹钟 → 贪睡时长」，1 到 30 分钟。
15. 想用自己手机里的歌、或者只想要震动 → 「我的 → 闹钟 → 闹钟铃声」，可以选内置、系统铃声，或者从手机里挑一首；不想出声就选「仅震动」。
16. 睡前想确认明天几点响 → 闹钟页最上面那份「未来 30 天」的列表，按天列着。

*小节 `L10nText('待办', 'Todo')`*
17. 明天交班要提醒我 → 待办页右下角新建一条，填上时间，再把「提醒」设成提前多久。到点会弹通知。
18. 每周三开会，不想每周手填一遍 → 新建待办时把「重复」选上，可以按天、按星期几、或按每月几号。
19. 到点只想要通知、不要全屏闹钟 → 那条待办里的「联动闹钟」关掉就行；开着的话它会像班次闹钟一样全屏响。
20. 做完的不想在列表里碍眼 → 勾掉之后它会自己收进列表最下面那个「已完成 N 条」里。

*小节 `L10nText('外观与设置', 'Look and settings')`*
21. 字太小 → 「我的 → 外观 → 字体大小」，四档，App 自己管，不跟系统走。
22. 想换深色 / 主题色 / 想用英文 → 也在「我的 → 外观」。
23. 手机发热、费电 → 「我的 → 外观」里把「液态玻璃」关掉。那个效果是最好看也最费电的一项。
24. 想从头来一遍 → 「我的 → 数据 → 清空重置」，会回到刚装好的样子。
25. 换了手机，怎么把排班搬过去 → 目前不支持。数据只存在这台手机上，没有云同步也没有导出，换手机要重新排一遍。

组 2 `L10nText('它不对劲', 'Something looks wrong')`（无小节，`heading: null`）

26. 闹钟到点只响、不弹响铃界面 → 去「我的 → 权限」逐项开齐。小米手机还要单独开「后台弹出界面」和「锁屏显示」这两项，不开的话系统会拦掉响铃界面。
27. 重启手机后闹钟没恢复 → 「我的 → 权限」里的「自启动」没开。开着它，重启后闹钟才排得回来。
28. 桌面小组件还是升级前的样子 → 打开一次 App 就好。卡片上的班次是上次打开 App 时算好的。
29. 小米桌面找不到小组件在哪加 → 长按桌面空白处 → 添加小部件 → 「支持小部件的应用」→「安卓小部件」。小米把它们藏在二级分类里。
30. 日历上整月没有班次 / 某几天突然没了 → 去「我的 → 排班管理 → 排班时段」，看那几天归哪套班表。也可能是那段日子被设成了「无」。
31. 横屏、平板、车机上日历变成了左右两栏 → 这是正常的：屏幕够宽时左边是日期网格、右边是当天详情；窗口很矮（高不到 480dp）时只显示当天那张卡，因为那个尺寸下网格看不清。

- [ ] **Step 4: 跑用例，确认绿**

```bash
flutter test test/help_content_test.dart
```
期望：4 条全绿。

- [ ] **Step 5: 反向验证那条数字护栏**

把第 10 条的中文里的 `10` 改成 `6`，重跑 —— 必须红在「闹钟条数的数字与 maxAlarmsPerShift 一致」。然后改回来。

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/profile/help_content.dart app/test/help_content_test.dart
git commit -m "feat(help): 第二层的内容文件与内容护栏（双语、条数下限、数字对常量）"
```

---

### Task 3: 第二层整页

**Files:**
- Create: `app/lib/features/profile/help_faq_screen.dart`
- Test: `app/test/help_faq_screen_test.dart`

**Interfaces:**
- Consumes: `helpFaqGroups`（Task 2）；`L10n.faqTitle`
- Produces: `class HelpFaqScreen extends StatelessWidget { const HelpFaqScreen({super.key}); }`

- [ ] **Step 1: 写页面用例（先看着它红）**

`app/test/help_faq_screen_test.dart`：

```dart
// app/test/help_faq_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/help_content.dart';
import 'package:shiftassistantpro/features/profile/help_faq_screen.dart';

Future<void> _pump(WidgetTester tester, {Size size = const Size(420, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: HelpFaqScreen()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('两组标题都在，第一条问题的原文在页面上', (tester) async {
    L10n.locale = 'zh';
    await _pump(tester);
    for (final g in helpFaqGroups) {
      expect(find.text(g.title.zh), findsOneWidget);
    }
    expect(find.text(helpFaqGroups.first.sections.first.items.first.question.zh),
        findsOneWidget);
  });

  testWidgets('切到英文之后整页是英文（不许漏一条中文）', (tester) async {
    L10n.locale = 'en';
    addTearDown(() => L10n.locale = 'zh');
    await _pump(tester);
    expect(find.text(helpFaqGroups.first.title.en), findsOneWidget);
    expect(find.text(helpFaqGroups.first.sections.first.items.first.question.en),
        findsOneWidget);
    // 中文那份的原文一个都不该出现
    expect(find.text(helpFaqGroups.first.title.zh), findsNothing);
    expect(find.text(helpFaqGroups.first.sections.first.items.first.question.zh),
        findsNothing);
  });
}
```

- [ ] **Step 2: 跑它，确认红**

```bash
cd app && flutter test test/help_faq_screen_test.dart
```
期望：编译不过（`help_faq_screen.dart` 还不存在）。

- [ ] **Step 3: 写 `help_faq_screen.dart`**

骨架照抄 `app/lib/features/calendar/schedule_management_screen.dart:34-70` 的 `Scaffold` + `AppBar`（标题用 `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(L10n.faqTitle))`）+ `CenteredContent` + `ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24))`。

- 组标题：页面级小节标题，照抄排班管理页的 `_sectionHeading` 写法（`Text(style: AppTokens.titleStrong)`，上下留 `AppTokens.spaceSm` / `AppTokens.spaceMd`）。**把那个私有函数复制成这个文件里的私有 `_groupHeading`**（两个文件各一份，别为它去动排班管理页）。
- 每个小节 = 一张 `GlassTile(translucentFill: false, padding: EdgeInsets.zero)`：
  - `heading != null` 时，卡片内第一行是小节标题，`AppTokens.microStrong.copyWith(color: AppTokens.inkMuted(context))`，外边距 `EdgeInsets.fromLTRB(16, 12, 16, 0)`；
  - 条目之间 `const Divider(height: 1)`；
  - 每条 = `Padding(EdgeInsets.fromLTRB(16, 12, 16, 12))` 包一个 `Column(crossAxisAlignment: start)`：问题用 `AppTokens.labelStrong`，隔 `AppTokens.spaceXs`，答案用 `AppTokens.rowSecondary.copyWith(height: 1.45, color: AppTokens.inkMuted(context))`。
  - 整张卡下面的间距 `AppTokens.spaceMd`。

- [ ] **Step 4: 跑用例，确认绿**

```bash
flutter test test/help_faq_screen_test.dart
```

- [ ] **Step 5: 补 Review Focus 的三条，跑一遍**

同一个测试文件里加三条：
- **小窗 + 大字号不截断**：`_pump(tester, size: const Size(200, 400))` 与在 `MaterialApp` 外包一层 `MediaQuery` 把 `textScaler` 设成 `TextScaler.linear(1.2)`（这是 App 自己的最大档，见 `AppFontSize`），各跑一遍 `expect(tester.takeException(), isNull)`，并断言**第一条问题的中文原文仍然完整可见**（`findsOneWidget`）——不是只断言「没溢出」。
- **英文折行后问题与答案还分得开**：英文档下取第一条，断言问题那行与答案那行是两个不同的 `Text`，且它们的 `tester.getRect` 的 `top` 不同（防止被挤成一行）。
- **切语言回来是新语言**：中文档挂上页 → `L10n.locale = 'en'` → 重新 `pumpWidget` → 断言英文原文在、中文原文不在。

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/profile/help_faq_screen.dart app/test/help_faq_screen_test.dart
git commit -m "feat(help): 第二层「遇到问题怎么解决」整页"
```

---

### Task 4: 第一级「使用帮助」整页 + 九条补正 + 入口

**Files:**
- Create: `app/lib/features/profile/help_center_screen.dart`
- Modify: `app/lib/features/profile/app_dialogs.dart`（删 `showUsageGuideDialog`）
- Modify: `app/lib/features/profile/profile_screen.dart:316-323`（那一行改成 push）
- Modify: `app/lib/core/l10n.dart`（新增文案 + 补正九条）
- Modify: `app/tool/visual/visual_screens.dart:299-306`（`18_usage_guide` 换成整页）
- Test: `app/test/help_center_test.dart`

**Interfaces:**
- Consumes: `HelpEntry`（Task 1）、`HelpFaqScreen`（Task 3）
- Produces: `class HelpCenterScreen extends StatelessWidget { const HelpCenterScreen({super.key, this.scrollToWidgets = false}); final bool scrollToWidgets; }`
  （`scrollToWidgets` 这一版由 Task 5 用；Task 4 先把它实现出来。）

- [ ] **Step 1: 写页面用例（先看着它红）**

`app/test/help_center_test.dart`：

```dart
// app/test/help_center_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/profile/help_center_screen.dart';
import 'package:shiftassistantpro/features/profile/help_faq_screen.dart';

Future<void> _pump(WidgetTester tester,
    {Size size = const Size(420, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('简介与九条功能简介都在', (tester) async {
    L10n.locale = 'zh';
    await _pump(tester);
    expect(find.text(L10n.helpIntro), findsOneWidget);
    for (final t in [L10n.guideCalTitle, L10n.guideSchedTitle, L10n.guideAlarmTitle,
      L10n.guideTodoTitle, L10n.guideWidgetTitle, L10n.guideAppearanceTitle,
      L10n.guideLayoutTitle, L10n.guidePermTitle, L10n.guideUpdateTitle]) {
      expect(find.text(t), findsOneWidget, reason: '九条里少了 $t');
    }
  });

  testWidgets('点那个入口进第二层', (tester) async {
    L10n.locale = 'zh';
    await _pump(tester);
    await tester.tap(find.text(L10n.faqEntryTitle));
    await tester.pumpAndSettle();
    expect(find.byType(HelpFaqScreen), findsOneWidget);
  });

  test('闹钟那一条的条数与 maxAlarmsPerShift 一致', () {
    L10n.locale = 'zh';
    expect(L10n.guideAlarmDesc.join(), contains('$maxAlarmsPerShift'),
        reason: '帮助里写着「最多挂 6 条」而实现是 10 条 —— 这条护栏就是为它加的');
    L10n.locale = 'en';
    expect(L10n.guideAlarmDesc.join(), contains('$maxAlarmsPerShift'));
    L10n.locale = 'zh';
  });

  test('九条功能简介里不许出现 markdown 标记', () {
    final bad = RegExp(r'\*\*|`|^#|\[[^\]]+\]\([^)]+\)', multiLine: true);
    for (final locale in const ['zh', 'en']) {
      L10n.locale = locale;
      final all = [...L10n.guideCalDesc, ...L10n.guideSchedDesc, ...L10n.guideAlarmDesc,
        ...L10n.guideTodoDesc, ...L10n.guideWidgetDesc, ...L10n.guideAppearanceDesc,
        ...L10n.guideLayoutDesc, ...L10n.guidePermDesc, ...L10n.guideUpdateDesc];
      for (final s in all) {
        expect(bad.hasMatch(s), isFalse, reason: '$locale 命中 markdown：$s');
      }
    }
    L10n.locale = 'zh';
  });
}
```

- [ ] **Step 2: 跑它，确认红**

```bash
cd app && flutter test test/help_center_test.dart
```
期望：编译不过（`help_center_screen.dart` 与 `L10n.helpIntro` / `L10n.faqEntryTitle` 都还不存在）。

- [ ] **Step 3: 在 `l10n.dart` 加新文案**

在「使用帮助（图标化条目）」那一节的前面新增：

```dart
// 使用帮助 · 第一级
static String get helpIntro => t(
  '倒班助手Pro 是一个纯离线的排班助手：班表设一次，它替你算好每天什么班、什么时候响闹钟，还能放到手机桌面上随时看。底部四个页面各管一件事——日历看班、闹钟管响铃、待办记事情、我的做设置。',
  'Shift Assistant Pro is an offline scheduling helper. Set your shift pattern once and it works out every day for you, rings when it should, and keeps a card on your home screen. The four tabs each do one job — Calendar for shifts, Alarm for ringing, Todo for notes, Me for settings.');
/// 第一级那颗入口按钮。
static String get faqEntryTitle => t('遇到问题？', 'Stuck?');
static String get faqEntrySubtitle => t(
  '「我想办一件事」与「它不对劲」——进来找怎么解决',
  'Things you want to do, and things that look wrong — find the answer here');
/// 第二层的页标题。
static String get faqTitle => t('遇到问题怎么解决', 'How to get things done');
```

- [ ] **Step 4: 补正九条**（`l10n.dart` 里 `guide*` 那一批）

三件事，逐条改：

1. **事实错**：`guideAlarmDesc` 里那句「一个班次最多挂 6 条闹钟」→ 与 `maxAlarmsPerShift` 一致（10 条），中英各一处。同一条里「零点班（00:00 上班）的响铃排在上班前 1 小时，也就是前一天晚上」改成**三档落点**的说法：响铃落在前一天、当天还是次日，是按上班时间算出来的，列表里会标。
2. **补缺席的功能**（各补一行，**只要「有这么个功能、在哪儿」这一句**，怎么用归第二层）：
   - `guideTodoDesc` 补「重复待办」：待办可以设成每天 / 每周几 / 每月某日自动出现。
   - `guideAppearanceDesc` 补「字体大小」：四档，App 自己管、不跟系统字号。
   - `guideSchedDesc` 补「按月排班」：不是固定循环的，可以按每个月 1 号重新开始排。
   - `guideTodoDesc` 或 `guideSchedDesc` 补「待办自动归档」：做完的会自己收进列表底部。
3. **中英两份都要改**，改完 `flutter test test/changelog_window_test.dart` 那类扫 `L10n` 的用例不受影响。

- [ ] **Step 5: 写 `help_center_screen.dart`**

骨架同 Task 3（`Scaffold` + `AppBar(FittedBox(Text(L10n.usageGuide)))` + `CenteredContent` + `ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24))`），页内三段：

1. `Text(L10n.helpIntro, style: AppTokens.rowSecondary.copyWith(height: 1.45, color: AppTokens.inkMuted(context)))`，下留 `AppTokens.spaceLg`。
2. 九条 `HelpEntry`，条目之间 `const SizedBox(height: 16)`（与现在弹窗里那份间距一致），数据就是现在 `showUsageGuideDialog` 里那个 `items` 列表（`(icon, title, lines)` 三元组），原样搬过来。
3. 入口：一张 `GlassTile(translucentFill: false, padding: EdgeInsets.zero)` + `GlassPressable` + `ListTile(leading: Icon(Icons.help_outline), title: Text(L10n.faqEntryTitle), subtitle: Text(L10n.faqEntrySubtitle), trailing: Icon(Icons.chevron_right_outlined))`，`onTap` 用 `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpFaqScreen()))`。这一行的配方**与「我的」页每一行逐字一致**。

页面里的分组标题用一个文件内私有的 `_sectionHeading`，写法同 Task 3。

`scrollToWidgets` 这一版就实现：给「桌面小组件」那一条套一个 `GlobalKey`，`initState` 里注册
```dart
if (widget.scrollToWidgets) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = _widgetsKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: AppTokens.durMed, alignment: 0.1);
  });
}
```
（`HelpCenterScreen` 因此是 `StatefulWidget`；没有 `scrollToWidgets` 时这段什么都不做。）

- [ ] **Step 6: 删掉弹窗版，改「我的」页那一行**

- `app_dialogs.dart`：删掉 `showUsageGuideDialog` 整个函数。
- `profile_screen.dart:321`：`onTap: () => showUsageGuideDialog(context)` →
  ```dart
  onTap: () => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
  ),
  ```
  并加 import；如果 `app_dialogs.dart` 在这之后还有别的用处（有的，`showChangelogDialog` 等），import 留着。
- `app_dialogs.dart` 顶上的 `_showHelpDialog` 的文档注释里提到「使用帮助」那句要跟着改准。
- `l10n.dart` 的 `usageGuideSubtitle`：现在写的是「每个功能在哪、怎么用」—— 点开之后是**整页**了，这句话仍然成立，但要顺一遍，确认它没有暗示「弹窗」或者把第二层的内容说漏（例：「每个功能在哪、怎么用；遇到问题也能进来查」/ 'Where each feature lives, how to use it, and what to do when something looks wrong'）。

- [ ] **Step 7: 跑全套测试 + 屏单**

```bash
flutter analyze          # 0 error / 0 warning
flutter test             # 期望 1011 + 本轮新增，全绿
```

改 `visual_screens.dart`：把 `18_usage_guide` 那条（`_DialogHost(showUsageGuideDialog)`）换成

```dart
(
  // 《使用帮助》从弹窗改成整页（v0.11.17）。它是全 app 最长的一屏之一：
  // 一段简介 + 九条 + 一个入口，弹窗那个形态在窄屏上早就该换了。
  slug: '18_help_center',
  title: '使用帮助',
  build: (db) async => const HelpCenterScreen(),
  needsOnboardingPrefs: false,
),
```

并新增第二层那一屏（同一文件里挨着放）：

```dart
(
  slug: '59_help_faq',
  title: '使用帮助 · 遇到问题',
  build: (db) async => const HelpFaqScreen(),
  needsOnboardingPrefs: false,
),
```

- [ ] **Step 8: 出图看图**

```bash
cd app && flutter test tool/visual/render_screens_test.dart --plain-name "使用帮助"
```
逐张打开 `build/visual/18_help_center_*.png` 与 `build/visual/59_help_faq_*.png` 看：浅色 / 深色 / 英文 / 横屏 / 小窗五档。**必须真的看图**，不是只看「测试过了」。

- [ ] **Step 9: Commit**

```bash
git add -A app/lib app/test app/tool
git commit -m "feat(help): 使用帮助改成整页，带第二层入口；补正九条功能简介"
```

---

### Task 5: 「我的 → 桌面」那一行改成跳进使用帮助

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart:246-252`
- Modify: `app/lib/features/profile/app_dialogs.dart`（删 `showWidgetGuideDialog`）
- Modify: `app/tool/visual/visual_screens.dart`（删 `35_widget_guide`）
- Modify: `app/lib/core/l10n.dart`（`widgetEntrySubtitle` 改准）
- Test: `app/test/help_center_test.dart`（追加）

**Interfaces:**
- Consumes: `HelpCenterScreen(scrollToWidgets: true)`（Task 4）
- Produces: 无

- [ ] **Step 1: 写用例（先看着它红）**

在 `help_center_test.dart` 追加：

```dart
testWidgets('scrollToWidgets 一路滚到「桌面小组件」那一条', (tester) async {
  L10n.locale = 'zh';
  tester.view.physicalSize = const Size(420, 800); // 必须矮到装不下，否则滚不动
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(
      home: HelpCenterScreen(scrollToWidgets: true)));
  await tester.pumpAndSettle();

  final title = find.text(L10n.guideWidgetTitle);
  final rect = tester.getRect(title);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(800),
      reason: '滚完之后「桌面小组件」那一条必须真的在视口里');
});

testWidgets('不传 scrollToWidgets 时停在页首', (tester) async {
  L10n.locale = 'zh';
  tester.view.physicalSize = const Size(420, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
  await tester.pumpAndSettle();
  expect(find.text(L10n.helpIntro), findsOneWidget);
});
```

- [ ] **Step 2: 跑它，确认第一条红**

```bash
cd app && flutter test test/help_center_test.dart --plain-name "scrollToWidgets"
```
期望：红（`scrollToWidgets` 那条路径还没接到「我的」页；如果 Task 4 已按上面实现，这条可能直接绿 —— 那就**把 Task 4 步骤 5 里那段 `addPostFrameCallback` 临时注释掉**，看它确实红，再放回来）。

- [ ] **Step 3: 改「我的」页那一行**

`profile_screen.dart:251`：`onTap: () => showWidgetGuideDialog(context)` →
```dart
onTap: () => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => const HelpCenterScreen(scrollToWidgets: true))),
```
`l10n.dart` 的 `widgetEntrySubtitle`：现在写的是「三张卡怎么加到桌面（小米机型在二级分类里）」，改成指向使用帮助的说法（例：「说明在《使用帮助》里，小米机型在二级分类里」/ 'Explained in the usage guide; Xiaomi hides them in a sub-menu'）。

- [ ] **Step 4: 删 `showWidgetGuideDialog`，同步屏单**

`app_dialogs.dart` 里删掉整个 `showWidgetGuideDialog`；`visual_screens.dart` 里删掉 `35_widget_guide` 那一条（它渲的就是这个弹窗，弹窗没了它就没有对象了）。`guideWidgetDesc` **留着**（第一级九条里那一条还在用）。

- [ ] **Step 5: 跑全套 + 出图**

```bash
flutter analyze && flutter test
cd app && flutter test tool/visual/render_screens_test.dart --plain-name "我的"
```
看 `07_profile_*.png`：那一行的副标题换了、点开的行为换了（行为图上看不出来，靠 Step 1 那两条用例）。

- [ ] **Step 6: Commit**

```bash
git add -A app/lib app/test app/tool
git commit -m "feat(help): 「我的 → 桌面」那一行改成跳进《使用帮助》并滚到小组件那一节"
```

---

### Task 6: 收尾验收

**Files:** 无新增（只跑、只看、只改文案）

- [ ] **Step 1: 全套**

```bash
cd app && flutter analyze && flutter test
```
期望：analyze 0 error / 0 warning；`flutter test` 全绿，条数 ≥ 1011 + 本轮新增。

- [ ] **Step 2: 工装全量出图 + 对比度审计**

```bash
cd app && flutter test tool/visual/
```
它会跑三件事：出图（`render_screens_test.dart`）、字号截断护栏（`text_fit_guard_test.dart`，新屏会自动进它的矩阵）、对比度审计（`contrast_audit_test.dart`）。
期望：**截断护栏 0**（新屏若有截断，这一条会点名是哪一屏哪一档）；对比度审计若报新屏，逐条看是不是真问题（长段落用 `inkMuted` 是有意的配方，但**深色档下要实测**）。

- [ ] **Step 3: 逐张看图**

打开 `app/build/visual/18_help_center_*` 与 `59_help_faq_*` 的全部档位（浅色 / 深色 / 英文 / 横屏 / 小窗）。看四件事：简介段落读不读得顺；九条与旧版弹窗相比有没有走样；第二层的「问题 → 答案」层次是不是一眼分得开；英文折行后还整不整齐。

- [ ] **Step 4: 反向验证本轮的两条护栏**

1. 把 `help_content.dart` 第 10 条里的 `10` 改回 `6` → `flutter test test/help_content_test.dart` 必须红；改回来。
2. 把 `l10n.dart` 里 `guideAlarmDesc` 的「10 条」改回「6 条」 → `flutter test test/help_center_test.dart` 必须红；改回来。

两条都要**先看着它红一次**才算数。

- [ ] **Step 5: 提交（如果前面几步改了文案）**

```bash
git add -A app
git commit -m "chore(help): 收尾 —— 字号护栏与对比度审计的调整"
```

---

## 完成之后

这一版改了用户可见的界面，按仓库惯例还要做两件**不属于本计划**的事（各自单独一轮，不要塞进这里）：
- 更新日志 prepend 一条 `0.11.17` 的条目（并删最旧一条，保持 10 条窗口）——由发版那一轮统一做。
- `AGENTS.md` 的版本史与「最近改动」——同上。
