# 统计页 + 请假/加班（设计）

- 日期：2026-11-16
- 起因：用户要求新增统计页，取代日历右上角「排班时段」按钮；按月 / 按年浏览；统计上班总工时、平均工时、休息天数、请假时长（区别于大休）、加班时长。
- 影响版本：v0.13.14 测试版（`X.Y` 由用户定，AI 只动 `Z` 与 `build`）

## 1. 目标 / 非目标 / 反目标

**目标**

- 日历顶栏那颗 `Icons.timeline` 换成统计入口，点开是独立页 `StatsScreen`。
- 统计页支持**按月 / 按年**浏览，可在期间之间前后翻，可一键回到本月 / 今年。
- 指标：实际在岗工时（正常 + 加班）、正常工时、平均每班工时、上班天数、休息天数、
  请假时长、加班时长、法定节假日上班天数、夜班天数、最长连班、最长连休、班次分布。
- 给「按天改班」加**请假 / 加班**两种日级记录：时长可自定义，整天请假默认等于当天
  班次时长；整天请假自动不排这天的班次闹钟。
- 日历格子与信息卡能看见「假 / 加」标记。

**非目标**

- 不做收入估算、个税、时薪。
- 不做导出 / 分享长图、趋势图、去年同月对比。
- 不按班次统计工时（班次分布只记天数，与信息卡「本月统计」同口径）。
- 不新增底部导航 tab，不改底栏结构。

**反目标**

- 为空白表（跟随法定节假日）合成「上班 / 休息」——v0.9.15 的教训。
- 把「未排班」「空白表」「休息」混成一个数。
- 用班次名字猜夜班 / 请假 / 加班。
- 请假只影响统计、却让闹钟照响。

## 2. 入口与页面

- 入口：`features/calendar/calendar_screen.dart` 的 `_header` 两条版式（单行 / 两行）都把
  `Icons.timeline` 换成 `Icons.insights_outlined`，`onTap` 从 `_showTimeline` 改为
  `Navigator.push(StatsScreen())`。
- 「排班时段」总览仍可从 `我的 → 排班管理 → 排班时段` 进入；统计页头部的
  「使用中：<方案名> ›」再给一个入口，避免可发现性下降。
- 页面骨架：`Scaffold` + `AppBar`（标题「统计」）+ `CenteredContent` + `ListView`，
  与排班管理页同一套。

版式（数字为示意）：

```
统计
 [ 月 ] [ 年 ]                      ← GlassSegment
 ‹   2026年11月   ›        [本月]   ← 年月可点，复用 showGlassMonthPicker
 182小时30分                          ← AppTokens.bigNumber
 实际在岗 · 四班两倒 ›
 正常 180小时 · 加班 2小时30分 · 请假 8小时
 [上班 18天] [休息 12天] [请假 1天] [加班 2小时30分]
 班次分布
 ● 白班      7天
 ● 上夜班    8天
 ● 大休      15天
 其他：法定节假日上班 2天 · 夜班 8天
       最长连班 4天 · 最长连休 6天
 未排班 0天 · 无班次 0天              ← 只在有值时出现
```

年视图：同一张总览卡（全年合计）+ 12 行「1月 · 180小时 · 上班18 · 休息13」，
点某一行切到那个月的月视图。

## 3. 统计口径

| 指标 | 口径 |
|---|---|
| 班次时长 | `endMinute - startMinute`，兼容三种真实形态：累计值（>1440）、回绕值（<startMinute）、正好 1440 |
| 上班总工时 / 实际在岗 | 正常工时 + 加班工时 |
| 正常工时 | Σ 每个出勤班次的（时长 − 当天请假），下限 0；整天请假不计入 |
| 平均工时 | 正常工时 ÷ 出勤天数（平均每班），一位小数 |
| 上班天数 | 非休班、且请假没有占满整班的天数 |
| 休息天数 | `isRest` 班次的天数（含「下夜班」这类标成休的） |
| 请假时长 | 日级记录的分钟数相加；请假天数只数「整天请假」 |
| 加班时长 | 日级记录的分钟数相加，叠加在当天工时上，不改变出勤 / 休息天数 |
| 法定节假日上班 | 出勤日里 `holidayNameOf(date) != null` 的天数（与日历标红同源） |
| 夜班天数 | 出勤日里班次 `isNight == true` 的天数 |
| 最长连班 / 连休 | 期内连续出勤 / 连续休息的最长天数；未排班、空白表、整天请假都断开 |
| 跨月夜班 | 归**上班开始那天** |
| 班次未设时间 | 算出勤天数、工时记 0，并提示「N 天班次未设时间」 |
| 空白表 | 不合成上班 / 休息；记入「无班次」；请假 / 加班照常统计 |
| `scheduleOn == null` | 记入「未排班」，不算休息 |

## 4. 数据模型

### 4.1 日级请假 / 加班

新表 `ShiftDayExtras`（schema v16）：

```dart
class ShiftDayExtras extends Table {
  IntColumn get day => integer()();      // dayNumber 口径
  IntColumn get kind => integer()();     // 0 = 请假, 1 = 加班
  IntColumn get minutes => integer()();
  @override
  Set<Column> get primaryKey => {day, kind};
}
```

- **全局、不挂 scheduleId**：请假是「那天我不在」，换班表也成立。与
  `ShiftAlarmOverrides` 同一个理由。
- 一天最多一条请假 + 一条加班；`minutes <= 0` 视为清除。
- 领域值类型 `DayExtra { leaveMinutes, overtimeMinutes }`，provider 暴露
  `Map<int, DayExtra>`（key = `dayNumber`）。

