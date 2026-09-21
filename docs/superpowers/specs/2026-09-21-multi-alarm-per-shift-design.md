# 每个班次自定义 N 个闹钟 · 设计规格

- 日期：2026-09-21
- 目标版本：**待定** —— 本轮是「新功能 + schema 变更」，够不够到 `X.Y` 由用户决定；AI 只改末位 `Z` 与 `build`
- 状态：待评审
- 来源：用户反馈（原话：「已收到反馈，每个班次可以自定义 N 个闹钟。」场景：**白班除了早上要早起，午休也要起** —— 现在一个班次只有一个闹钟）
- 前置：`docs/superpowers/specs/2026-09-18-per-day-shift-override-design.md`（班次 id 稳定、按天覆盖表 —— 本轮要接着用那两条）
- 相邻但**不属于本文**的一件：待办弹窗「快速连点添加 → 整屏纯黑」的修复（bounded，已按两层护栏落地：`GlassActionButton` 上锁 + `dialogCloser`）。与本轮的闹钟模型无关，只是同一轮反馈进来的

---

## 1. 背景与目标

现状是**一个班次一个闹钟**：`ShiftClassRows` 上的 `alarmEnabled`（开关）+ `alarmMinute`（钟点），
用户可编辑的只有这一对。六个消费方都按「一个钟点」写死了：班次编辑器、闹钟页列表、
日历信息卡的 `_alarmText`、排定逻辑 `planShiftAlarms`、模板 JSON、内置模板与种子库。

用户要的是**一个班次挂任意个闹钟**，典型场景就是白班：起床一个、午休一个。

**目标**：每个班次 0..6 个闹钟，每个闹钟可带一个可选名字（「起床」「午休」）；
响铃、闹钟页、信息卡、模板、「我的模板」都跟着走；「按天关闹钟」仍然一处关掉当天全部。

**非目标**：见 §9。

---

## 2. 四个已定决策（来自 2026-09-21 的头脑风暴，用户逐个拍板）

| # | 决策 | 理由 |
|---|---|---|
| ① | 每个班次**最多 6 个** | 不是产品口味，是**原生 id 空间的硬上限**（见 §6）：`序号 × 60 + 天数偏移` 必须落在 0..400 里 |
| ② | 每个闹钟**可带名字**（可空） | 响铃界面从笼统的「白班提醒」变成「白班 · 午休」；不填就还是「白班提醒」 |
| ③ | 「前一天 / 当天」**自动推断**，不加开关 | 规则本轮**要补好**（见 §4）—— 现行规则会把午休闹钟算到前一天中午 |
| ④ | 总开关**关掉不清空闹钟** | 保留现在的语义（`alarmEnabled` 只是「这组闹钟要不要响」），手滑关一下不会丢配置 |

---

## 3. 数据模型

### 3.1 新表 `ShiftClassAlarms`

```
ShiftClassAlarms
  classId   int    ┐ 复合主键 {classId, order}
  order     int    ┘
  minute    int      钟面值（0..1439，分钟自午夜）
  label     text null 可选名字（「起床」「午休」）
```

- **不设自增 id**：没有任何东西引用单个闹钟（「按天关闹钟」是按天、不是按闹钟；
  模板不存 id）。所以它和 `ShiftDayOverrides` 不是一类东西 —— 那边要稳定 id
  是因为覆盖要指得住班次定义，这边没有这层需求。**别为了对称给它加 id。**
- **没有 per-alarm 的 enabled**：总开关留在班次上（决策 ④），删掉一个闹钟 = 删掉这一行。
- `order` 是**用户在编辑页里的顺序**，同时也是原生 id 里的「序号」（见 §6）。

### 3.2 `ShiftClassRows.alarmEnabled` 留下，`alarmMinute` 删掉

- `alarmEnabled` 继续当**总开关**（决策 ④），语义不变。
- `alarmMinute` 迁进新表后**从表里删掉**，不留死列 —— 留一列没人读的旧值，
  下一个人就会从两个来源里挑错那个（这正是 v0.7.1 待办弹窗踩过的坑）。
- ⚠️ **历史迁移那段代码要一起改**：`app_database.dart` 的 `_migrateRowsToTwoTier`
  （v5→v6）是按列名显式 `INSERT INTO shift_class_rows (… alarm_enabled, alarm_minute)`
  的 —— 表里没这列之后，**任何从 v5 或更早升上来的用户都会直接迁移失败**。
  改法：先插班次行，再把 `alarm_minute` 插进新表（`order = 0`）。
  护栏是既有的 `test/migration_v5_to_v6_test.dart` —— 它必须仍然过。
- 改完跑 `dart run build_runner build --delete-conflicting-outputs` 重新生成。

