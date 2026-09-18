# 触觉反馈系统 · 设计规格

- 日期：2026-09-18
- 目标版本：`0.8.2+93`（AI 只改末位 `Z` 与 `build`；`X.Y` 由用户决定）
- 状态：待评审
- 来源：v0.8.1 实机测试反馈（原话：「长按这个滑块的时候，它不是会触发这个连选吗？那它触发的时候能不能加个震动反馈啊，这样区分更明显一点」→ 进一步：「既然咱们新增了这个触觉反馈系统，那么能不能把它优化好，然后并应用到 APP 全部的可能会用到的地方呢？」）
- 前置：`docs/superpowers/specs/2026-09-18-per-day-shift-override-design.md`（按天改班，v0.8.1 已发布）

---

## 1. 背景与目标

v0.8.1 实测反馈里有一句「长按触发连选时加个震动，这样区分更明显」。顺着这条，把「震动」提升为一个**设计系统层**，铺到全 app 该用的地方。

这个 App 已经有同类的先例：`core/motion.dart` 就是「交互反馈的设计系统层」（弹簧物理 + `QScale` 按压缩放），而 `core/design_tokens.dart` + `design_tokens_test.dart` 是「令牌 + 守门测试」这套模式的样板。触觉反馈照这两者的样子做。

**目标**：建立一套按语义命名的触觉词汇表，把它铺到全 app 的**状态改变**与**不可逆动作**上；给用户一个 App 级开关；并用一条守门测试钉住它不被绕过。

**非目标**：见 §8。

---

## 2. 三个已定决策（来自 2026-09-18 的头脑风暴）

| # | 决策 | 理由 |
|---|---|---|
| ① | **只给「状态改变」与「不可逆动作」**，普通点击一律不震 | 震动一旦变成背景噪音，信息量就归零了，用户反而会去系统里把触觉整个关掉 —— 那时你想用震动区分的**那件事**也一起没了。iOS 与安卓的设计指南是同一立场 |
| ② | **给用户一个 App 级开关**，默认开 | 与主题 / 主色调 / 语言一样，都是可配的；且系统那层总开关关掉时不该是唯一的出路 |
| ③ | **圆点尺寸保持选择层的 20dp**，不与信息卡的 12dp 统一 | 它坐在 `ListTile.leading` 位、对面的打勾是 20dp，缩到 12 会失衡；信息卡里那 12dp 是行内元素，本来就该小一档（见 §7.4） |

---

## 3. 词汇表（`core/haptics.dart`）

**按语义命名，不按强度。** 调用方写 `Haptics.select()` 表达的是「选中变了」，不是「震得轻一点」——这样将来调整某个语义档位的强度时，不必回头改所有调用点。

| 名字 | 何时 | 底层 |
|---|---|---|
| `Haptics.select()` | 选中变了：开关翻转、胶囊段切换、选项胶囊选中、选择器提交、拖到新格 | `HapticFeedback.selectionClick()` |
| `Haptics.commit()` | 动作落实：删除类确认、应用改班 / 恢复轮转、切换排班方案 | `HapticFeedback.lightImpact()` |
| `Haptics.modeEnter()` | 进入一个模式：长按进入多选态 | `HapticFeedback.mediumImpact()` |

**只有三档。** 特意**不做**「危险」那一档：危险动作（删除）本来就有一层模态确认，用户在那里已经做过一次明确决定；再加一个第四档，真机上几乎分不出与 `commit` 的差别，却多一份要维护的词汇。若实机装上去觉得删除该更重，加回来是一行。

三个函数**一律返回 `void` 并按 fire-and-forget 处理**：`HapticFeedback.*` 返回的 `Future` 不该被等待，也不该让一个触觉调用的异常冒到业务逻辑里 —— 震不震不该影响功能。

### 3.1 开关的接线：抄 `advancedMaterialDisabled` 的先例

词表内部读一个**模块级标志**，而不是让每个调用点自己去查设置：

```dart
// core/haptics.dart
/// 用户是否开启触觉反馈（由「外观」设置反灌）。
bool hapticsDisabled = false;
```

