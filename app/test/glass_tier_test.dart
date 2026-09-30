// 玻璃档位的结构性护栏。
//
// 阶段 1 管「标准档」：`GlassPanel` / `GlassBlur` 的 filter 必须是
// **「模糊 + 真实饱和度」的复合**，不是裸的一层 blur。
//
// 为什么值得钉：`glass.dart` 顶上那段注释一直写着「2) 半透明渐变着色（近似饱和度
// 提升）」—— 那是拿一层白渐变**假装**饱和度。这一版把它换成真的之后，任何一次
// 「顺手简化回 `ImageFilter.blur(...)`」都会让 App 静默退回那个「近似」的观感，
// 而那种退步**不会报错、也未必一眼看得出来**。

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';

/// 装配一个 GlassPanel 并取回它那层 `BackdropFilter` 的 filter。
///
/// 返回可空：`BackdropFilter.filter` 本身可空（null = 不过滤）。为 null 时
/// 下面那条 `isNot(blur)` 会过 —— 所以调用点必须先断言它非空，别让空值蒙混过去。
Future<ImageFilter?> _panelFilter(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: GlassPanel(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    ),
  );
  final backdrop =
      tester.widget<BackdropFilter>(find.byType(BackdropFilter));
  return backdrop.filter;
}

void main() {
  setUp(() {
    // 每个用例从「标准档」起跑：省电档关。全局标志不重置的话，
    // 前一个用例把它打开过就会漏到这一个里。
    lowEndDevice = false;
    recomputeGlassBlur();
  });

  test('glassSaturation 就是 spec 写的 Rec.709 保亮度矩阵（s = 1.2）', () {
    // 钉的是**公式**：`invSat * L_i`（对角线上再加 s），L 取 Rec.709 的三个亮度系数。
    //
    // 为什么照着公式算一遍、而不是写一组四舍五入的字面量：`ColorFilter` 的 `==`
    // 是按内容**逐位比 double** 的，而 `-0.2 * 0.7152` 是 `-0.14303999999999994`，
    // 不等于手抄的 `-0.14304`。写死字面量只会得到一条假红。
    //
    // 这条钉子守的是：`ColorFilter.saturation(1.2)` 是 SDK 的实现细节、不是契约 ——
    // 哪天它换了亮度系数（Rec.709 → Rec.601）或换了语义，观感会跟着变而没有任何
    // 东西报警。把 spec 的公式钉在这里，那种改变会立刻变红。
    const double s = 1.2;
    const double lr = 0.2126;
    const double lg = 0.7152;
    const double lb = 0.0722;
    const double invSat = 1 - s;
    expect(
      AppTokens.glassSaturation,
      const ColorFilter.matrix(<double>[
        invSat * lr + s, invSat * lg, invSat * lb, 0, 0, // R
        invSat * lr, invSat * lg + s, invSat * lb, 0, 0, // G
        invSat * lr, invSat * lg, invSat * lb + s, 0, 0, // B
        0, 0, 0, 1, 0,
      ]),
    );
  });

  testWidgets('标准档：GlassPanel 的 filter 不只是一层模糊', (tester) async {
    final filter = await _panelFilter(tester);

    expect(filter, isNotNull, reason: 'GlassPanel 根本没挂 filter');
    expect(
      filter,
      isNot(ImageFilter.blur(
          sigmaX: AppTokens.blurPanel, sigmaY: AppTokens.blurPanel)),
      reason: 'filter 还是裸的 blur —— 真实饱和度没有接进去，'
          '观感退回「白渐变近似饱和度」那一版',
    );
  });

  testWidgets('标准档：GlassPanel 的 filter 恰好是「模糊 + 饱和度」的复合',
      (tester) async {
    final filter = await _panelFilter(tester);

    // 精确到 sigma 与内外层顺序 —— `compose` 的语义是 `outer(inner(source))`，
    // 两者写反了照样是个合法 filter，只是「先糊再提饱和」变成了「先提饱和再糊」，
    // 上面那条「不是裸的 blur」**抓不到**这种错。
    expect(
      filter,
      ImageFilter.compose(
        outer: ImageFilter.blur(
            sigmaX: AppTokens.blurPanel, sigmaY: AppTokens.blurPanel),
        inner: AppTokens.glassSaturation,
      ),
      reason: '复合出来的不是「该有的模糊 × 该有的饱和度」',
    );
  });

  testWidgets('标准档：GlassBlur 的 filter 也是「模糊 + 饱和度」的复合',
      (tester) async {
    const sigma = 8.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              ColoredBox(color: Color(0xFF7A8A9A)),
              GlassBlur(
                sigma: sigma,
                child: SizedBox(width: 40, height: 40),
              ),
            ],
          ),
        ),
      ),
    );

    final backdrop =
        tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(
      backdrop.filter,
      ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        inner: AppTokens.glassSaturation,
      ),
    );
  });

  testWidgets('省电档：GlassBlur 直接返回 child，一层 filter 都不套',
      (tester) async {
    // 省电档的地基：`glassBlurDisabled` 时**短路**。改成「照常套一层、
    // 只是内容透明」之类的写法，低内存机器就白付一次 backdrop 抓取 ——
    // 而那正是这一档存在的理由。
    lowEndDevice = true;
    recomputeGlassBlur();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassBlur(
            sigma: 8,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