### 3.3 值类型

```dart
class ShiftAlarm {
  const ShiftAlarm({required this.minute, this.label});
  final int minute;      // 钟面值
  final String? label;   // 可空
  // == / hashCode 全字段
}
```

`ShiftClass` 上：`alarmMinute`（单值）→ **`List<ShiftAlarm> alarms`**（有序）。
`copyWith` 要能表达「清空列表」（沿用既有的 `clear*` 通道写法，
`copyWith` 的 `xx ?? this.xx` 没有清空通道 —— 见 AGENTS.md 里那条教训）。

---

## 4. 「前一天 / 当天」的规则（本轮唯一的**行为变更**）

### 4.1 现行规则与它为什么在多闹钟下会错

```dart
bool get alarmPreviousDay => alarmMinute > startMinute;   // 现行
```

它写的是「**不晚于上班时刻的最近一次该钟点**」—— 那是给「起床闹钟」量身定的：
起床钟点必然早于上班，所以「晚于上班钟点」的钟点只可能是前一天晚上那个。

多闹钟一来，前提就破了：**白班 08:00 上班、午休 12:30 起床** —— 12:30 晚于 08:00，
按现行规则会被排到**前一天的中午 12:30**。用户提的正是这个例子。

### 4.2 新规则

> 钟点落在**值班窗口内**（`[start, end)`，按班次相对时刻算，跨午夜与 24 小时班都成立）
> → **当天**；
> 否则钟点**晚于上班钟点** → **前一天**；
> 否则 → **当天**。

- 白班 08:00–20:00：起床 06:30 → 当天 ✓（窗外、早于上班）；午休 12:30 → 当天 ✓（窗内）
- 夜班 20:00–08:00（次日）：19:00 → 当天 ✓（窗外、早于上班）；02:00 → 当天 ✓（窗内）
- 00:00 上班的夜班 + 23:00 → 前一天 ✓（窗外、晚于上班 —— 与 v0.8.9 修好的那条一致）
- 上班时间没填 → 判不了，**按当天**（沿用「不瞎挪一天」的口径）

### 4.3 与现行行为的差异面（必须写清，免得被当成回归）

只有一档不同：**闹钟钟点落在值班窗口内**的那些。那一档的旧行为（排到前一天）
几乎必然是错的 —— 它把「班中间的闹钟」搬到了 24 小时前。其余全部逐条相同，
包括边界：**钟点正好等于下班时刻**（`end` 取**开区间**）仍按旧行为落「前一天」，
这条是**刻意的**（保住旧语义，本轮不顺手改），写进注释与测试。

---

## 5. 领域层

- `bool alarmFallsOnPreviousDay(ShiftClass shift, int alarmMinute)`：上表的纯函数实现。
- `DateTime shiftAlarmFireAt(DateTime date, ShiftClass shift, ShiftAlarm alarm)`：
  多一个 alarm 参数，日期重建方式**不动**（`DateTime(y, m, d - 1)` 而不是减 24 小时，
  夏令时的教训）。
- `ShiftAlarmPlan` 增加 `alarmIndex`（原生 id 要用），`fireAt` 与 `offset` 的口径不变：
  **`offset` 仍按班次那一天算**，id 仍不跟着前移的触发时刻走。
- `planShiftAlarms`：跳过条件逐条保持（没班次 / 休班 / 没开总开关 / 该天被按天关掉 /
  触发时刻不晚于 `from`），只是**每个闹钟各出一条 plan**。
- 响铃标题（`scheduleNativeAlarm` 的 label）：
  - `label` 为空 → `白班提醒`（与现在逐字一致，别拼成「白班提醒提醒」）
  - `label` 非空 → `白班 · 午休`
  - 两处都在 `l10n.dart` 出（双语），不写死中文。

---

## 6. 原生 id 空间（硬约束，先算清楚再写代码）

现状：班次闹钟 id = `_shiftBaseId(0) + 天数偏移`，`reschedule` 排未来 **60** 天 →
今天占 0..59；Kotlin 侧 `cancelAllNativeAlarms` 扫 `0..400`。

多闹钟之后：

```
id = 序号 × 60 + 天数偏移        序号 ∈ 0..5 → id ∈ 0..359 ≤ 400 ✓
```

- **上限 6 就是这么来的**，不是随手定的。要更多，得同时改 Kotlin 的 `0..400`
  扫描范围与 `AlarmScheduler` 那句「排班闹钟 0..59」的注释 —— 本轮不做。
- `60` 这个数字**就是 `reschedule(days:)` 的缺省值**：两者必须一起改，
  所以代码里抽一个常量（`_shiftDaysHorizon`）给两处用，别再各写一个 60。
