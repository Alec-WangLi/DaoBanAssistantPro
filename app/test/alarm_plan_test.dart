// app/test/alarm_plan_test.dart
//
// 「一批交给原生」的那一层纯逻辑：请求怎么拼、撤哪些、下一跳怎么写。
//
// 为什么要逐条钉：2026-11-22 一位三星用户报「早上 6:00 没响」，日志里 4:00 全链路
// 正常、6:00 **连 `AlarmReceiver.onReceive` 都没有** —— 那一刻系统里根本没有它。
// 旧实现是「先按固定区间盲扫全撤 + 清空落盘清单，再一条条排回来」，中间有几秒
// 一条闹钟都没有，而每次闹钟响都会冷启动 App 并整链重排。
//
// 改成「先排后清」之后，「撤哪些」只剩 [staleNativeIds] 一个纯函数 —— 它错了不会
// 报错，只会把该响的闹钟撤掉（或该撤的留下），所以这里逐条钉住。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'support/fixed_clock.dart';

const MethodChannel _settings =
    MethodChannel('com.daoban.shiftassistantpro/settings');
const MethodChannel _notifications =
    MethodChannel('dexterous.com/flutter/local_notifications');

/// 拦下来的那一次 `reconcileNativeAlarms` 的参数。
Map<Object?, Object?>? lastReconcile;

List<Map<Object?, Object?>> reconciledAlarms() =>
    [for (final a in (lastReconcile?['alarms'] as List? ?? const [])) a as Map<Object?, Object?>];

List<Map<Object?, Object?>> reconciledQuiets() =>
    [for (final q in (lastReconcile?['quiets'] as List? ?? const [])) q as Map<Object?, Object?>];

List<int> reconciledCancelIds() =>
    [for (final id in (lastReconcile?['cancelIds'] as List? ?? const [])) id as int];

void _installChannels({List<int> storeIds = const []}) {
  lastReconcile = null;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_settings, (call) async {
    switch (call.method) {
      case 'nativeAlarmStoreIds':
        return storeIds;
      case 'reconcileNativeAlarms':
        lastReconcile = Map<Object?, Object?>.from(call.arguments as Map);
        return null;
      default:
        return null;
    }
  });
  messenger.setMockMethodCallHandler(_notifications, (call) async => null);
  addTearDown(() {
    messenger.setMockMethodCallHandler(_settings, null);
    messenger.setMockMethodCallHandler(_notifications, null);
  });
}

/// 两天一循环：10/15 白班（07:00 + 07:30「出门」），其余休班。
ShiftSchedule _schedule() => ShiftSchedule(
      name: '测试',
      anchorDate: DateTime.utc(2026, 10, 15),
      classes: const [
        ShiftClass(
            id: 11,
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60,
            endMinute: 20 * 60,
            alarmEnabled: true,
            alarms: [
              ShiftAlarm(minute: 7 * 60),
              ShiftAlarm(minute: 7 * 60 + 30, label: '出门'),
            ]),
        ShiftClass(id: 12, name: '休班', abbr: '休', isRest: true),
      ],
      cycle: const [0, 1],
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
      dayOverrides: const {},
    );

CustomAlarm _custom({
  int id = 1,
  int hour = 6,
  int minute = 30,
  int repeatType = 1,
  DateTime? onceDate,
  int weekdays = 0,
  bool enabled = true,
}) =>
    CustomAlarm(
      id: id,
      hour: hour,
      minute: minute,
      repeatType: repeatType,
      onceDate: onceDate,
      weekdays: weekdays,
      enabled: enabled,
    );

