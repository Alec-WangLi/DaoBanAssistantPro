# 模板双语化与周期色条截断提示 · 设计规格

- 日期：2026-09-12
- 目标版本：`0.6.2+73`（测试版）
- 状态：待评审

---

## 1. 背景与目标

### 1.1 现状

用户实测 v0.6.1：**英文界面下，19 张倒班方式模板卡的标题与副标题仍是中文。**

排查后发现问题的范围比「卡片上的两行字」大得多 —— 模板里的中文有一部分会**写进数据库**：

1. **卡片文案**：`ShiftTemplate.title` / `subtitle` / `aliases` / `group` 全部硬编码中文。
2. **方案名会被持久化**：`createScheduleFromTemplatePicker` 把模板的 `subtitle` 直接当方案名存下来。英文用户建完方案，「排班管理」与「切换排班」里躺着一条「白夜休休 · 四班两倒」。
3. **班次名与简称会被持久化**：模板的 `classes` 里班次名是 `白班/夜班/休班`、简称是 `白/夜/休`。这两个字段落库后被「班次设置」与「周期设置」引用，**简称还会逐格画在日历上** —— 英文用户的日历整月都是中文单字。
4. **「我自己排」同样中招**：`defaultSchedule()` 硬编码了方案名 `四班两倒`、班组名 `一班…四班`、班次 `白班/上夜班/下夜班/大休`。它是「我自己排」、清空重置、编辑器从空白表切回普通表的共同输入。
5. **搜索词只有中文**：英文用户搜 `4-crew` 搜不到任何东西。

根因是一条明确的旧决策：`l10n.dart::templateGroup` 的注释写着「模板本身的标题/副标题不在这里翻 —— 那是内容文案，不是界面标签」。这条区分本身没错，但它导致模板文案被整体排除在本地化之外，且**没有第二个人负责**。本规格撤销这条决策。

### 1.2 目标

1. 英文界面下，从模板新建的方案，**从卡片 → 编辑器 → 日历格子 → 排班列表，全链路不出现中文**。
2. 中文界面的行为**逐字节不变**（文案、搜索、分组顺序都不动）。
3. 模板的**结构**（周期表、班组数、相位、时间、颜色、闹钟）与本次改动完全解耦，一个字节都不改。

### 1.3 非目标

- **不迁移已存库的中文数据**。用户已经建好的方案、班次名是他的数据，不因为切了语言就改名。新建设置走新逻辑，存量保持原样。
- 不引入第三种语言。
- 不做「切换语言时自动重命名」这类隐式改写。

---

## 2. 设计

### 2.1 两层拆分

模板拆成**语言无关的结构**与**双语文案**两层。模板自身的文案（标题/副标题/别名）不进 `l10n.dart`，而是与被描述的结构放在同一个文件里 —— 这样「加一个模板」和「给它写两句文案」是同一次编辑，不存在漏翻的窗口。

`l10n.dart` 只放两样东西：

1. **`L10nText` 原语**（一段双语文案的持有者，见 §2.3）—— 它是通用本地化设施，放这里。
2. **分组名的映射** `templateGroup(String key)`（5 条）—— 分组是界面标签，与模板内容不同源。

**班次角色的名称与简称放在 `shift_templates.dart`，不放 `l10n.dart`。** 原因是一条依赖方向：`ShiftRole` 是领域类型，定义在 `domain/`；若 `core/l10n.dart` 为了给角色起名反过来 import `domain/shift_templates.dart`，就形成了 core ↔ domain 的循环依赖。而 `shift_templates.dart` 本来就依赖 `l10n.dart`（用 `L10nText`），把角色名放它这边是单向的。

### 2.2 班次角色（新增）

模板里的班次原型不再自带名字，只带一个**角色**；名字与简称由角色经 `L10n` 按当前语言解析。

```dart
/// 班次在模板中的语义角色。名称与简称按当前语言生成，
/// 结构字段（时间/颜色/闹钟/是否休息）仍由原型自带。
enum ShiftRole { day, night, morning, afternoon, evening, duty, off, rest }
```