- `planShiftAlarms` 头上那句「映射必须保持不变，否则每次重排都会把闹钟换个号」
  **需要改写**：现在 id 还跟「闹钟在列表里的序号」有关 —— 用户在编辑页里调整顺序
  会重新编号。这是可接受的（编辑之后必然重排、`cancelAll` 先跑），但**重排本身
  绝不能改序号**，否则每次打开 App 都会换一批号。这句话要写进注释。
- Kotlin 侧只改注释；`MainActivity` 的两处 `for (id in 0..400)` **不动**
  （requestCode 占用清单见 AGENTS.md，班次段是 0..400）。

---

## 7. 迁移（schemaVersion 9 → 10）

顺序（都在 `if (from < 10)` 一个分支里，`_migrateRowsToTwoTier` 之后的新代码）：

1. `createTable(shiftClassAlarms)`。
2. 老数据搬过去：
   `INSERT INTO shift_class_alarms (class_id, "order", minute, label)
    SELECT id, 0, alarm_minute, NULL FROM shift_class_rows WHERE alarm_minute IS NOT NULL`
   —— 条件只看 `alarm_minute`，**不要求 `alarm_enabled = 1`**：开关关着但时间还留着的行
   同样把时间搬过去（决策 ④ 的语义：关开关不清空时间）。搬完老用户看到的是
   「一组闹钟、开关关着」，配置没丢。
3. `m.alterTable(TableMigration(shiftClassRows))` 删掉 `alarm_minute` 列。
   ⚠️ 这会**重建表**：`id` 必须原样带过去 —— `shift_cycle_rows.class_id` 与
   `shift_day_overrides.class_id` 都指着它，id 一变，周期与按天覆盖集体指飞
   （不报错、只是那天变成别的班）。迁移测试里要断言这两处仍指得对。
4. 逐条改 §3.2 提到的 `_migrateRowsToTwoTier`。

模板 JSON（`domain/schedule_template.dart`）：

- 编码：班次对象里新增 `"alarms": [{"minute": 390, "label": "起床"}, …]`；
  **不再写** `alarmEnabled` / `alarmMinute`（写两份就是两个来源）。
- 解码：有 `alarms` 用 `alarms`；**没有则回退**读旧的 `alarmEnabled` + `alarmMinute`
  → 一个闹钟（`label` 空）。老模板（用户已经存下来的「我的模板」）必须照常能用。
- 内置模板（`shift_templates.dart` 的 20 个）、默认库（`shift_rotation.dart`）、
  种子（`seed.dart`）里的闹钟改成 `alarms: [ShiftAlarm(...)]`，**内容一个都不改**
  （每个仍是 1 个闹钟、同一个钟点）。

---

## 8. 六处消费方逐个交代

| # | 位置 | 现在 | 改成 |
|---|---|---|---|
| 1 | `schedule_editor_screen.dart` `_classRow` | 开关 + 一个时间块 + 「前一天」小字 | 开关 + **闹钟行列表** + 「添加闹钟」；每行 = 时间块 + 名称输入（可空）+ 紧凑删除钮。行数到 6 时**隐藏**「添加闹钟」并给一行小字说明上限（**不造"禁用态"这种新视觉状态** —— 设计语言里没有它）。切成休班时照旧整组清掉 |
| 2 | `alarm_screen.dart` 「未来 30 天」 | 一天一条、一个钟点 | 过滤条件由 `alarmMinute != null` 换成 `alarms.isNotEmpty`；一条里列出当天全部闹钟（含「前一天」标记与名字），`_ShiftAlarmEntry` 带上当天的闹钟列表 |
| 3 | `calendar_screen.dart` `_alarmText` | 「闹钟 06:30」 | 一行内给**第一个 + 「等 N 个」**（`闹钟 06:30 等 2 个`）。那一行本来就是 `maxLines: 1` + 省略号，**高度不会变**，所以 `info_card_metrics.dart` 不用动 —— 这是刻意选的形态，不是省事 |
| 4 | `alarm_service.dart` | 一天一条 plan | §5：每个闹钟一条，id 与 label 按 §6 / §5 |
| 5 | `schedule_template.dart` | 单值编解码 | §7 |
| 6 | 内置模板 / 默认库 / 种子 | 单值 | §7 末条 |

**桌面小组件不受影响**：快照里没有闹钟字段（`widget_snapshot.dart` 的协议里没有它）。
这条要顺手核一遍，别让「六个消费方」变成七个。

---

## 9. 明确不做

