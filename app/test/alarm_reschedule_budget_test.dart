// app/test/alarm_reschedule_budget_test.dart
//
// 护栏：一次 `rescheduleAll` 到底往原生发多少次跨端调用。
//
// 历史：每个闹钟后面跟一条 `logInfo` 时，一次重排 99 次跨端里有 46 次是它
// （本用例最初就是为了钉住那份浪费）。后来变成「每条闹钟一次 scheduleNativeAlarm
// + 每条一次全量落盘」，跨端与主线程序列化都是 O(n²)。
//
// 2026-11-23 起整批走 `reconcileNativeAlarms`：**一条只跨一次端、只落一次盘**。
// 这不只是快 —— 旧的「先全撤、再逐条排」中间有几秒系统里一条闹钟都没有，而每次
// 闹钟响都会冷启动 App 并整链重排（用户 2026-11-22 报的「6 点没响」）。
//
// **反向验证过**：把 `reconcileNative` 拆回逐条 `scheduleNativeAlarm`，`total`
// 立刻冲到 50 以上、`reconcileNativeAlarms` 变成 0。
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
import 'support/fixed_clock.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const MethodChannel _channel =
    MethodChannel('com.daoban.shiftassistantpro/settings');
const MethodChannel _notifications =
    MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  useFixedNow();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('一次 rescheduleAll 只发一次 reconcileNativeAlarms、总数不超过 12 次', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final repo = AppRepository(db);
    final template =
        shiftTemplates.firstWhere((x) => x.id == 'four_crew_three_shift');
    await repo.saveSchedule(
      name: template.subtitle,
      anchorDate: dateOnly(kAnchor),
      classes: template.classes,
      cycle: template.cycle,
      makeCurrent: true,
      teamCount: template.teamCount,
      teamNames: L10n.defaultTeamNames(template.teamCount),
      ourTeamIndex: 0,
      teamOffsets: template.teamOffsets,
    );

    final calls = <String, int>{};
    Map<Object?, Object?>? payload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls[call.method] = (calls[call.method] ?? 0) + 1;
      if (call.method == 'reconcileNativeAlarms') {
        payload = Map<Object?, Object?>.from(call.arguments as Map);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));
    // 通知插件那条也要接住：没接住的话 `_plugin.cancelAll()` 会走
    // 「异常 → 清缓存 → 再试 → 再异常」的兜底，凭空多几次跨端，数就不准了。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notifications, (call) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notifications, null));

    await AlarmService.rescheduleAll(repo);

    expect(calls['reconcileNativeAlarms'], 1,
        reason: '重排必须是一整批：逐条跨端既慢，又把「先排后清」拆成了可中断的窗口');
    final int total = calls.values.fold<int>(0, (a, b) => a + b);
    expect(total, lessThanOrEqualTo(12),
        reason: '一次重排只该有「几条汇总 + 一次快照 + 一次重排」。实测本次：$calls');
    expect(calls['scheduleNativeAlarm'] ?? 0, 0,
        reason: '逐条排定只留给贪睡 / 测试闹钟，重排不该再走它');

    final alarms = (payload!['alarms'] as List).cast<Map>();
    expect(alarms.length, greaterThan(30),
        reason: '四班三倒 × 未来 60 天，班次闹钟应当有几十条');
    // 最近的那条排在最前：断在中间也先保住马上要响的。
    int prev = 0;
    for (final a in alarms) {
      final millis = a['millis'] as int;
      expect(millis, greaterThanOrEqualTo(prev));
      prev = millis;
    }
  });
}
