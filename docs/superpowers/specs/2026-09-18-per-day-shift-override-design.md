# 按天改班（换班 / 请假覆盖） · 设计规格

- 日期：2026-09-18
- 目标版本：**待定** —— 本轮是「新功能 + schema 变更」，够不够到 `0.9.0` 由用户决定；AI 只改末位 `Z` 与 `build`
- 状态：待评审
- 来源：用户反馈（原话：「能单独设置某天的班次吗？因为某天可能休假或者跟别的同事调班嘛。现在这个排班表排完之后就固定了」）
- 前置：无。`docs/superpowers/specs/2026-09-11-shift-cycle-editor-design.md` 的成果（两层模型）是本文的地基

---

## 1. 背景与目标

`PRODUCT_SPEC.md` §2「明确不做」清单里有一条：

> 日历上直接改某一天（换班/请假覆盖）

本轮正式翻案。用户反馈里点名的两个场景 —— **请假**（那天不上班）与**跟同事调班**（那天换成另一个班）—— 现在都只能靠改整套排班方案来变通，改完还会污染整张轮转表。

好消息是当初就留了口子。`PRODUCT_SPEC.md` §4 的原话：

> 某天的班次**不落库**，按「周期起始日 + 周期序列」实时计算（**为未来「换班/请假覆盖」留余地**）

所以本轮不是把模型推倒重来，而是**给那个预留的口子补上一张覆盖表**，并让「某天是什么班」这个问题的答案统一走一个出口。

**目标**：日历上能对某一天或连续的一段日子单独指定班次；这件事只在「我们班组」生效；联动闹钟自动跟着变。

**非目标**：见 §10。

---

## 2. 四个已定决策（来自 2026-09-18 的头脑风暴）

| # | 决策 | 理由 |
|---|---|---|
| ① | 覆盖**只能从本方案已有的班次定义里挑** | 颜色 / 时间 / 简称 / 闹钟全是现成的，与轮转出来的班次长得一模一样。请假 = 挑个休班，调班 = 挑对方那个班 |
| ② | **支持一次圈一段连着日期** | 连休 3 天、出差一周是常态，一天天点太烦。底层仍是每天一行 |
| ③ | **空白表方案（跟随法定节假日）不给改** | 那套方案 `classes` 与 `cycle` 都是空的，没有池子可选；为它单开一条特例会把数据模型搞脏 |
| ④ | **让班次 id 稳定** | 见 §4 —— 这是本轮工作量最大的一块，也是覆盖面最杂的一块 |

---

## 3. 数据模型

### 3.1 新表 `ShiftDayOverrides`

`schemaVersion` **7 → 8**。

| 列 | 类型 | 说明 |
|---|---|---|
| `scheduleId` | `int` | 属于哪套排班方案。**复合主键之一** |
| `day` | `int` | 纯日期自 epoch 的天数，复用现成的 `dayNumber()`。**复合主键之一** |
| `classId` | `int` | 这天改成哪个班次定义（`shift_class_rows.id`） |

复合主键 `{scheduleId, day}` 带来两条语义：

- 覆盖**跟着方案走**：切到另一套方案时，这套的覆盖不生效 —— 因为「这天是什么班」整个都变了。
- 删方案时连带删覆盖。

迁移：

```dart
if (from < 8) {
  await m.createTable(shiftDayOverrides);
}
```

放在现有 `onUpgrade` 里的哪儿都行（都是一次性建表），按现有倒序习惯放最前面。

### 3.2 一处**有意的不一致**，写下来免得后人当 bug 修

已有的 `ShiftAlarmOverrides`（按天关班次闹钟）**是全局的** —— 只有 `day` 一个主键，不带 `scheduleId`。新表带 `scheduleId`，两者不一致。

这是有意的，不要「顺手统一」：`ShiftAlarmOverrides` 表达的是「**那天别响**」，这个意图跨方案也说得通（用户在那天有事，不管当期是哪套方案都不想被闹钟吵）；而 `ShiftDayOverrides` 表达的是「**那天上哪个班**」，它必然依附于某套方案的班次定义。**本轮不动 `ShiftAlarmOverrides`。**

