// app/test/shift_color_picker_test.dart
//
// 自我取色那一层：预览、两颗真的日历小样、16 颗预设、十六进制输入、确定与取消。
//
// 它**不碰库**，所以夹具只有一个 `MaterialApp` + `Scaffold`（挂一个按钮把弹层弹出来）。
// 返回值靠文件级那两个变量接 —— 弹层是命令式的，返回值只有调用点接得到。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/hex_color.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/shift_palette.dart';
import 'package:shiftassistantpro/features/calendar/shift_color_picker.dart';

Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 弹层返回了什么、关没关 —— 每条用例开头由 [_openPicker] 重置。
int? _picked;
bool _closed = false;

Future<void> _openPicker(WidgetTester tester,
    {required int current,
    String? sampleLabel,
    Size size = const Size(420, 900)}) async {
  _picked = null;
  _closed = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            _picked = await showShiftColorPicker(context,
                current: current, sampleLabel: sampleLabel);
            _closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await _settle(tester);
}

/// 预设第 [i] 颗那枚圆点的装饰 —— 用来量「选中描边」。
BoxDecoration _presetDeco(WidgetTester tester, int i) {
  final c = tester.widget<Container>(find.byKey(ValueKey('shift-preset-$i')));
  return c.decoration! as BoxDecoration;
}

Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(find.text(L10n.confirm));
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    L10n.locale = 'zh';
  });

  testWidgets('挂上就有 16 颗预设；当前色那颗带选中描边', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF, sampleLabel: '早');

    for (var i = 0; i < kShiftPalette.length; i++) {
      expect(find.byKey(ValueKey('shift-preset-$i')), findsOneWidget,
          reason: '第 $i 颗不见了');
    }
    expect(find.byKey(const ValueKey('shift-preset-16')), findsNothing,
        reason: '盘是 16 颗，不该有第 17 颗');

    expect(_presetDeco(tester, 0).border, isNotNull, reason: '当前色那颗要看得出来');
    expect(_presetDeco(tester, 8).border, isNull, reason: '其余的不带描边');

    await _dispose(tester);
  });

  testWidgets('挑一颗预设 → 确定：返回那颗色', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF);

    await tester.tap(find.byKey(const ValueKey('shift-preset-8')));
    await _settle(tester);
    await _tapConfirm(tester);

    expect(_closed, isTrue);
    expect(_picked, 0xFFE53935, reason: '第 8 颗是红');

    await _dispose(tester);
  });

  testWidgets('什么都不动 → 确定：原样返回当前色（当前色不在盘里也不许变）', (tester) async {
    // 0xFF5B7FFF 是域 / 库 / 模板三处的默认色，**任何一版盘都没有它**。
    await _openPicker(tester, current: 0xFF5B7FFF);

    for (var i = 0; i < kShiftPalette.length; i++) {
      expect(_presetDeco(tester, i).border, isNull,
          reason: '当前色不在盘里时，一颗都不该高亮');
    }

    await _tapConfirm(tester);
    expect(_picked, 0xFF5B7FFF);

    await _dispose(tester);
  });

  testWidgets('取消：返回 null', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF);

    await tester.tap(find.text(L10n.cancel));
    await _settle(tester);

    expect(_closed, isTrue);
    expect(_picked, isNull);

    await _dispose(tester);
  });

  testWidgets('点外面关掉：返回 null', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF);

    await tester.tapAt(const Offset(10, 6)); // 遮罩最上面那一点
    await _settle(tester);

    expect(_closed, isTrue);
    expect(_picked, isNull);

    await _dispose(tester);
  });

  testWidgets('十六进制框：敲合法值 → 确定，返回敲的那个', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF);

    await tester.enterText(find.byType(TextField), '#E65100');
    await _settle(tester);
    await _tapConfirm(tester);

    expect(_picked, 0xFFE65100);

    await _dispose(tester);
  });

  testWidgets('十六进制框：敲非法值 → 确定，还是上一次的有效色', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF);

    await tester.enterText(find.byType(TextField), 'nonsense');
    await _settle(tester);
    await _tapConfirm(tester);

    expect(tester.takeException(), isNull);
    expect(_picked, 0xFF4C8DFF,
        reason: '非法输入不许改到任何状态 —— 点确定用的仍是上一次的色');

    await _dispose(tester);
  });

  testWidgets('十六进制框：敲了合法值再改回非法值，颜色要退回到那个合法值', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF);

    await tester.enterText(find.byType(TextField), '#E65100');
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '#zzzzzz');
    await _settle(tester);
    await _tapConfirm(tester);

    expect(_picked, 0xFFE65100, reason: '非法那一版不许把前一个合法值也带走');

    await _dispose(tester);
  });

  testWidgets('小窗 200×400：整层不溢出、确定点得到', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF, size: const Size(200, 400));

    expect(tester.takeException(), isNull, reason: '小窗下不许有布局溢出');

    final confirm = find.text(L10n.confirm);
    expect(confirm, findsOneWidget);
    final hit = tester.hitTestOnBinding(tester.getCenter(confirm));
    expect(hit.path.any((e) => e.target == tester.renderObject(confirm)), isTrue,
        reason: '「确定」的中心得真的打得中 —— 被挤到可点区域外时命中的是别的层');

    await _dispose(tester);
  });

  testWidgets('预览与日历小样跟着当前色走（用十六进制框驱动一次）', (tester) async {
    await _openPicker(tester, current: 0xFF4C8DFF, sampleLabel: '早');

    // 小样上的字是 sampleLabel —— 它在深浅两颗上都画了一次。
    expect(find.text('早'), findsNWidgets(2), reason: '浅色 / 深色各一颗小样');

    await tester.enterText(find.byType(TextField), '#2E7D32');
    await _settle(tester);
    expect(formatHexColor(0xFF2E7D32), '#2E7D32'); // 意图写在这儿：敲的确实是这个
    await _tapConfirm(tester);
    expect(_picked, 0xFF2E7D32);

    await _dispose(tester);
  });
}