| 角色 | 中文名 / 简称 | 英文名 / 简称 | 用在 |
|---|---|---|---|
| `day` | 白班 / 白 | Day shift / D | 12 小时制白班、常白 |
| `night` | 夜班 / 夜 | Night shift / N | 12 / 8 / 6 小时制的夜班 |
| `morning` | 早班 / 早 | Morning shift / M | 8 / 6 小时制的早班 |
| `afternoon` | 中班 / 中 | Afternoon shift / A | 8 / 6 小时制的中班 |
| `evening` | 晚班 / 晚 | Evening shift / E | 6 小时制的晚班 |
| `duty` | 值班 / 值 | Duty / D | 24 小时值班 |
| `off` | 休班 / 休 | Off / O | 浅灰休息（`0xFF9AA0B4`） |
| `rest` | 休息 / 休 | Rest / R | 深灰休息（`0xFF5A5F73`） |

**英文简称取单字母**：日历格子宽度按 1–2 个汉字设计，英文用单字母才不会破版。`duty` 与 `day` 的简称都是 `D`，但二者从不共存于同一个模板，不冲突。`morning`(M) / `afternoon`(A) / `evening`(E) / `night`(N) 四个各不冲突 —— 这是把「中班」译作 Afternoon 而不是 Mid 的原因（Mid 的首字母 M 会与早班撞车）。

`off` 与 `rest` 是两个休息色（浅灰 / 深灰），中文名现有就是「休班」「休息」两个词，英文取 `Off` / `Rest` 加以区分 —— 否则编辑器下拉里会出现两条一模一样的条目。

**不设独立的「常白」角色**：常白模板用的班次与 12 小时制白班同名同色（都叫「白班」、都是 `0xFF4C8DFF`），只差时段，时段本来就是原型自带的结构字段。多设一个产出完全相同文案的角色是空转；哪天常白要换个说法再单独加。

### 2.3 模板原型与文案

```dart
/// 双语文案。英文缺省时**不回退中文** —— 缺了就该被测试抓出来，
/// 悄悄回退会让漏翻在英文界面上伪装成正常内容。
class L10nText {
  const L10nText(this.zh, this.en);
  final String zh;
  final String en;
  String get value => L10n.isEn ? en : zh;
}

class ShiftTemplateSpec {
  final String id;
  final String groupKey;          // 'h12' | 'h8' | 'h6' | 'duty' | 'office'
  final L10nText title;
  final L10nText subtitle;
  final List<String> aliases;     // 中英关键词**都放**，搜索不分语言
  final List<ShiftClassProto> classes;
  final List<int> cycle;
  final int teamCount;
  final List<int> teamOffsets;
}
```

`ShiftClassProto` = 现有 `ShiftClass` 去掉 `name` / `abbr`，加上 `role`。`toClass()` 在调用时经 `L10n` 解析成 `ShiftClass`。

对外接口保持形状不变，调用方改动最小：

```dart
class ShiftTemplate {
  List<ShiftClass> get classes;        // 原型 → 按当前语言解析
  String get title;                    // = spec.title.value
  String get subtitle;                 // = spec.subtitle.value
  int get workingTeamsPerDay;          // 读**原型**的 isRest，见下
}
```

`workingTeamsPerDay` 必须读原型而不是 `classes` —— 它每次 build 都会被卡片调用，而 `classes` 是每次现算的列表，让它去分配一份临时列表是白白的开销；「是否休息」本来就是结构字段，不走本地化。

### 2.4 搜索匹配

`_matches` 改为匹配：当前语言的 `title` / `subtitle` + `aliases`（中英混合，两语言都能命中）+ `id`。

`aliases` 中英并收，因此中文用户搜「四班三倒」、英文用户搜 `4-crew` 都能中；英文用户打中文关键词也能中（不特意支持，但顺手就有）。

### 2.5 分组键

`shiftTemplateGroups` 由中文列表改为语言无关键：`['h12', 'h8', 'h6', 'duty', 'office']`。

`ShiftTemplateSpec.groupKey` 存键，显示时过 `L10n.templateGroup(key)`。`templateGroup` 的 `switch` 从「匹配中文字面量」改为「匹配键」，并删掉那条「模板标题/副标题不在这里翻」的注释 —— 它所代表的决策已被本规格撤销。

### 2.6 默认方案

`defaultSchedule()` 同样改造：方案名、班组名、四个班次名与简称全部走 `L10n`。方案名取 `t('四班两倒', '4-crew 2-shift')`，班组名复用现成的 `L10n.defaultTeamNames(4)`。

它是「我自己排」→ 编辑器、清空重置、编辑器从空白表切回普通表三条路径的共同输入，改这一处三处都跟着好。