---

## 4. 班次 id 稳定（决策 ④）

### 4.1 问题

`AppRepository.saveSchedule` 每次保存都无条件地把该方案的班次行**删光重建**（[app_repository.dart:251-275](app/lib/data/app_repository.dart:251)）：

```dart
await (db.delete(db.shiftCycleRows)..where((t) => t.scheduleId.equals(id))).go();
await (db.delete(db.shiftClassRows)..where((t) => t.scheduleId.equals(id))).go();
// …然后逐条 insert，拿到全新的自增 id
```

于是**只要保存一次，所有 `classId` 就全变了** —— 用户哪怕只是把方案名从「四班两倒」改成「我们组」也一样。新表若直接存 `classId`，覆盖会在第一次保存之后全部指飞。

顺带一提，这个实现跟两层模型的本意是拧着的：`PRODUCT_SPEC.md` §3 写的是「**班次定义只需配一次**」，「一个班次只定义一次」，但实现每次保存都当新班次重新定义一遍。本轮正好把它掰回来。

### 4.2 做法

**`ShiftClass` 加一个 `int? id`**（`domain/shift_rotation.dart`）：

- `null` = 还没落库的新班次；非空 = 库里那一行的 id。
- 进 `==` / `hashCode` / `copyWith`。两个「内容相同但 id 不同」的 `ShiftClass` **不相等** —— 它们是两个不同的实体，这正是我们要的语义。
- `defaultSchedule()` 造出来的班次 `id` 全是 null（它随后由 `seedIfEmpty` 或 `saveSchedule` 落库）。

**`saveSchedule` 从「删光重建」改成增量**：

- 新列表里**带 id** 的 → `UPDATE`（不再删旧行）
- 新列表里**没 id** 的 → `INSERT`
- 库里**不在新列表里**的 id → `DELETE`

这样改班次时间、改颜色、改方案名，id 都不动，覆盖稳稳指着。

**删除班次时**：引用它的覆盖行一并删掉（在 `saveSchedule` 的收尾里扫一遍悬空 `classId` 即可，不用在编辑器里单独处理）。

**其余要连带删覆盖的地方**：`deleteSchedule`（删方案）、`clearAll`（清空全部数据）。

### 4.3 这条改动的成本

要动 `schedule_editor_screen.dart`：`_classes` 是 `List<ShiftClass>`，只要它带着 id 走就行（`_editClass` 是一个**显式构造 `ShiftClass` 的专用函数，并不是 `copyWith`** —— 它必须把 `id: c.id` 带上；之所以不用 `copyWith`，是因为 `copyWith` 没有把可空字段**清成 null** 的通道，切休班时时间 / 闹钟清不掉；`_deleteClass` 走 `removeAt`，其余班次的对象不变、id 跟着对象走）。**`_deleteClass` 里那段「周期下标整体前移」的逻辑不受 id 影响**，不用改。

**一处容易搅混的地方**：`_deleteClass` 的注释（[schedule_editor_screen.dart:1232](app/lib/features/calendar/schedule_editor_screen.dart:1232)）说「删除会把周期里比它大的下标整体前移」。那是 **`_cycle` 里的下标**，与 `ShiftClass.id` 是两码事 —— 别把两者搅在一起。本轮不碰 `_cycle` 的这套下标语义。

---

## 5. 领域层：一个出口（本轮的骨干）

`ShiftSchedule` 加一个字段：

```dart
/// 按天覆盖：dayNumber(日期) → classes 下标。
/// 与其他班次查询同口径 —— 存的是下标，不是 classId。
final Map<int, int> dayOverrides;   // 默认 const {}
```

`shiftOn` 变成覆盖感知：

```dart
ShiftClass? shiftOn(DateTime date) {
  final ov = dayOverrides[dayNumber(date)];
  if (ov != null && ov >= 0 && ov < classes.length) return classes[ov];
  return teamShift(ourTeamIndex, date);
}
```