- **不加「次日」（下班之后的闹钟）**：现在这套模型只有「当天 / 前一天」两档
  （它本来是给「上班前起床」设计的）。下班后的闹钟要的是「第三天」，
  加第三档得先有真实需求 —— 用户这次提的两个场景（早起、午休）都在两档之内。
  这一条是**刻意的**，不是漏的。
- **不做每个闹钟单独开关**（决策 ④：总开关管一组，删掉才是不响）。
- **不做每个闹钟单独铃声 / 单独提前提醒档位**。
- **不做 per-alarm 的按天覆盖**：`ShiftAlarmOverrides` 仍是「那天这个班次全不响」。
- 不动 `CustomAlarms`（自定义闹钟是另一条线，与班次无关）。

---

## 10. 文案（`lib/core/l10n.dart`，中英都要）

新增：`addAlarm`（添加闹钟）· `alarmNameOptional`（名称（可选））·
`alarmNameHint`（如「起床」「午休」）· `alarmLimitReached`（每个班次最多 6 个）·
信息卡的「等 N 个」· 响铃标题的拼接（`班次名 · 闹钟名`）。
既有的 `alarmTime` / `alarmPrevDayHint` / `clockPrevDay` 全部继续用。

---

## 11. 测试

| 文件 | 加什么 |
|---|---|
| `shift_rotation_test.dart` | 新规则的每一条边界：窗内 / 窗外早于上班 / 窗外晚于上班 / **正好等于上班** / **正好等于下班** / 跨午夜班 / 24 小时班 / 上班时间没填 |
| `shift_alarm_decision_test.dart` | 一个班次两个闹钟 → 两条 plan；`alarmIndex` 与 id 的对应；按天关掉 → 当天一个都不排；起床与午休**都落在班次当天** |
| `migration_v9_to_v10_test.dart`（新） | 老库（有 `alarm_minute`、含「开关关着但有时间」的行）迁完 → 新表一行、开关不变、**按天覆盖与周期仍指向原 classId**、`alarm_minute` 列不存在 |
| `migration_v5_to_v6_test.dart`（既有） | 必须仍然过 —— 它是 §3.2 那个坑的护栏 |
| `schedule_template_test.dart` | 新编码往返；**老 JSON（只有 alarmEnabled/alarmMinute）回退成一个闹钟** |
| `schedule_editor_test.dart` | 加 / 删闹钟；6 个时不再出现「添加闹钟」 |
| `calendar_screen_test.dart` | 一个班次 3 个闹钟时，信息卡高度与 1 个闹钟时**一模一样**（既有那条「点开每一天高度不变」的用例等价扩展） |

---

## 12. 风险与坑（实施时挨个对照）

1. **id 空间**：`序号 × 60 + 偏移`，`60` 与 `reschedule(days:)` 必须同源；
   序号别在重排时变。
2. **v5→v6 历史迁移**：删列之后那段代码会直接炸（§3.2）。
3. **`alterTable` 重建表**：`classId` 引用（周期 + 按天覆盖）必须原样活下来。
4. **模板老 JSON**：用户已经存下的「我的模板」必须照常打开（§7）。
5. **响铃标题**：`label` 为空时不能拼成「白班提醒提醒」。
6. **切休班**：照旧整组清掉（现在的 `clearAlarmMinute` 路径改成清列表）。
7. **按天关闹钟**：一处关掉当天这个班次的**全部**闹钟，别退化成 per-alarm。
8. **视觉工装**：编辑器的闹钟列表要进屏单 —— 1 个 / 多个 / 6 个（上限态）三种，
   深浅色各一遍（AGENTS.md 的规矩：新界面一律进屏单，令牌守门看不出「裸文字 vs 胶囊」）。
9. **别把 `alarms` 塞进 `copyWith` 的 `xx ?? this.xx`**：清空需要一条显式通道。

---

## 13. 收尾（照 AGENTS.md）

1. `dart run build_runner build --delete-conflicting-outputs`（改了表）。
2. `flutter analyze` 0 error / 0 warning；`flutter test` 全绿（只增不减）。
3. 版本号：`pubspec.yaml` 与 `app_info.dart` 同步（`X.Y` 由用户定，AI 只动末位 `Z` 与 `build`）。
4. 更新日志（`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn`，prepend + 保 10 条）。
5. `AGENTS.md`：schemaVersion 9 → 10、Drift 表清单加一张、版本历史；
   §6 的 id 算式与「上限 6 的由来」值得留一条坑。
6. **真机验收**（必须，不是可选）：装 release 包 → 老库迁移后班次编辑页能看到原来那个闹钟 →
   给白班加第二个闹钟（午休）→ 闹钟页与信息卡显示正确 → **到点两个都响**、
   响铃标题带名字 → 「按天关闹钟」那天两个都不响。
7. 视觉工装出图看图（§12.8）。
