// app/test/alarm_reschedule_budget_test.dart
//
// 护栏：一次 `rescheduleAll` 到底往原生发多少次跨端调用。
//
// 每个闹钟后面跟一条 `logInfo`，就是**每次跨端之后再跨一次** —— 本用例实测 99 次里
// 46 次是它（一次 `rescheduleAll` 排 46 条班次闹钟 + 2 条收尾汇总）。真机上每次
// `invokeMethod` 都是一次平台线程往返，而这条链路上还有原生侧 `AlarmStore` 的全量
// 读写，所以「多跨一次端」不是免费的。这条用例把那份浪费钉住，免得哪天又长回来。
//
// **反向验证过**：把 `scheduleNativeAlarm` 里那句 `logInfo` 加回去，
// 这条立刻红（99 > 55）。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const MethodChannel _channel =
    MethodChannel('com.daoban.shiftassistantpro/settings');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('一次 rescheduleAll 的跨端调用不超过 55 次', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final repo = AppRepository(db);
    final template =
        shiftTemplates.firstWhere((x) => x.id == 'four_crew_three_shift');
    await repo.saveSchedule(
      name: template.subtitle,
      anchorDate: dateOnly(DateTime.now()),
      classes: template.classes,
      cycle: template.cycle,
      makeCurrent: true,
      teamCount: template.teamCount,
      teamNames: L10n.defaultTeamNames(template.teamCount),
      ourTeamIndex: 0,
      teamOffsets: template.teamOffsets,
    );

    final calls = <String, int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls[call.method] = (calls[call.method] ?? 0) + 1;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    await AlarmService.rescheduleAll(repo);

    final int total = calls.values.fold<int>(0, (a, b) => a + b);
    expect(total, lessThanOrEqualTo(55),
        reason: '99 次里有 46 次是「每排一条闹钟就跟一条日志」—— 那条不该再跟着跨端。'
            '实测本次：$total');
    expect(calls['logInfo'] ?? 0, lessThanOrEqualTo(3),
        reason: '只许剩收尾那几条汇总，不许逐条记');
    // 反面：别把「排闹钟」本身也砍了
    expect(calls['scheduleNativeAlarm'] ?? 0, greaterThan(30),
        reason: '排班闹钟还是要一条一条排出去的');
  });
}