由 `AppSettingsNotifier` 在 `_load()` 与 `setHapticsEnabled()` 两处赋值 —— 与 `advancedMaterialDisabled`（[glass.dart:11](app/lib/core/glass/glass.dart:11)，由 [app_settings.dart:66](app/lib/state/app_settings.dart:66) 与 `:103` 赋值）**完全同一条路**。

这样关掉之后，**所有**震动点一处生效，不需要每个调用点自己去查设置，也不会有人漏查。

---

## 4. 应用点清单

### 4.1 共享组件自己震（三类最高频的交互，谁都不用记）

放进组件内部，调用方零负担，新界面天然一致：

| 组件 | 位置 | 档位 |
|---|---|---|
| `GlassSwitch` | [glass_switch.dart:30](app/lib/core/widgets/glass_switch.dart:30) 的 `onTap` | `select()` |
| `GlassSegment` | [glass_segment.dart:132](app/lib/core/widgets/glass_segment.dart:132) | `select()` |
| `GlassChoiceChip` | [glass_choice_chip.dart:52](app/lib/core/widgets/glass_choice_chip.dart:52) | `select()` |
| 四个 glass picker 的**提交点** | 时间 `:123`、日期 `:205`、年月 `:403`、选项 `:501` 的 `Navigator.pop` | `select()` |

**两个必须注意的地方：**

- **选择器的滚轮滚动不算提交。** `showGlassTimePicker` 的 `onSelectedItemChanged`（[glass_pickers.dart:48](app/lib/core/widgets/glass_pickers.dart:48)）是滚动、不是选定，**不能**挂 —— 否则拨一次滚轮会连震十几下。只有 `Navigator.pop` 那一处算提交。
- **`GlassSegment` 只在选中项真的变了时才震。** 点当前已选中的那一段不该有反馈（状态没变）。

### 4.2 提交点显式震

不在共享组件里、必须在**状态提交的那一刻**调用：

| 动作 | 位置 | 档位 |
|---|---|---|
| 删除类确认 | `GlassDialog`（[glass_dialog.dart:11](app/lib/core/widgets/glass_dialog.dart:11)）里 `GlassActionVariant.danger` 那个按钮按下时 | `commit()` |
| 待办勾选完成 | [schedule_screen.dart:121](app/lib/features/schedule/schedule_screen.dart:121) | **不加** —— 见下方「一条自我纠正」 |
| 选择层应用「改成某班次」/「恢复轮转」 | `calendar_screen.dart` 的 `adjustDays` 里，落库之后 | `commit()` |
| 切换排班方案 | [calendar_screen.dart:532](app/lib/features/calendar/calendar_screen.dart:532) 的 `setCurrentSchedule` 之后 | `commit()` |

> ⚠️ **不要给闹钟页那条单条开关再加一次。** [alarm_screen.dart:234](app/lib/features/alarm/alarm_screen.dart:234) 与 `:277` 用的就是 `GlassSwitch`，§4.1 已经让它自动震了 —— 在那里再写一次就是**每拨一下震两下**。这类重复是本设计最容易犯的错：**先确认那个控件是不是已经在 §4.1 的名单里**。

#### 一条自我纠正：待办勾选那行原本是错的

上面那张表的第一版把「待办勾选完成」列为一个 `commit()` 点，位置指到 [schedule_screen.dart:121](app/lib/features/schedule/schedule_screen.dart:121)。**那是写这张表时的疏忽**：我照着「提交点」的思路列调用点，没有回头确认那个控件是什么 —— 而它（`:119`）就是一个 `GlassSwitch`，§4.1 已经让它自动震了。

照原样实现的话，拨一下待办会**连着震两下**（`select` 紧跟一个 `commit`），正是上面那条警告说的同一个错。**已裁定：不加。**

**为什么是「不加」而不是「保留 commit」**：

1. **spec 自己的立意就排除了它。** §1 说这些震动的价值在于「每个震动都携带信息」，§2 决策① 说只给状态改变与不可逆动作。一个动作震两下，携带的信息比一下**更少**，不是更多。
2. **待办勾选是可撤销的。** 取消勾选就回去了 —— 它不属于 `commit()` 文案里写的「这一步不可逆」，用 `select()`（选中变了）描述它更准。
3. **一致性。** 全 app 每一个 `GlassSwitch`（静音某条闹钟、高级材质、以及本轮新加的触觉开关本身）都只发一次 `select()`。单独让待办那个发两次，就成了项目一直在避免的「一处特例」。
4. §4.1 的通用规则（`GlassSwitch` → `select()`）是**有原则**的那条；§4.2 这张表是**枚举**，枚举漏看了一个事实。