### 2.7 周期色条截断提示

`shift_template_picker_screen.dart::_cycleStrip` 现在写死 `t.cycle.take(14)`，7 个一行共两行；28 天的 DuPont 只画 14 个色块，剩下的**静默消失**。

改法：**周期长于 14 天时，第 14 格换成省略标记**（居中的「…」，用中性色，不占班次色）。保持 7×2 的网格节奏不被破坏，同时眼睛能看出「还有后半截」。副标题里的「28 天周期」保留 —— 有了省略标记，它从「唯一线索」变成「补充说明」，这是它该有的位置。

不采用「把 28 天全画出来」：周期上限 60 天，卡片高度会随模板剧烈起伏，且 60 个色块在手机宽度下每个不到 5px，认不出任何东西。

同时把写死的 `width: dot * 7 + 12` 改为按实际间距计算（`dot * 7 + spacing * 6`），避免以后改间距时宽度对不上。

### 2.8 首启落库的语言竞态（必须一并修）

`defaultSchedule()` 一旦按当前语言生成，就暴露出一个**既有的**竞态：首启时 `activeScheduleProvider` 会调 `seedIfEmpty` 把默认方案写进数据库，而此时语言可能还没定下来。

具体时序：

1. `AppSettingsNotifier` 构造时异步 `_load()` 读 SharedPreferences，初始 state 的语言是默认值 `'zh'`。
2. `ShiftAssistantApp.build` 先按 `'zh'` 设置 `L10n.locale`。
3. `activeScheduleProvider` 首次被 watch → `seedIfEmpty(db)` 落库。
4. `_load()` 完成，语言变 `'en'`，`L10n.locale` 更新。

第 3 步与第 4 步是两条独立的异步链，**谁先谁后不确定**。英文用户首启若 `seedIfEmpty` 抢在前面，他的第一套排班（方案名与四个班次名）就是中文的 —— 正是本规格要消灭的那类缺陷。

修法：**把语言读取提到 `runApp` 之前**（`main()` 里从 SharedPreferences 读一次 `language` 写进 `L10n.locale`）。播种最早也在首帧之后，那时语言早已就位 —— 竞态从「两条异步链赛跑」变成确定的顺序。

考虑过但没采用的方案：给 `AppSettingsNotifier` 加一个 `ready` future，让 `activeScheduleProvider` 在落库前 `await` 它。它同样有效，但要多改一个文件、并让 `data/` 反向依赖 `state/`；而 `main()` 里那几行更短、顺序更硬，也顺带让首帧就是正确的语言。

只有首启这一条路径有这个竞态。`clearAll()`（清空重置）与 `deleteSchedule()` 触发的重新播种都是用户操作，那时语言早已确定，不必改。

---

## 3. 受影响文件

| 文件 | 改动 |
|---|---|
| `core/l10n.dart` | 新增 `L10nText` 双语文案原语；`templateGroup` 的 switch 由中文键改为语言无关键 |
| `domain/shift_templates.dart` | 重构为原型 + 双语文案；新增 `ShiftRole`、角色名表、`ShiftClassProto`、`ShiftTemplateSpec`；`ShiftTemplate` 变为读取期视图；分组值改键 |
| `domain/shift_rotation.dart` | `defaultSchedule()` 改为按当前语言生成 |
| `main.dart` | `runApp` 之前从 SharedPreferences 读一次语言（见 §2.8） |
| `features/calendar/shift_template_picker_screen.dart` | 搜索匹配规则、色条省略标记、分组取键 |

`domain/` 两个文件保持**纯 Dart、无 Flutter 依赖**。`shift_rotation.dart` 会因此新增一个对 `core/l10n.dart` 的导入 —— `l10n.dart` 只依赖 `intl`（纯 Dart），所以「可直接 `dart test`」这个性质不受影响，但这是 domain 层第一次依赖 core，记在此处备查。

---

## 4. 边界与容错

| 场景 | 行为 |
|---|---|
| 英文文案缺省 | 显示空串并**由测试抓出**（不静默回退中文） |
| 存量中文方案切到英文 | 名称、班次名原样保持（用户数据不动） |
| 英文用户建完方案再切回中文 | 方案名与班次名保持建时的语言（已落库，不再跟随） |
| 中文界面 | 逐字节不变 |

