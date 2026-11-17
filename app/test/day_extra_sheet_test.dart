// app/test/day_extra_sheet_test.dart
//
// 请假 / 加班时长选择层：整天哨兵、30 分钟加减、清除、窄窗不溢出。
//
// 返回值是写库前的唯一决策点：`isFullDay` 让调用方逐天按班次时长算，
// `clear` 让一次操作清掉整段日子。这里不碰数据库。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';
import 'package:shiftassistantpro/domain/day_extra.dart';
import 'package:shiftassistantpro/features/calendar/day_extra_sheet.dart';

Future<void> _pumpHost(
  WidgetTester tester, {
  required void Function(DayExtraSelection?) onResult,
  DayExtraKind kind = DayExtraKind.leave,
  int? existingMinutes,
  int? fullDayMinutes = 720,
  bool hasExisting = false,
  String? initialLeaveKind,
  String? initialNote,
  List<String> customLeaveTypes = const <String>[],
  ValueChanged<List<String>>? onCustomTypesChanged,
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final r = await showDayExtraSheet(
              context,
              kind: kind,
              from: DateTime(2026, 11, 12),
              to: DateTime(2026, 11, 12),
              dayCount: 1,
              existingMinutes: existingMinutes,
              fullDayMinutes: fullDayMinutes,
              hasExisting: hasExisting,
              initialLeaveKind: initialLeaveKind,
              initialNote: initialNote,
              customLeaveTypes: customLeaveTypes,
              onCustomLeaveTypesChanged: onCustomTypesChanged,
            );
            onResult(r);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  testWidgets('请假默认整天，确定回传 fullDay', (tester) async {
    DayExtraSelection? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    expect(find.text(L10n.leave), findsWidgets);
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.isFullDay, isTrue);
    expect(result!.clear, isFalse);
  });

  testWidgets('点「+」从班次时长起步、每次 30 分钟', (tester) async {
    DayExtraSelection? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    await tester.tap(find.byIcon(Icons.add_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    expect(result!.minutes, 750);
    expect(result!.isFullDay, isFalse);
  });

  testWidgets('加班默认 2 小时，没有「整天」档', (tester) async {
    DayExtraSelection? result;
    await _pumpHost(tester,
        kind: DayExtraKind.overtime,
        fullDayMinutes: null,
        onResult: (r) => result = r);

    expect(find.text(L10n.fullDay), findsNothing);
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();
    expect(result!.minutes, 120);
  });

  testWidgets('已有记录时可清除', (tester) async {
    DayExtraSelection? result;
    await _pumpHost(tester,
        existingMinutes: 240, hasExisting: true, onResult: (r) => result = r);

    await tester.tap(find.text(L10n.clear));
    await tester.pumpAndSettle();

    expect(result!.clear, isTrue);
  });

  testWidgets('320 宽：弹层内容不溢出', (tester) async {
    await _pumpHost(tester,
        size: const Size(320, 640), onResult: (_) {});
    expect(tester.takeException(), isNull);
  });

  testWidgets('选请假类型 + 填备注，随结果一起回传', (tester) async {
    DayExtraSelection? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    await tester.tap(find.text(L10n.leaveKindLabel('annual')!));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  家里有事  ');
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    expect(result!.leaveKind, 'annual');
    expect(result!.note, '家里有事', reason: '备注要 trim 掉首尾空格');
  });

  testWidgets('再点一次已选中的类型 = 取消选择', (tester) async {
    DayExtraSelection? result;
    await _pumpHost(tester,
        initialLeaveKind: 'annual', onResult: (r) => result = r);

    await tester.tap(find.text(L10n.leaveKindLabel('annual')!));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();

    expect(result!.leaveKind, isNull);
  });

  testWidgets('自定义类型：起名后出现在选择条并选中，回调带回列表', (tester) async {
    DayExtraSelection? result;
    List<String>? changed;
    await _pumpHost(tester,
        onResult: (r) => result = r,
        onCustomTypesChanged: (v) => changed = v);

    await tester.tap(find.text(L10n.leaveKindAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
          of: find.byType(GlassDialog), matching: find.byType(TextField)),
      '育儿假',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(GlassDialog), matching: find.text(L10n.confirm)));
    await tester.pumpAndSettle();

    expect(changed, ['育儿假']);
    expect(find.text('育儿假'), findsOneWidget);
    await tester.tap(find.text(L10n.confirm));
    await tester.pumpAndSettle();
    expect(result!.leaveKind, customLeaveKindKey('育儿假'));
  });

  testWidgets('长按自定义类型可删除；已有记录的名字不跟着没', (tester) async {
    List<String>? changed;
    await _pumpHost(tester,
        customLeaveTypes: const ['育儿假'],
        onResult: (_) {},
        onCustomTypesChanged: (v) => changed = v);

    await tester.longPress(find.text('育儿假'));
    await tester.pumpAndSettle();
    expect(find.text(L10n.leaveKindDeleteTitle), findsOneWidget);
    await tester.tap(find.text(L10n.delete));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed, isEmpty);
    expect(find.text('育儿假'), findsNothing);
    // 删除后弹层还在，没被一起关掉。
    expect(find.text(L10n.leaveKindTitle), findsWidgets);
  });

  testWidgets('备注会预填已有值（单日编辑）', (tester) async {
    await _pumpHost(tester,
        initialNote: '上次的备注', onResult: (_) {});
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '上次的备注');
  });
}