**由此得到的通用规则**（写进计划与 `AGENTS.md`）：**§4.1 覆盖的控件（`GlassSwitch` / `GlassSegment` / `GlassChoiceChip` / 四个选择器提交点）绝不能再出现在 §4.2 的提交点表里。** 加任何一处之前，先确认它不在 §4.1 的名单里。

### 4.3 日历手势

| 手势 | 位置 | 档位 |
|---|---|---|
| 已有的单格滑块：点选与拖动落点 | `_selectFromPosition`（点选）**与** `onPanEnd`（拖动落点）里，`_selected` 真的变了时 | `select()` |
| 长按进入多选态 | `onLongPressStart` 判定成功（吸附到有效日期）时 | `modeEnter()` |
| 长按拖选每进一格 | `onLongPressMoveUpdate` 里 `_rangeFocus` 真的变了时 | `select()` |

> **单格滑块那行有两个落点，别只改一个。** 本表初稿只写了 `_selectFromPosition` —— 但那一路只从 `onTapDown` 走到；**拖动是 Pan**，一越过 slop 就把 Tap 识别器挤掉，落点走的是 `onPanEnd` → `_nearestDateFromVisual()`，**根本不经过 `_selectFromPosition`**。只改前者的话，滑块拖一次都不会震（实机一试就露）。两处都要，判据相同：吸附到的日期真的变了。

第三行是用户最初提的那条。范围**往回缩**时同样会响 —— 只要吸附到的格子变了就响，两个方向一致。

### 4.4 明确不震

- 普通按钮点击（`GlassButton` / `GlassActionButton` / `GlassDeleteButton` / `GlassPressable` 包的一切）
- 列表行点击（`ListTile`、方案行、设置行）
- 翻页、滚动、下拉
- 选择器的滚轮滚动（见 §4.1）

> `GlassPressable` 是**故意不挂**的：它包的是*每一次*按压，包括普通点击 —— 而决策 ① 正是「普通点击不震」。触觉挂在**动作**上，不挂在**按压**上。

#### 主题 / 主色调 / 语言这三段**在**此列之外（本轮改）

它们（[profile_screen.dart:51](app/lib/features/profile/profile_screen.dart:51) / `:70` / `:99`）用的就是 `GlassSegment`（§4.1），而翻一段是**真实的状态改变** —— 决策 ① 正是「状态改变给反馈」。所以它们跟着 §4.1 震，**不为它们开特例**。

本表初稿曾把「主题与语言切换」列为不震，理由是「这两样会重建整棵树，震动容易被吞掉」。**那个理由是错的**：触觉走的是 platform channel，`HapticFeedback.*` 的调用是**即发即忘**的 —— 消息在任何重建开始之前就已经发出去了（`core/haptics.dart` 的 `_fire` 就是这么写的），重建吞不掉它。真要让这三处不震，得给 `GlassSegment` 加一个 opt-out 开关，为一个不存在的问题引入一个 API，不划算。

（这条是「代码越过了规格写的边界」的一次正确收尾：**改话不改代码**。§2 决策 ① 是统辖原则，枚举性质的 §4.4 漏看了它的适用面。）

---

## 5. 开关

### 5.1 状态与持久化

`AppSettings`（[state/app_settings.dart](app/lib/state/app_settings.dart)）加一个字段，**照 `advancedMaterial` 那条路一模一样地走**：

```dart
final bool hapticsEnabled;   // 默认 true
```

- 进构造函数默认值、`copyWith`、`AppSettingsNotifier._load()`（`sp.getBool('hapticsEnabled') ?? true`）、以及一个新的 `setHapticsEnabled(bool)`
- `_load()` 与 `setHapticsEnabled()` 两处都要给 `hapticsDisabled` 赋值（`hapticsDisabled = !hapticsEnabled;`）

### 5.2 设置页

