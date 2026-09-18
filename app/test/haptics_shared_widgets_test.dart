// app/test/haptics_shared_widgets_test.dart
//
// 共享组件自己震的那几处。三件事各有用例：
//   1. 真的会震（不然「自动一致」是空话）
//   2. 状态没变时**不震**（点当前已选中的那一段不该有反馈）
//   3. 选择器的滚轮**滚动**不震 —— 拨一次滚轮连震十几下是这套设计最容易犯的错
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/haptics.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_choice_chip.dart';
import 'package:shiftassistantpro/core/widgets/glass_pickers.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> fired;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    fired = [];
    hapticsDisabled = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fired.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    hapticsDisabled = false;
  });

  testWidgets('GlassSwitch 翻转时震一次', (tester) async {
    var value = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GlassSwitch(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(GlassSwitch));
    await tester.pumpAndSettle();
    expect(fired, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('GlassSegment 选中项变了才震；点当前段不震', (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GlassSegment(
            count: 3,
            selectedIndex: selected,
            height: 40,
            // `itemBuilder` 是**必填**的（签名已核实），漏了编译不过。
            itemBuilder: (i, isSelected) => Text('$i'),
            onSelected: (i) => setState(() => selected = i),
          ),
        ),
      ),
    ));

    // 点第二段：选中变了 → 震
    final box = tester.getRect(find.byType(GlassSegment));
    await tester.tapAt(Offset(box.left + box.width / 2, box.center.dy));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1), reason: '选中变了该震');

    // 再点同一段：没变 → 不震
    await tester.tapAt(Offset(box.left + box.width / 2, box.center.dy));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1), reason: '状态没变不该再震');
  });

  testWidgets('GlassChoiceChip 选中时震一次', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlassChoiceChip(
          label: '白班',
          selected: false,
          color: Colors.blue,
          onTap: () {},
        ),
      ),
    ));
    await tester.tap(find.byType(GlassChoiceChip));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1));
  });

  testWidgets('时间选择器：拨滚轮不震，点确定才震一次', (tester) async {
    // 这一条是 spec §6.3 点名的「滚轮不震」，也是这套设计最容易犯的错 ——
    // 把触觉挂到 `onSelectedItemChanged` 上，拨一次滚轮会连震十几下。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showGlassTimePicker(
              context,
              initialTime: const TimeOfDay(hour: 7, minute: 0),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 拨滚轮：一格都不该震
    final wheel = find.byType(ListWheelScrollView);
    expect(wheel, findsWidgets, reason: '时间选择器应该是滚轮');
    await tester.drag(wheel.first, const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: '滚动不是提交，绝不能震');

    // 点确定：一次
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();
    expect(fired, hasLength(1), reason: '确定那一处才是提交点');
  });
}
