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

  group('sanitizeSystemInsets：系统栏内边距体检', () {
    // 实测数据（Redmi K90 Pro Max + 小米小窗）：
    //   win=199.7x400.0 dpr=3.0 pad(t400.0,b22.7) vpad(t400.0,b22.7)
    // top 正好等于窗口高度 —— 于是每个开着的 SafeArea 都把整页吃掉，
    // 日历页正文可用高度变成 0，小窗里只剩底部导航胶囊。
    const smallWindow = MediaQueryData(
      size: Size(199.67, 400),
      viewPadding: EdgeInsets.only(top: 400, bottom: 22.67),
      padding: EdgeInsets.only(top: 400, bottom: 22.67),
    );

    test('小窗：报成整窗高度的 top 归零，正常的手势条留着', () {
      final fixed = sanitizeSystemInsets(smallWindow);
      expect(fixed.viewPadding.top, 0);
      expect(fixed.padding.top, 0, reason: 'SafeArea 读的是 padding，也得改到');
      expect(fixed.viewPadding.bottom, closeTo(22.67, 0.01),
          reason: '底部手势条是真实存在的系统栏，不能一起清掉');
    });

    test('小窗：清完之后可用高度回到整个窗口', () {
      // 不清的话 availableHeight = 400 − 422 < 0，分档与格子高度全乱。
      final mq = sanitizeSystemInsets(smallWindow);
      final available = mq.size.height -
          mq.viewInsets.vertical -
          mq.viewPadding.vertical;
      expect(available, closeTo(377.33, 0.01));
    });

    test('正常竖屏：一个值都不动', () {
      const portrait = MediaQueryData(
        size: Size(420, 900),
        viewPadding: EdgeInsets.only(top: 48, bottom: 24),
        padding: EdgeInsets.only(top: 48, bottom: 24),
      );
      final fixed = sanitizeSystemInsets(portrait);
      expect(fixed.viewPadding, const EdgeInsets.only(top: 48, bottom: 24));
      expect(fixed.padding, const EdgeInsets.only(top: 48, bottom: 24));
    });

    test('键盘的 viewInsets 不参与收敛（占半屏是正常的）', () {
      const typing = MediaQueryData(
        size: Size(420, 900),
        viewPadding: EdgeInsets.only(top: 48),
        padding: EdgeInsets.only(top: 48),
        viewInsets: EdgeInsets.only(bottom: 400),
      );
      final fixed = sanitizeSystemInsets(typing);
      expect(fixed.viewInsets.bottom, 400);
      expect(fixed.padding.top, 48);
      expect(fixed.padding.bottom, 0, reason: '键盘占满时底部不再留系统栏');
    });
  });
}
