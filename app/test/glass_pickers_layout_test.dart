// app/test/glass_pickers_layout_test.dart
//
// 三个玻璃选择器在短屏（手机横屏 / 小窗）下的高度自适应。
//
// 这一版的起因就是它们：`showModalBottomSheet` 默认把弹层压到屏幕的 9/16，
// 横屏 420 高的屏上只有 236px，而时间选择器的内容要 340px —— 一定会溢出。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_pickers.dart';

/// 在指定尺寸下打开某个弹层。
Future<void> _open(
  WidgetTester tester,
  Size size,
  Future<void> Function(BuildContext) open,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // 年份/月份走 L10n.yearMonth / monthShort（intl DateFormat 'zh'），
  // 不初始化就会抛 LocaleDataException —— 那是测试的问题，不是布局的问题。
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });

  testWidgets('时间选择器：高屏正常，横屏不溢出', (tester) async {
    await _open(
      tester,
      const Size(420, 900),
      (c) => showGlassTimePicker(c,
          initialTime: const TimeOfDay(hour: 8, minute: 0)),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('08'), findsOneWidget);
  });

  testWidgets('时间选择器：横屏也不溢出', (tester) async {
    await _open(
      tester,
      const Size(900, 420),
      (c) => showGlassTimePicker(c,
          initialTime: const TimeOfDay(hour: 8, minute: 0)),
    );
    expect(tester.takeException(), isNull, reason: '横屏下弹层不该溢出');
    expect(find.text('08'), findsOneWidget, reason: '滚轮仍要能用');
  });

  testWidgets('月份选择器：小窗也不溢出', (tester) async {
    await _open(
      tester,
      const Size(360, 360),
      (c) => showGlassMonthPicker(c, initialMonth: DateTime(2026, 9)),
    );
    expect(tester.takeException(), isNull, reason: '小窗下弹层不该溢出');
    expect(find.text(L10n.jumpToMonth), findsOneWidget);
  });

  testWidgets('日期选择器：横屏也不溢出', (tester) async {
    await _open(
      tester,
      const Size(900, 420),
      (c) => showGlassDatePicker(c, initialDate: DateTime(2026, 9, 12)),
    );
    expect(tester.takeException(), isNull, reason: '横屏下弹层不该溢出');
  });
}
