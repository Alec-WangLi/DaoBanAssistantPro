// 按月切法 —— 「每月第几天起换成哪个班次」的规则本体。
//
// 两套锚定的分工：`shift_rotation.dart` 是**连续周期**（离基准日多少天 mod 周期
// 长度），这里是**按月归零**（每月的第 N 天起换一段、最后一段自动到月底）。
// 月份长度在 28~31 之间变，所以固定长度的周期表达不了它 —— 用 31 天硬凑的话，
// 每过一个 30 天的月就往后错一天（用户 2026-10-13 报的「12 月 1 日显示成夜班」
// 就是这么来的）。
//
// **本文件只跟「当月第几天」这个整数打交道，不碰 `DateTime`。** 因此它既没有
// 时区风险（全仓那条「日期比较一律走 dayNumber / dateOnly」的纪律在这里无从违反），
// 也能纯整数测；把日期换成日号是 `shift_rotation.dart` 的事。
//
// 两条结构性约束（spec §3.1）：
//   · 第一段恒从 1 日起（于是「每月 1 号归零」是**结构上**成立的，不靠额外判断）；
//   · 最后一段自动延伸到月底（于是 31 天的月里它是 11 天、2 月里只有 8 天 —— 月份
//     长度变化被算进语义里，而不是被当成例外去补）。
// 代价是：起始日填 29 / 30 / 31 的段遇上 2 月会整月不出现，那些天落在**上一段**。
library;

/// 一段：从每月的第 [startDay] 天起，改用 [classIndex] 那个班次定义。
///
/// [classIndex] 是 `ShiftSchedule.classes` 的**下标**（不是库里的 classId）——
/// 与 `domain` 层其它地方同口径；落库时的换算在 `app_repository.dart` 里做。
class MonthlySegment {
  const MonthlySegment({required this.startDay, required this.classIndex});

  /// 每月第几天起（1..31）。第一段恒为 1。
  final int startDay;

  /// 段内用哪个班次（`classes` 的下标）。
  final int classIndex;

  @override
  bool operator ==(Object other) =>
      other is MonthlySegment &&
      other.startDay == startDay &&
      other.classIndex == classIndex;

  @override
  int get hashCode => Object.hash(startDay, classIndex);

  @override
  String toString() => 'MonthlySegment(from $startDay → #$classIndex)';
}

/// 某一天落在第几段（[dayOfMonth] 是当月的号数，1..31）。
///
/// 判据是「最后一个 `startDay <= dayOfMonth` 的段」—— 于是每个月的 1 号必然落在
/// 第一段（第一段的 `startDay` 恒为 1），**这就是「按月归零」的全部实现**。
///
/// 表为空、或那天早于第一段（脏数据）时返回 `-1`，由调用方转成「没有班次」。
int segmentIndexOn(List<MonthlySegment> segments, int dayOfMonth) {
  for (var i = segments.length - 1; i >= 0; i--) {
    if (segments[i].startDay <= dayOfMonth) return i;
  }
  return -1;
}

/// 第 [teamSegOffset] 个班组在某天上哪个班次（`classes` 的下标）。
///
/// **班组错位在按月模式下是按「段」错开的，不是按天**（spec §3.3）：转的是
/// 「这一段分配哪个班次」，段与段的分界不动 —— 于是所有班组都在**同一天**换班，
/// 只是换到不同的班次上。按天错开做不到这件事：月份长度与天数算式对不齐，取哪个
/// 偏移组合都会在某个号数上撞班（用例在 `monthly_schedule_test.dart`）。
///
/// 表为空或那天无段时返回 `null`。Dart 的 `%` 对正除数恒返回非负值，所以负的
/// [teamSegOffset] 直接取模就对。
int? monthlyClassIndexOn(
    List<MonthlySegment> segments, int dayOfMonth, int teamSegOffset) {
  final n = segments.length;
  if (n == 0) return null;
  final seg = segmentIndexOn(segments, dayOfMonth);
  if (seg < 0) return null;
  return segments[(seg + teamSegOffset) % n].classIndex;
}

/// 段表合法吗：非空、第一段从 1 起、严格递增、都在 1..31 内。
///
/// 保存前与读回脏数据时都用它。**「严格递增」这一条就是「不出现空档与重叠」的
/// 全部保证** —— 每段只带起始日、结束日由下一段的起始日决定，所以只要递增，
/// 整月的覆盖必然既不重叠也不留缝。
bool validMonthlySegments(List<MonthlySegment> segments) {
  if (segments.isEmpty) return false;
  if (segments.first.startDay != 1) return false;
  var prev = 0;
  for (final s in segments) {
    if (s.startDay < 1 || s.startDay > 31) return false;
    if (s.startDay <= prev) return false;
    prev = s.startDay;
  }
  return true;
}

/// 一套「均分」的起步段表：把 31 天按 [count] 等分，第 i 段指向第 i 个班次。
///
/// 都用它做**起点**，因为「不指定就撞班」是个很差的初体验：班组数与段数不等时
/// 平均分配本来就会告警，所以起步一律让段数等于班组数（调用方传 `teamCount`）。
/// [count] 为 1 时正好退化成 `[(1, 0)]` —— 整月一个班次。
///
/// 按 **31 天**算而不是按当月真实天数：段表是「每月的第几天起」，与具体哪个月
/// 无关，31 是它的上界。
List<MonthlySegment> defaultMonthlySegments(int count) {
  if (count <= 0) return const [];
  return [
    for (var i = 0; i < count; i++)
      MonthlySegment(
        startDay: 1 + (i * 31 / count).round(),
        classIndex: i,
      ),
  ];
}
