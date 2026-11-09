// app/lib/core/migration_flags.dart
//
// 一次性数据迁移的开关。**不是用户可见设置** —— 不放进 `AppSettings`，
// 也不出现在「我的」页。每个键只回答一个问题：「这段迁移跑过没有？」
//
// 为什么需要它：迁移的判据是「旧口径的启发式」。没有开关的话，迁移会在每次
// 启动重跑；用户手工把行挪到恰好等于旧显示日的位置时，会被再次拽回。
// 开关让迁移真正只发生一次。
import 'package:shared_preferences/shared_preferences.dart';

const String _kRecurringRowDayMigrated = 'recurringRowDayMigratedV1';

/// 旧版「行挂提醒落地日」→ 发生日 的迁移跑过没有。
Future<bool> legacyRecurringRowDayMigrated() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getBool(_kRecurringRowDayMigrated) ?? false;
}

Future<void> markLegacyRecurringRowDayMigrated() async {
  final sp = await SharedPreferences.getInstance();
  await sp.setBool(_kRecurringRowDayMigrated, true);
}
