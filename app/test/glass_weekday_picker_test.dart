// app/test/glass_weekday_picker_test.dart
//
// 星期多选在弹窗宽度下的几何：七个格子必须排成**一行**、等宽、间距够。
// v0.12.2 真机反馈「选到每周的时候，日期格子挨得太近」—— 当时用的是
// `Wrap(spacing: 6)`，在弹窗里折成 5+2 两行、相邻只隔 6dp。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/glass_weekday_picker.dart';

void main() {
  testWidgets('七个星期格子在 320dp 宽里排成一行、等宽、间距 ≥ 4', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: GlassWeekdayPicker(value: 0, onChanged: (_) {}),
          ),
        ),
      ),
    ));

    final rects = [
      for (var i = 0; i < 7; i++)
        tester.getRect(find.byType(AnimatedContainer).at(i)),
    ];

    expect(rects.map((r) => r.top).toSet().length, 1, reason: '必须是同一行');
    for (var i = 1; i < 7; i++) {
      expect(rects[i].left - rects[i - 1].right, closeTo(4, 0.01),
          reason: '第 $i 格与前一格的间距');
    }
    expect(rects.first.width, closeTo(rects.last.width, 0.01),
        reason: '等宽');
    expect(rects.first.left, greaterThanOrEqualTo(0));
    // 坐标是全局的（控件居中在 360dp 屏里），所以比**跨度**而不是绝对右缘。
    expect(rects.last.right - rects.first.left, lessThanOrEqualTo(320));
  });
}
