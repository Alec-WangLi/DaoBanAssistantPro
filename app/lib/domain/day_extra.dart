// app/lib/domain/day_extra.dart
//
// 日级「请假 / 加班」的值类型 —— 全局按天记，不挂在某套排班方案上。
//
// 为什么不挂在方案上：请假是「那天我不在」、加班是「那天我多干了」，
// 换一套班表这两个事实仍然成立（与 `ShiftAlarmOverrides` 全局按天的理由相同）。
//
// 一天各最多一条：请假与加班可以同时存在（上午请假、晚上加班是正常排法）。
//
// 请假类型存的是**键**而不是下标：
//  · 内置五类用固定英文键（`annual` / `personal` / …），换语言、加类型都不会串；
//  · 自定义类型存成 `custom:<名字>`，名字跟着**记录本身**走 —— 用户以后把那个
//    类型从选择列表里删掉，历史记录仍然显示得出当时写的是什么，不会变成空白。
//
// 备注也是按行存的（请假一行、加班一行各一份）：同一天上午请假、晚上加班时，
// 两件事的说明本来就不是一句话。

/// 日级记录的种类。
enum DayExtraKind { leave, overtime }

/// 内置请假类型的键。顺序就是选择条里的顺序。
const List<String> kBuiltInLeaveKindKeys = <String>[
  'annual',
  'personal',
  'sick',
  'compensatory',
  'other',
];

/// 自定义类型的存储前缀。
const String kCustomLeaveKindPrefix = 'custom:';

/// 统计里「没选类型」那一档的键（v0.13.17 之前的旧记录都落在这里）。
const String kUnspecifiedLeaveKind = 'unspecified';

/// 把用户起的名字编成库里存的那个键。
String customLeaveKindKey(String name) => '$kCustomLeaveKindPrefix$name';

/// 从键里取回自定义类型的名字；内置类型或空值返回 null。
String? customLeaveKindName(String? key) {
  if (key == null || !key.startsWith(kCustomLeaveKindPrefix)) return null;
  return key.substring(kCustomLeaveKindPrefix.length);
}

/// 是否为内置类型（决定显示时要不要走 L10n）。
bool isBuiltInLeaveKind(String? key) =>
    key != null && kBuiltInLeaveKindKeys.contains(key);

class DayExtra {
  const DayExtra({
    this.leaveMinutes = 0,
    this.overtimeMinutes = 0,
    this.leaveKind,
    this.leaveNote,
    this.overtimeNote,
  });

  /// 请假分钟数；<= 0 视为没有。
  final int leaveMinutes;

  /// 加班分钟数；<= 0 视为没有。
  final int overtimeMinutes;

  /// 请假类型键（见本文件顶部说明）；null = 没选类型（含 v0.13.17 之前的旧记录）。
  final String? leaveKind;

  /// 请假备注（已 trim；空串视为没有）。
  final String? leaveNote;

  /// 加班备注（已 trim；空串视为没有）。
  final String? overtimeNote;

  /// 两样都没有 —— 界面据此不画「假 / 加」标记。
  bool get isEmpty => leaveMinutes <= 0 && overtimeMinutes <= 0;

  /// 这一天有没有任何备注 —— 信息卡据此决定要不要多留一行（见 `info_card_metrics`）。
  bool get hasNote =>
      (leaveNote != null && leaveNote!.isNotEmpty) ||
      (overtimeNote != null && overtimeNote!.isNotEmpty);

  @override
  bool operator ==(Object other) =>
      other is DayExtra &&
      other.leaveMinutes == leaveMinutes &&
      other.overtimeMinutes == overtimeMinutes &&
      other.leaveKind == leaveKind &&
      other.leaveNote == leaveNote &&
      other.overtimeNote == overtimeNote;

  @override
  int get hashCode => Object.hash(
      leaveMinutes, overtimeMinutes, leaveKind, leaveNote, overtimeNote);

  @override
  String toString() =>
      'DayExtra(leave=$leaveMinutes, overtime=$overtimeMinutes, '
      'kind=$leaveKind, leaveNote=$leaveNote, overtimeNote=$overtimeNote)';
}