「建完方案再切语言，名字不跟着变」是**预期行为**而非缺陷：方案名是用户可编辑的自由文本，建成那一刻就归属用户了。这一点写进更新说明的注意事项，避免被当成 bug。

---

## 5. 范围外（本次明确不做）

- 存量数据的中文名迁移或自动重命名。
- 第三种语言。
- 模板的结构、周期、班组、时间、颜色、闹钟的任何调整。
- 模板卡片的视觉重做（字号与间距统一在 v0.6.3 处理）。

---

## 6. 验收标准

1. `flutter analyze` —— 0 error / 0 warning。
2. `flutter test` —— 全绿，且新增：
   - **英文无中文**：在 `L10n.locale == 'en'` 下遍历全部 19 个模板，断言 `title` / `subtitle` / 每个 `classes[i].name` / `abbr` 均**不含 CJK 字符**（用字符区间判定，不用肉眼）。
   - **中文不回归**：切回 `'zh'`，断言上述字段与当前 v0.6.1 的取值逐条相等（把现值抄进测试作为基线）。
   - **落库路径无中文**：模拟 `createScheduleFromTemplatePicker` 的建方案逻辑（英文 locale），断言写进 repository 的 `name`、`teamNames`、`classes` 全无 CJK。
   - **默认方案无中文**：英文 locale 下 `defaultSchedule()` 的 name / teamNames / classes 全无 CJK。
   - **首启落库跟随语言**：英文 locale 下对空库跑 `seedIfEmpty`，读回方案名、班组名、班次名断言全无 CJK（这条覆盖 §2.8 的竞态修复）。
   - **文案完整性**：遍历 19 个模板，断言 `title` 与 `subtitle` 的中英均非空、`aliases` 非空。
   - **搜索命中**：英文 locale 下用 `4-crew`、`dupont`、中文 `四班三倒` 分别搜，断言都能命中对应模板。
   - **色条省略**：`cycle.length > 14` 的模板渲染出的色块数 = 13，且第 14 格是省略标记；`cycle.length <= 14` 的模板色块数不变。
3. 手工验收：切英文 → 从「白白夜夜休休」建方案 → 依次看模板卡、编辑器、日历格子、排班管理列表，确认无中文；切回中文确认与 v0.6.1 一致。
4. 视觉工装：英文变体出图，**肉眼抽查首屏可见的几张卡片**无中文、DuPont 卡片带省略标记。
   注意出图的局限：模板列表是懒构建的 `ListView`，一屏只渲染前 4–5 张卡片，**「19 张全部无中文」不能靠出图证明**，那是第 2 条穷举测试的职责。出图在这一版的作用是看排版（省略标记的位置与观感），不是查漏翻。

---

## 7. 版本与更新日志

- 版本号同步升到 **`0.6.2+73`**（`0.6.1+72` 之后；`+build` 是 Android versionCode，必须单调递增）。
- 更新日志（`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`）prepend 一条，删最旧一条，保持 10 条。测试版条目只写自己这版改了什么。
- 双语条目内容：英文界面下倒班方式模板的标题、副标题与新建后的班次名不再出现中文；模板卡周期色条超过两行时给出省略标记。
- **不得出现任何「参考 / 借鉴 / 对照 / 类似某 App」的表述。**

---

## 8. 修订记录

| 日期 | 变更 |
|---|---|
| 2026-09-12 | 初稿。经确认：分三个版本推进（本份为 0.6.2）；文案与结构同文件、不进 `l10n.dart`；色条截断用占一格的省略标记；不做存量数据迁移 |
| 2026-09-12 | 写实现计划时自检修正三处：① **角色表漏了「早班」** —— 8/6 小时制模板全在用，按原表实现会把早班显示成「中班」，补 `morning`/`afternoon` 两个角色并删掉与 `day` 产出完全相同的 `office` 角色；② 补 §2.8 首启落库的语言竞态（`defaultSchedule()` 按语言生成后，播种可能早于语言加载完成）；③ 修正验收里「出图确认 19 张卡片」的说法 —— 列表懒构建，出图证明不了穷举，那是测试的职责 |
| 2026-09-12 | §2.8 的修法由「设置层加 `ready`、数据层 await」改为「`main()` 里在 `runApp` 前定语言」：少改两个文件、少一条 `data/` → `state/` 的反向依赖，且顺序是确定的而不是两条异步链赛跑 |
