// app/test/todo_dialog_test.dart
//
// 待办弹窗的两处行为：
//
//   1. **「添加」与「编辑」两个弹窗必须是同一套字段**。v0.7.1 就是在这里出的
//      岔子：两处各写了一遍，改提醒档位时只改到「添加」，编辑弹窗还停在旧的两档
//      开关上 —— 点它只会在「不设 / 15 分钟」之间跳。判据是选择器里的那些档位
//      标签（「提前1天」这类）只有弹层才画得出来，两档开关永远不会有。
//   2. **提醒档位与「联动闹钟」开关联动**：开闹钟要补一个可响的时点，选「不设」
//      要顺手把闹钟关掉，否则开关开着却没有时刻，用户以为它会响而它永远不会。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 有界推进若干帧。
///
/// **不用 `pumpAndSettle`**：它要等到「没有待调度的帧」才返回，页面上只要有一个
/// 一直调度下一帧的东西就会挂到超时（默认 10 分钟）。逐帧推进既不会挂，结果也是
/// 确定性的 —— 与视觉工装同样的做法。800ms 的假时钟足够走完弹窗与弹层的动画。
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长定时器
/// 真的跑掉（否则框架报「A Timer is still pending」）。
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Future<AppDatabase> _pumpTodos(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: ScheduleScreen()),
  ));
  await _settle(tester);
  return db;
}

/// 打开某条待办的编辑弹窗。
Future<void> _openEdit(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await _settle(tester);
  expect(find.text(L10n.editEvent), findsOneWidget);
}

/// 弹窗里的那个开关（列表行上也有一个「完成」开关，所以按弹窗范围取）。
Finder _alarmSwitch() => find.descendant(
    of: find.byType(GlassDialog), matching: find.byType(GlassSwitch));

bool _switchOn(WidgetTester tester) =>
    tester.widget<GlassSwitch>(_alarmSwitch()).value;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    L10n.locale = 'zh';
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('编辑弹窗：提醒档位弹得出选择器（v0.7.1 只会在两档之间跳）',
      (tester) async {
    final db = await _pumpTodos(tester);
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
      advanceRemindMinutes: 15,
    );
    await _settle(tester);
    await _openEdit(tester, '交体检报告');

    await tester.tap(find.text(L10n.advanceRemindOptional));
    await _settle(tester);

    // 这些标签只有档位弹层画得出来。
    expect(find.text(L10n.remindOptionLabel(0)), findsOneWidget); // 准时
    expect(find.text(L10n.remindOptionLabel(1440)), findsOneWidget); // 提前1天
    expect(find.text(L10n.remindOptionLabel(30)), findsOneWidget); // 提前30分钟

    await tester.tap(find.text(L10n.remindOptionLabel(1440)));
    await _settle(tester);
    // 选完落到那一行上（弹层已关，剩下这一处）。
    expect(find.text(L10n.remindOptionLabel(1440)), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('添加弹窗：提醒档位同样弹得出选择器', (tester) async {
    await _pumpTodos(tester);

    await tester.tap(find.byIcon(Icons.add_outlined));
    await _settle(tester);
    expect(find.text(L10n.addEvent), findsOneWidget);

    await tester.tap(find.text(L10n.advanceRemindOptional));
    await _settle(tester);
    expect(find.text(L10n.remindOptionLabel(1440)), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('联动闹钟开关：开时补「准时」，选「不设」时自动关', (tester) async {
    final db = await _pumpTodos(tester);
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
    );
    await _settle(tester);
    await _openEdit(tester, '交体检报告');

    expect(_switchOn(tester), isFalse, reason: '默认只弹通知');
    expect(find.text(L10n.remindOptionLabel(L10n.remindNone)), findsOneWidget,
        reason: '一开始没设提醒');

    // 开闹钟 → 提醒自动补成「准时」
    await tester.tap(_alarmSwitch());
    await _settle(tester);
    expect(_switchOn(tester), isTrue);
    expect(find.text(L10n.remindOptionLabel(0)), findsOneWidget,
        reason: '开着闹钟却没有可响的时刻，等于开关是假的');

    // 再把提醒设成「不设」→ 闹钟跟着关
    await tester.tap(find.text(L10n.advanceRemindOptional));
    await _settle(tester);
    await tester.tap(find.text(L10n.remindOptionLabel(L10n.remindNone)).last);
    await _settle(tester);
    expect(_switchOn(tester), isFalse,
        reason: '「不设」的意思就是别提醒我，闹钟不该还开着');

    // 存下去：库里那条待办的两个字段要自洽（没有提醒就没有闹钟）
    await tester.tap(find.text(L10n.save));
    await _settle(tester);
    final saved = (await AppRepository(db).listEvents()).single;
    expect(saved.advanceRemindMinutes, isNull);
    expect(saved.alarmEnabled, isFalse);

    await _dispose(tester);
  });

  testWidgets('联动闹钟开关：存得进库、列表行上带铃铛', (tester) async {
    final db = await _pumpTodos(tester);
    await AppRepository(db).addEvent(
      title: '交体检报告',
      date: dateOnly(DateTime.now()),
      timeMinute: 14 * 60,
    );
    await _settle(tester);
    await _openEdit(tester, '交体检报告');

    await tester.tap(_alarmSwitch());
    await _settle(tester);
    await tester.tap(find.text(L10n.save));
    await _settle(tester);

    final saved = (await AppRepository(db).listEvents()).single;
    expect(saved.alarmEnabled, isTrue);
    expect(saved.advanceRemindMinutes, 0, reason: '自动补的「准时」');

    // 列表行上那个小铃铛
    expect(find.byIcon(Icons.alarm_outlined), findsOneWidget);

    await _dispose(tester);
  });
}
