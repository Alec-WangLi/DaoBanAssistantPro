// 「重复待办」管理面板在**小窗**（200×400）下的可读性。
//
// 独立审查量出来的一条：那一行的固定件（开关 56 + 间距 + 删除键 36）在 200dp 下
// 几乎占满，标题只剩十来个像素 —— **一个汉字加省略号要 ≈28px**，于是 Flutter
// 什么都不画。行读起来是 `[开关] [垃圾桶]`，看不出自己在开关哪一条规则。
//
// v0.10.10 把开关从 46 加宽到 56 时先修了**溢出**（6px），这一条钉的是**读得出来**：
// 窄窗下把这一行改成两行排（开关与删除在上、标题在下），标题拿回整行宽度。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 拆掉这棵树 —— **必须做**：页面里的 drift 查询流在取消时会用 `Timer.run` 排一个
/// 零时长定时器，而 widget 测试在测试体结束**立刻**校验「没有待处理的定时器」，
/// 不拆就会报「A Timer is still pending even after the widget tree was disposed」
/// （而且那条报错会让 `tearDownAll` 卡上几分钟）。`recurring_screen_test.dart`
/// 里同名的那一份就是这个用途。
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    L10n.locale = 'zh';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final String name in const <String>[
      'dexterous.com/flutter/local_notifications',
      'com.daoban.shiftassistantpro/settings',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
      addTearDown(() =>
          messenger.setMockMethodCallHandler(MethodChannel(name), null));
    }
    db = AppDatabase.forTesting(
        NativeDatabase.opened(sqlite3.sqlite3.openInMemory()));
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  testWidgets('小窗 200×400：面板那一行的标题真的画得出来', (tester) async {
    tester.view.physicalSize = const Size(200, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final DateTime t = DateTime.now();
    await repo.addRecurringTodo(
      title: '周三例会',
      repeat: RecurRepeat.weekly,
      startDate: dateOnly(DateTime(t.year, t.month, t.day - 7)),
      weekdays: 1 << 2,
    );
    await repo.advanceRecurringTodos(today: dateOnly(DateTime.now()));

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ScheduleScreen()),
    ));
    await _settle(tester);

    // 顶栏那个「重复待办」入口（实心主色胶囊，见 v0.9.13）。
    await tester.tap(find.byIcon(Icons.repeat).first);
    await _settle(tester);

    // 页面上还有那条待办自己也叫这个名字 —— 限定在弹层里找。
    final Finder title = find.descendant(
        of: find.byType(GlassDialog), matching: find.text('周三例会'));
    expect(title, findsOneWidget, reason: '面板没打开');
    // ⚠️ 量的是**布局给它的宽度**，不是墨迹：`Text` 带省略号时会把整个约束宽度
    // 吃掉，所以「被压到十来个像素」与「有地方放」在这里分得开。
    final double w = tester.getSize(title).width;
    // 实测：改之前 **14px**（什么都不画）、改之后 **57px**（「周三例会」四个字正好放下）。
    // 门槛取 40：安全地高于「什么都画不出来」，也低于实测值。
    expect(w, greaterThan(40),
        reason: '标题只分到 ${w}px —— 一个汉字加省略号要 ≈28px，'
            '实际什么都画不出来（行读起来只剩开关与垃圾桶）');

    await _dispose(tester);
  });
}