ScheduleEvent _event({
  int id = 7,
  String title = '交报告',
  DateTime? date,
  int? timeMinute = 9 * 60 + 30,
  int advance = 0,
  bool alarmEnabled = false,
  int? seriesId,
}) =>
    ScheduleEvent(
      id: id,
      title: title,
      date: date ?? DateTime.utc(2026, 10, 16),
      timeMinute: timeMinute,
      advanceRemindMinutes: advance,
      isCompleted: false,
      alarmEnabled: alarmEnabled,
      seriesId: seriesId,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  useFixedNow();
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('班次闹钟的请求', () {
    test('一条 plan 一条请求，id = 序号 × 60 + 偏移', () async {
      _installChannels();
      final schedule = _schedule();
      final plans = planShiftAlarms(schedule, from: kAnchor, days: 5);
      expect(plans, isNotEmpty, reason: '两天一循环里应当有上班日');

      await AlarmService.reschedule(schedule, const [], days: 5);

      final alarms = reconciledAlarms();
      expect(alarms.length, plans.length);
      final byId = {for (final a in alarms) a['id'] as int: a};
      for (final p in plans) {
        final id = p.alarmIndex * AlarmService.shiftDaysHorizonForTesting +
            p.offset;
        expect(byId.containsKey(id), isTrue,
            reason: '原生 id 必须是「序号 × 天数窗口 + 偏移」，'
                '改成别的算式会让每次重排都换一批号');
        expect(byId[id]!['millis'] as int, p.fireAt.millisecondsSinceEpoch);
      }
    });

    test('按触发时刻升序递过去（进程被打断也先保住马上要响的）', () async {
      _installChannels();
      await AlarmService.reschedule(_schedule(), const [], days: 5);

      final millis = [for (final a in reconciledAlarms()) a['millis'] as int];
      expect(millis.length, greaterThan(1));
      for (var i = 1; i < millis.length; i++) {
        expect(millis[i], greaterThanOrEqualTo(millis[i - 1]),
            reason: '第 $i 条排在了更早的那条前面 —— 断在中间就丢了最近的');
      }
    });

    test('标题走 L10n.shiftAlarmTitle（带名字的那条也要带上）', () async {
      _installChannels();
      await AlarmService.reschedule(_schedule(), const [], days: 5);

      final labels = [for (final a in reconciledAlarms()) a['label'] as String];
      expect(labels.every((l) => l.startsWith('白班')), isTrue);
      expect(labels.any((l) => l.contains('出门')), isTrue,
          reason: '闹钟自己的名字（「出门」）不该在批量重排里丢掉');
    });
  });

  group('自定义闹钟的请求', () {
    test('一次性：已过的不排、停用的不排', () async {
      _installChannels();
      await AlarmService.reschedule(_schedule(), [
        _custom(id: 1, repeatType: 0, onceDate: DateTime.utc(2026, 10, 14)),
        _custom(id: 2, repeatType: 0, onceDate: DateTime.utc(2026, 10, 16)),
        _custom(id: 3, repeatType: 0, onceDate: DateTime.utc(2026, 10, 17),
            enabled: false),
      ]);

      final ids = [for (final a in reconciledAlarms()) a['id'] as int];
      expect(ids, contains(10002), reason: '未来的那一条要排上');
      expect(ids, isNot(contains(10001)), reason: '过去的那一刻不该排');
      expect(ids, isNot(contains(10003)), reason: '停用的不该排');
    });

    test('每天 / 每周带上续排参数（原生靠它自己续下一次）', () async {
      _installChannels();
      await AlarmService.reschedule(_schedule(), [
        _custom(id: 4, repeatType: 1, hour: 6, minute: 20),
        _custom(id: 5, repeatType: 2, hour: 22, minute: 0, weekdays: 1 << 2),
      ]);

      final byId = {for (final a in reconciledAlarms()) a['id'] as int: a};
      expect(byId[10004]!['repeatType'], 1);
      expect(byId[10004]!['hour'], 6);
      expect(byId[10005]!['repeatType'], 2);
      expect(byId[10005]!['weekdays'], 1 << 2);
    });
  });

  group('待办的请求', () {
    test('联动闹钟走响铃、关掉走安静提醒；重复待办的行跳过', () async {
      _installChannels();
      await AlarmService.reschedule(_schedule(), const [], events: [
        _event(id: 7, alarmEnabled: true),
        _event(id: 8, alarmEnabled: false),
        _event(id: 9, seriesId: 5),
      ]);

      final alarmIds = [for (final a in reconciledAlarms()) a['id'] as int];
      final quietIds = [for (final q in reconciledQuiets()) q['id'] as int];
      expect(alarmIds, contains(20007));
      expect(quietIds, contains(20008));
      expect(alarmIds, isNot(contains(20009)),
          reason: '重复待办的某一次由系列那一条负责，两处都排会响两声');
      expect(quietIds, isNot(contains(20009)));
    });

    test('重复待办：响铃时把后续时刻一起递过去（repeatType=3）', () async {
      _installChannels();
      final series = [
        RecurringTodo(
          id: 5,
          title: '交班记录',
          repeat: RecurRepeat.daily,
          startDate: DateTime.utc(2026, 10, 1),
          timeMinute: 20 * 60,
          advanceRemindMinutes: 0,
          alarmEnabled: true,
        ),
      ];
      await AlarmService.reschedule(_schedule(), const [], recurring: series);

      final byId = {for (final a in reconciledAlarms()) a['id'] as int: a};
      final req = byId[40005];
      expect(req, isNotNull, reason: '系列 id 5 的原生 id 是 40000 + 5');
      expect(req!['repeatType'], 3,
          reason: '带时刻表的一律走「弹队首、续队尾」，不让原生自己算规则');
      expect((req['repeatTimes'] as List), isNotEmpty);
    });

    test('重复待办关掉联动闹钟时写成安静提醒，正文是规则不是日期', () async {
      _installChannels();
      final series = [
        RecurringTodo(
          id: 6,
          title: '交班记录',
          repeat: RecurRepeat.daily,
          startDate: DateTime.utc(2026, 10, 1),
          timeMinute: 20 * 60,
          advanceRemindMinutes: 0,
        ),
      ];
      await AlarmService.reschedule(_schedule(), const [], recurring: series);

      final byId = {for (final q in reconciledQuiets()) q['id'] as int: q};
      expect(byId.containsKey(40006), isTrue);
      expect(byId[40006]!['body'], isNotEmpty);
      expect('${byId[40006]!['body']}', isNot(contains('10-1')),
          reason: '同一条提醒会跨很多次，正文写死日期第二次就是错的');
    });
  });

  group('差集：撤哪些', () {
    test('号段内、且新计划里没有的才撤', () {
      expect(
        staleNativeIds(
          armed: [1, 2, 10001, 20005, 50000, 99999],
          desired: [1, 10001],
          ranges: nativeFullRanges,
        ),
        [2, 20005, 99999],
        reason: '50000 不在任何号段里（不是我们的 id），不该被当成残留撤掉',
      );
    });

    test('新计划里的 id 绝不出现（哪怕清单里也有）', () {
      final desired = [3, 7, 11];
      final stale = staleNativeIds(
        armed: [3, 4, 7, 8, 11, 12],
        desired: desired,
        ranges: nativeFullRanges,
      );
      expect(stale, [4, 8, 12]);
      for (final id in desired) {
        expect(stale, isNot(contains(id)),
            reason: '先排后清的前提就是「撤的只能是确认不再需要的」');
      }
    });

    test('只重排待办时碰不到班次闹钟', () {
      expect(
        staleNativeIds(
          armed: [5, 10001, 20007, 40005],
          desired: const [],
          ranges: nativeTodoRanges,
        ),
        [20007, 40005],
        reason: '勾一条待办不该把班次闹钟与自定义闹钟一起撤掉',
      );
    });

    test('去重且升序（同一 id 在清单里只该有一条，坏了也别撤两次）', () {
      expect(
        staleNativeIds(
          armed: [9, 3, 9, 3],
          desired: const [],
          ranges: nativeFullRanges,
        ),
        [3, 9],
      );
    });
  });

  group('下一跳的写法', () {
    test('响铃与提醒一起比，取最早的那条', () {
      expect(
        nativeNextDigest(
          alarms: [
            NativeAlarm(
                id: 125, fireAt: DateTime(2026, 11, 23, 6, 30), label: 'x'),
          ],
          quiets: [
            NativeQuiet(
                id: 20007,
                fireAt: DateTime(2026, 11, 23, 5, 0),
                title: 'y',
                body: 'z'),
          ],
        ),
        '11-23 05:00 id=20007',
      );
    });

    test('一条都没有时写「无」', () {
      expect(nativeNextDigest(alarms: const [], quiets: const []), '无');
    });
  });
}