三条要点：

1. **覆盖只走 `shiftOn`，`teamShift` 保持纯轮转。** 日历底栏的「其他班组」chips 走的是 `teamShift(i, date)`（[calendar_screen.dart:1396](app/lib/features/calendar/calendar_screen.dart:1396)），所以别人的班不会被我改掉 —— 我要的正是这个。
2. **下标越界 / 查不到就回退到轮转**，不抛异常。这是给历史脏数据与「班次被删但覆盖行还没清干净」留的兜底。
3. **空白表（`cycle.isEmpty`）`shiftOn` 仍返回 null**，覆盖逻辑不改变这一点（且空白表下压根不会产生覆盖行，见 §7）。

### 5.1 为什么值得放进领域对象，而不是在调用点各算各的

`shiftOn` 的调用点正好四处，`teamShift` 一处：

| 调用点 | 用途 |
|---|---|
| [calendar_screen.dart:754](app/lib/features/calendar/calendar_screen.dart:754) | 日历格子里的班次胶囊 |
| [calendar_screen.dart:1105](app/lib/features/calendar/calendar_screen.dart:1105) | 底栏信息卡 |
| [alarm_screen.dart:84](app/lib/features/alarm/alarm_screen.dart:84) | 闹钟页「未来 30 天」列表 |
| [schedule_editor_screen.dart:341](app/lib/features/calendar/schedule_editor_screen.dart:341) | 编辑器 14 天预览 |
| [calendar_screen.dart:1396](app/lib/features/calendar/calendar_screen.dart:1396) | 其他班组 chips（`teamShift`，**不受影响**） |

放进领域对象的话，这四处**一行都不用改**，口径也只有一份。若改成「各调用点自己查覆盖表」，就有四份需要同步的口径，漏一处不会报错、只会静默显示错的班次。

另外，日历要画「这天被调整过」的小圆点（§7），有了 `dayOverrides` 直接 `containsKey` 就行，不必再来一次查库。

### 5.2 ⚠️ 一个必须一起修的坑：`watchActiveSchedule()` 不会因覆盖变化而重发

`watchActiveSchedule()` 目前只监听 `shiftScheduleRows` 那一行，子表（班次 / 周期 / 覆盖）在 `asyncMap` 里读一次：

```dart
return schedQuery.watchSingleOrNull().asyncMap((sched) async {
  if (sched == null) return null;
  return _loadChildren(sched);
});
```

**后果**：用户改完覆盖、落库成功，`activeScheduleProvider` 不会推新值，**日历上不会变** —— 要等下一次因为别的原因重建才会显示出来。这是个静默失效，从界面上看不出原因。

**要求**：`watchActiveSchedule()` 必须改成「覆盖表变了也重新装配一次」。

**做法**：把覆盖表并进 `watchActiveSchedule()` 的触发源 —— 两张表任一变化就重新跑一次 `_loadChildren`，保持「领域对象持有全部答案」的架构。

（另一条路是照 `shiftAlarmOverridesProvider`（[app_repository.dart:478](app/lib/data/app_repository.dart:478)）的先例，把覆盖单开一个 provider、由界面层做查表。**不走这条**：它会退化成四份需要同步的口径，正好抵消掉 §5.1 的全部好处。只有在实施时发现合并流的写法确实别扭，才回头考虑它。）

---

## 6. 闹钟：自动跟随，无需额外改动

`AlarmService.reschedule` 里遍历未来 60 天用的就是 `schedule.shiftOn(date)`（[alarm_service.dart:656](app/lib/features/alarm/alarm_service.dart:656)），`shiftOn` 一旦覆盖感知，闹钟**自动**接上：

- 覆盖成休班 → `t.isRest` → 跳过，那天不响
- 覆盖成另一个工作班次 → 按**那个班次自己的** `alarmMinute` 排

与「按天关闹钟」（`ShiftAlarmOverrides`）**正交**，两条规则各管各的：那天被单独关过闹钟的，改完班之后**仍然关着**。