### 4.2 夜班标记

`ShiftClass` 增加 `bool isNight`，`shift_class_rows` 增加 `is_night`（默认 0）。

- 编辑器在「工作 / 休息」分段器下、联动闹钟之上加一行「夜班」开关（仅非休班显示）。
- 内置模板按 `ShiftRole.night` 自动置 true；`defaultSchedule()` 的「上夜班」置 true。
- 模板 JSON 增加 `isNight`，旧模板缺字段按 false。
- 老库升级后全部为 false，用户可在编辑器里补标；统计页在「夜班 0 天」时不额外提示。

## 5. 录入与交互

「调整班次」弹层在班次列表下、分隔线之后加两行动作：

- 请假（`Icons.event_busy_outlined`）
- 加班（`Icons.more_time_outlined`）

选中后弹第二个玻璃弹层 `showDayExtraSheet`：

- 标题「请假」/「加班」，副标题为日期区间。
- 快捷档：1小时 / 2小时 / 4小时 / 8小时；请假额外有「整天」「半天」。
- 精细档：`−` / `+` 每 30 分钟一档，范围 0.5–24 小时；**不用 TextField**
  （避免 `viewInsets` 那套坑）。
- 「整天」按**每天各自的班次时长**写库；区间里各天时长不同也各自算。
- 已有记录时预选中，并提供 `danger` 风格的「清除」。
- 确认后闭包返回分钟数（区间时是「每天多少分钟」；整天用哨兵 `0` 表示按天算）。

写入 `ShiftDayExtras` 后：

- `Haptics.commit()`。
- `AlarmService.replanAfterScheduleChange(repo)`：整天请假要让这天的班次闹钟不再排。
- 提示条「已记录 11月12日 请假 8小时」。

闹钟侧：`planShiftAlarms` 增加 `Map<int,int> leaveMinutes`，当
`leaveMinutes[day] >= 班次时长` 时跳过该天。**不做「同时关闹钟」复选框** ——
整天请假自动不响、部分请假照常响，语义更直白。

> 这条比原提案的「写 ShiftAlarmOverrides」更靠内：请假是「那天不在岗」的事实，
> 让调度器直接读它，避免两个开关打架（用户请假后又在闹钟页把那天的开关打开）。

## 6. 标记

- 日历格子：农历行前缀加「假 」或「加 」（请假优先），主色 + 加粗，与调休「班 」同一位置、
  同一手法；两者同时存在时写成「班 假 」。
- 信息卡完整版：班次富文本末尾追加「   请假 4小时」「   加班 2小时」，与班次名 / 时间 /
  闹钟同属一段 `Text.rich`，**不改变定高**。
- 信息卡紧凑版（短屏 / 小窗）：时间行下面加一行 `microText`「请假 4小时 · 加班 2小时」。
- 「调整班次」弹层里，选中那天的记录在动作行下方以次要文字显示。

## 7. 空状态

- 没有任何班表：总览数字全部为 0，主卡下面一行「这段时间还没有排班」。
- 空白表：工时 / 休息 / 上班三天数与「无班次」天数并列，主卡加一句
  「这套班表没有班次（跟随法定节假日）」；请假 / 加班照常显示。
- 只有请假 / 加班、没有排班：照常显示这两项，其余为 0。

## 8. 测试与验收

- `shift_stats_test`：三种 `endMinute` 形态、跨月夜班、整天 / 半天请假、休息日加班、
  空白表、未排班、缺时间、节假日上班、夜班、最长连班 / 连休、平均工时的除零。
- `shift_day_extras_test`：写入 / 覆盖 / 清除、`clearAll` 连带清空、provider 重发。
- `migration_v15_to_v16_test`：旧库加 `is_night` 默认 0、新表建出来、旧数据原样。
- `stats_screen_test`：月 / 年切换、前后翻、空状态、指标渲染、点年视图某行切到该月。
- `day_extra_sheet_test`：整天 / 半天 / 自定义 / 清除的回传值；窄窗不溢出。
- `shift_override_picker_test`：新增两行动作可点、返回正确的 intent。
- `alarm_service` 相关用例：整天请假不排、部分请假照排。
- 视觉工装屏单：`stats_month`、`stats_year`、`stats_blank`、`day_extra_sheet`。
- 验收：`flutter analyze` 0 error / 0 warning；`flutter test` 全绿；视觉出图逐张核对。

## 9. 文件落点

- 域层：`app/lib/domain/day_extra.dart`、`app/lib/domain/shift_stats.dart`。
- 数据：`app/lib/data/app_database.dart`（表 + v16 迁移）、`app_repository.dart`（读写 + provider）。
- 页面：`app/lib/features/stats/stats_screen.dart`、`stats_widgets.dart`。
- 录入：`app/lib/features/calendar/day_extra_sheet.dart`；
  `shift_override_picker.dart` 加动作行；`calendar_screen.dart` 接写入与标记。
- 班次：`shift_rotation.dart`、`schedule_template.dart`、`schedule_editor_screen.dart`、`shift_templates.dart`。
- 闹钟：`alarm_service.dart` 的 `planShiftAlarms` / `reschedule` / `rescheduleAll`。
- 文案：`app/lib/core/l10n.dart`。
- 文档：`docs/decisions/schedule.md`、`docs/changelog/v0.13.md`、帮助页、
  `site/index.html`、`README.md`、`PRODUCT_SPEC.md`。