「外观」分区（[profile_screen.dart:42](app/lib/features/profile/profile_screen.dart:42)）里，在「高级材质」那一行下面加一行，形状与它**完全一致**（同一种标题 + 副标题 + 右侧 `GlassSwitch` 的 `GlassRow` 配方，[profile_screen.dart:125-142](app/lib/features/profile/profile_screen.dart:125)）。

新增文案（`l10n.dart`，zh / en 成对）：

| 用途 | 中文 | English |
|---|---|---|
| 开关标题 | 触觉反馈 | Haptic feedback |
| 副标题 | 切换开关、选中、删除确认时轻微震动 | Subtle vibration on toggles, selections and delete confirmations |

副标题写**会引起什么**，而不是「要不要开」。这与权限卡那条「每行副标题写『不开会怎样』而不是『要不要开』」是同一个立场：副标题回答的是「这对我意味着什么」。这里也刻意**不提**「可以关掉」——那正是这个开关本身。

---

## 6. 守门与测试

现有 **239 条只增不减**。（写本 spec 时 217 条；本轮功能落地后 236；最终评审的修复波又追加 3 条断言 —— 每一条都补在一个原先「删掉那行代码也不会红」的落点上。）

### 6.1 源码扫描（抄 `design_tokens_test` 的做法）

新增一条用例，扫 `lib/` 源码：

- **除 `core/haptics.dart` 外，任何文件出现 `HapticFeedback.` 就算违规。** 这样词表不会被绕过、新代码想震就必须走那三个名字。
- 扫描前先剥离注释与字符串（`design_tokens_test` 已有这个处理，照抄它的做法），否则在注释里提一句 `HapticFeedback` 就会误报 —— 这个坑那个文件踩过。
- 失败信息要**指名道姓**：哪个文件哪一行、应该改用哪个 `Haptics.*`。

### 6.2 词汇表完整性

照 `design_tokens_test` 的「令牌自检」那条：读 `core/haptics.dart` 的源码，断言三个名字**都在**本测试文件里被断言过 —— 加了一个档位却忘了加断言时，这条会红。理由与那个文件里的注释一样：手写枚举的 `expect` 列表加漏一个，测试照样绿。

### 6.3 行为测试

- **开关关掉后不震**：把 `hapticsDisabled` 置真，触发一次交互（例如翻转一个 `GlassSwitch`），断言 platform channel 上**没有**触觉调用。用 `tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, …)` 拦 `HapticFeedback.*` 对应的 `SystemChannels.platform` 调用。
- **开着时会震**：同一场景下断言恰好一次、且是预期的那一档。
- **长按两级**：长按进入多选态一次 `modeEnter`，之后每换一格一次 `select`（用现有的 `midDrag` 钩子，那个钩子本来就是为「松手前断言」准备的）。
- **选择器滚轮不震**：拨动时间选择器的滚轮，断言无触觉调用；点确定才震一次。

---

## 7. 顺带修掉 v0.8.1 反馈里的四处设计语言偏差

这四条来自同一次实机反馈的第一问（「新增的这些界面是不是没有适配咱们的设计理念呀」）。**用户的直觉是对的，但问题不在结构上** —— 新选择层逐字段复刻了 `showGlassOptionPicker` 的配方，`design_tokens_test` 也全绿（**没有任何字面量违规**）。问题出在为按天改班新加的几处装饰件上：它们没有现成的最近同类件可抄，就各自发挥了。

### 7.1 「已调整」改成胶囊

现状是一串光秃秃的彩色文字（[calendar_screen.dart:1505](app/lib/features/calendar/calendar_screen.dart:1505)），而**同一行**上另外两个徽章都是胶囊：「今天」是主色实心胶囊、「N 项待办」是「信息胶囊」配方（14% 淡染 + 45% 描边 + `radiusL` + `inkFor` 文字）。

改成抄**最近的那个同类件** —— `_todoHintBadge` 的容器配方（去掉图标，只留文字）。

> ⚠️ **这一改会撞上定高约束。** 信息卡是定高的（`_bottomCardHeight` / `info_card_metrics.dart`），而胶囊比纯文字高。所以**必须同时把「已调整」纳入 `info_card_metrics.dart`** —— 那个文件存在的意义正是「让定高被破坏这件事在发布前就暴露」。顺带这也清掉上一轮记为欠账的那条（`info_card_metrics` 没有把该标记纳入模型）。