**重排触发点**：改完覆盖后调 `AlarmService.rescheduleAll(repo)`，与现有其它改动的做法一致。

---

## 7. 日历交互

### 7.1 两个入口

**入口一 · 点信息卡**：底栏信息卡上那行班次（日期 + 班次 + 时间那一行）变成可点，右端加一个小图标提示可点。点开范围 = 当前选中的那一天。紧凑版信息卡（短屏 / 小窗）那行同样可点。

**入口二 · 长按拖选**：长按某天不放，再拖动圈一段连着日期（可跨周，**不跨月**）。松手弹同一个选择层。

**与现有手势不冲突**：日历上现有的拖动是「单格滑块」（拖动时松手吸附到最近的格，[calendar_screen.dart:642-677](app/lib/features/calendar/calendar_screen.dart:642)）。长按与它不打架 —— Flutter 手势竞技场里按住不动约 500ms 长按才赢，立刻滑动还是原来的 Pan 赢，两者起手动作本来就不同。

### 7.2 选择层

一个玻璃底部弹层（照 `showGlassOptionPicker` 那一族的配方，`GlassPanel(solid: true)`）：

- 顶部一行：「9月18日 – 9月20日 · 3 天」（单日时只写「9月18日」）
- 中间列出本方案**全部班次定义**：色点 + 名称 + 时间范围。当前值打勾
- 底部一条「**恢复轮转**」，**仅当范围内至少有一天被覆盖过时**才出现。点了就删掉这几天的覆盖行

选完 → 落库 → `AlarmService.rescheduleAll` 重排 → `showGlassSnack` 提示「已把 3 天改为 大休」。

### 7.3 空白表方案下入口不出现

空白表方案（`isBlank`）下：信息卡那行**不可点**、长按**不进入范围态**。这是决策 ③ 的落点。

### 7.4 被覆盖那天的视觉标记

被覆盖那天的班次胶囊**右上角加一个小圆点**。

- 小圆点**固定在 3–4dp、不跟格子高度缩放** —— 格子里的字是按格子高度等比缩放的（`AppTokens.scaled`），小窗里缩到 1–2px 就等于没有。
- 颜色用班次色或主色。
- **这是本轮自觉最容易改的一处**：嫌吵可以换成虚线描边、格子角落的小三角形等，改起来是局部的事。

信息卡上同时给一句文字说明（「· 已调整」），用户第一次看见圆点时能对上号。

---

## 8. 编辑器

- 班次带 id 走（§4.3），保存改增量。
- **14 天预览不带覆盖。** 编辑器预览在 [schedule_editor_screen.dart:296](app/lib/features/calendar/schedule_editor_screen.dart:296) 自建一个 `ShiftSchedule`，不传 `dayOverrides` 即可 —— 这条是**白送的，不用写代码**。

  **为什么有意不带**：预览要回答的是「按这套规则未来 14 天是什么班」。带上覆盖之后，用户改周期就看不出规则的变化了 —— 预览会失去它存在的意义。
- **代价与补偿**：这样它跟日历上看到的不一致。所以方案存在覆盖时，编辑器顶部给一行轻提示：「本方案有 N 天单独调整，预览只显示轮转规则」。这行只为了防止「我改了那天，怎么预览没变」的困惑，成本是一条 `Text`。

---

## 9. 文案（`lib/core/l10n.dart`）

新增条目（zh / en 成对，沿用 `L10n.t(zh, en)`）：

| 用途 | 中文 |
|---|---|
| 选择层里的「恢复轮转」 | 恢复轮转 |
| 信息卡上的调整标记 | 已调整 |
| 应用后的提示 | 已把 N 天改为 X |
| 编辑器顶部提示 | 本方案有 N 天单独调整，预览只显示轮转规则 |
| 范围标题（多天） | M月D日 – M月D日 · N 天 |

单日不写「1 天」，只写日期，与信息卡现有写法一致（`L10n.monthDayWeekday`）。

---

