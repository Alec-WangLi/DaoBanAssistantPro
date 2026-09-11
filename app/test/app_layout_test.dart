// app/test/app_layout_test.dart
//
// 分档判定是这一版所有适配的输入：判错了，下面每一处都会照着错的档位走。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/layout.dart';

/// 在一个指定尺寸下取分档。
Future<AppLayout> _layoutAt(WidgetTester tester, Size size,
    {EdgeInsets padding = EdgeInsets.zero,
    EdgeInsets viewInsets = EdgeInsets.zero}) async {
  late AppLayout result;
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(
      size: size,
      padding: padding,
      viewPadding: padding,
      viewInsets: viewInsets,
    ),
    child: Builder(builder: (context) {
      result = AppLayout.of(context);
      return const SizedBox();
    }),
  ));
  return result;
}

void main() {
  testWidgets('五种形态的判定与设计表一致', (tester) async {
    final portrait = await _layoutAt(tester, const Size(420, 900));
    expect(portrait.isNarrow, isFalse);
    expect(portrait.isShort, isFalse);
    expect(portrait.isWide, isFalse, reason: '竖屏手机三档全 false，所有分支都不生效');

    final landscape = await _layoutAt(tester, const Size(900, 420));
    expect(landscape.isWide, isTrue);
    expect(landscape.isShort, isTrue);
    expect(landscape.isNarrow, isFalse);

    final small = await _layoutAt(tester, const Size(360, 360));
    expect(small.isShort, isTrue);
    expect(small.isWide, isFalse);
    expect(small.isNarrow, isFalse, reason: '360 是窄的边界值，不算窄');

    final tiny = await _layoutAt(tester, const Size(320, 360));
    expect(tiny.isNarrow, isTrue);
    expect(tiny.isShort, isTrue);
    expect(tiny.isWide, isFalse);

    final car = await _layoutAt(tester, const Size(1280, 720));
    expect(car.isWide, isTrue);
    expect(car.isShort, isFalse, reason: '车机是「宽且不矮」，与手机横屏不是一回事');
    expect(car.isNarrow, isFalse);
  });

  testWidgets('可用高度扣掉键盘与系统栏', (tester) async {
    // 键盘弹起会把可用高度吃掉一半。不扣掉的话，编辑器在键盘弹起时会
    // 被误判成「屏幕变矮了」而切到紧凑档 —— 那是另一回事。
    final withKeyboard = await _layoutAt(
      tester,
      const Size(420, 900),
      viewInsets: const EdgeInsets.only(bottom: 500),
    );
    expect(withKeyboard.availableHeight, 400);
    expect(withKeyboard.isShort, isTrue, reason: '扣掉键盘后确实变矮了');

    final withBar = await _layoutAt(
      tester,
      const Size(420, 900),
      padding: const EdgeInsets.only(top: 40, bottom: 30),
    );
    expect(withBar.availableHeight, 830);
    expect(withBar.availableWidth, 420);
  });
}