### 7.2 信息卡的点击反馈：去掉 Material 水波纹

现在套的是 `InkWell`（[calendar_screen.dart:1454](app/lib/features/calendar/calendar_screen.dart:1454)），按下去是 **Material 水波纹** —— 而这个 App 通篇的按压反馈是 `GlassPressable` 的 Q 弹缩放，**没有任何玻璃面带过水波纹**。

原因是我当时的裁定：`GlassPressable` 没有 `onTap`，那就套个 `InkWell`。**改成套一个只拿点击、不加波纹的手势层**（`GestureDetector` + `HitTestBehavior.opaque`，放在 `GlassPressable` 内部），拿到缩放反馈、去掉水波纹。禁用态（空白表）传 `onTap: null`。

### 7.3 长按范围的底色 18% → 14%

`primary.withValues(alpha: 0.18)`（[calendar_screen.dart:1056](app/lib/features/calendar/calendar_screen.dart:1056)）是全 app 唯一的 18% 淡染 —— 其余一律 14%。改回 14%，跟上约定。

### 7.4 圆点尺寸：**保持 20dp**，但把理由写进注释

决策 ③。需求是「让两个尺寸成为**有据可查的决定**而不是遗漏」—— 把分工理由写进 `_ClassDot` 的文档注释：它在 `ListTile.leading` 位、对面打勾是 20dp；信息卡里那 12dp 是行内元素。

---

## 8. 明确不做

- **第四档「危险」震动**（理由见 §3；实机有需要再加，是一行）
- **普通点击的触觉**（决策 ①）
- **强度分档**（关 / 轻 / 标准）—— 三层设置对一个小助手偏重，且两档之间的差异在真机上未必分得出来
- **可自定义的触觉模式 / 节奏**（长震、双震之类）
- **`HapticFeedback.vibrate()`**（那是一次长震，语义上属于「警报」，本 app 不需要 —— 闹钟响铃走的是原生 `Vibrator` 的循环震动，是另一条链路，本轮不碰）

---

## 9. 收尾

- **渲染工装补屏单**：把新界面加进 `app/tool/visual/visual_screens.dart`（调整班次选择层、被调整那天的日历、带「已调整」的信息卡、长按范围态），改完**出图比对前后**再交付。这是本轮的防复发措施 —— 上一轮之所以三道评审都没拦住这些偏差，正是因为守门测试只查字面量、而新界面从没进过屏单，**没有人真正「看过」它**。
- `PRODUCT_SPEC.md`：§6 设计系统一节补上「触觉反馈」这条（与「设计令牌」并列）；§2「我的 / 设置」一节的设置项清单补「触觉反馈」；抬头版本号跟着走。
- `README.md`：功能清单补一条。
- `AGENTS.md`：`core/` 的文件地图补 `haptics.dart`；「关键决策与坑」加一条（**触觉挂动作不挂按压；除 `core/haptics.dart` 外不许直接调 `HapticFeedback`，由守门测试盯着**）；版本史加一条。
- 更新日志（`features/profile/app_dialogs.dart`）按现有规则：本轮是测试版（末位非 0），条目原样写自己这版改了什么。

---

## 10. 风险与坑

1. **重复震动**：`GlassSwitch` 自动震之后，闹钟页那两条单条开关**不需要**再显式震（§4.2 的警告）。任何「共享组件已覆盖」的地方都要先确认再写。
2. **`HapticFeedback` 会被系统「触摸反馈」关掉**：这不是 bug，是应有的行为。测试里断言 platform channel 的调用，**不要**去断言「用户一定感觉得到」。
3. **不要在 `build()` 或 `setState` 里调触觉** —— 会在重建时重复触发。一律放在事件处理里。
4. **fire-and-forget**：`HapticFeedback.*` 的 `Future` 不要 await、异常不要上抛（§3）。
5. **定高契约**（§7.1）：改「已调整」成胶囊时，`info_card_metrics.dart` 必须同步更新，否则信息卡会随内容长高、整个网格跟着跳。这是这个文件存在的全部理由。
6. **不要跑 `dart format`** —— 工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
7. **版本号两处同步**：`app/pubspec.yaml` 与 `app/lib/core/app_info.dart`，由 `app/test/app_info_test.dart` 盯着。