## 10. 明确不做

- **空白表方案下的按天改班**（决策 ③）
- **跨月拖选**（要翻页才能圈，手势语义会变得很怪）
- **一次改到「从此往后」** —— 只能圈具体日期，不做「从这天起一直……」这种开放式范围
- **同一天对不同班组分别覆盖** —— 覆盖只属于「我们班组」
- **临时自定义一个只用于那天的班次**（决策 ① 排除掉的）
- **云同步 / 导入导出**，以及 `PRODUCT_SPEC.md` §2 里其余仍成立的条目

---

## 11. 测试

现有 170 条**只增不减**。

| 层 | 用例 |
|---|---|
| `shift_rotation_test.dart`（纯 Dart） | 覆盖命中（那天返回覆盖的班次）· 下标越界回退到轮转 · `dayOverrides` 为空时行为与从前完全一致 · **`teamShift` 不受覆盖影响**（其他班组仍是纯轮转）· 空白表忽略覆盖 |
| `migration_v7_to_v8_test.dart`（新建） | v7 库里升上来新表建得出来、原有数据一条不丢 |
| 仓库层 | `saveSchedule` 增量保存后：改方案名 → 班次 id **不变**；改班次时间 → id 不变；新增班次 → 只有新行拿到新 id；删班次 → 引用它的覆盖**连带被清掉**；`deleteSchedule` / `clearAll` → 覆盖被清掉 |
| 界面层 | 日历上被覆盖那天的标记出现 · 长按拖选圈出正确范围 · 选择层应用后日历与信息卡同步变 · 「恢复轮转」把范围清干净 · 空白表方案下入口不出现 |
| 闹钟 | 覆盖成休班那天不排闹钟 · 覆盖成另一个工作班次按新班次的 `alarmMinute` 排 · 与「按天关闹钟」正交（关着的仍关着） |

**怎么验证「班次 id 稳定」这条真的生效**：改一次方案名（不碰班次），断言 `shift_class_rows` 里那几行的 `id` 与保存前逐条相同。这条如果不写，删光重建那个实现改没改对是看不出来的。

---

## 12. 收尾（照 `AGENTS.md` 的正式版清单）

- `PRODUCT_SPEC.md`：§2「明确不做」里划掉「日历上直接改某一天（换班/请假覆盖）」；§2 排班日历与联动班次闹钟两节补上新能力；§4 数据模型表加一行、`schemaVersion` 改成 8；抬头版本号跟着走。
- `README.md`：功能清单补一条。
- `AGENTS.md`：Drift 表清单加 `ShiftDayOverrides`、`schemaVersion = 7` 改成 8、版本史加一条。
- 更新日志（`features/profile/app_dialogs.dart`）按现有规则：测试版条目原样、正式版条目归纳。

---

## 13. 风险与坑（实施时挨个对照）

1. **`watchActiveSchedule()` 不响应覆盖表**（§5.2）—— 最容易漏，且漏了不报错，只是日历不动。**先修这个再写界面**，否则会误以为是自己界面写错了。
2. **`saveSchedule` 的删除是无条件的**（§4.1）—— 改增量时别只改「插入」那头，删除那头也要跟着改成「只删不在新列表里的」。
3. **`ShiftClass` 加 `id` 进 `==` 之后**，任何拿 `ShiftClass` 做相等比对的既有测试都可能需要跟着更新。跑一遍全量测试确认，别只跑新的。
4. **改 Drift 表后必须重生成**：`dart run build_runner build --delete-conflicting-outputs`。
5. **不要跑 `dart format`** —— 工具链是新版 tall style 格式化器，一跑就重排整个文件、制造几百行无关 diff。只跑 `flutter analyze`。
6. **构建环境变量**：bash 里构建必须 `export ANDROID_HOME/JAVA_HOME/GRADLE_USER_HOME` 指向 `toolchain/`，否则 Gradle 会去 `~/.gradle` 下载到超时。
7. **小圆点别跟着格子缩放**（§7.4）—— 小窗里会缩没。
