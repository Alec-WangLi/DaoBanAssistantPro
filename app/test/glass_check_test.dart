// `GlassCheck` —— 待办那个勾（v0.10.10）。
//
// 用户 2026-10-01：「我看别的设计语言都是用打勾的样式。记得咱们之前把它做成开关了，
// 其实这不符合待办事项的逻辑：弄完之后打勾，给一个删除线表达……但是打勾的话，
// 要融入咱们的设计理念，尤其是现在要区分液态玻璃开启和关闭两种适配状态。」
//
// 全 app 九处 `GlassSwitch` 里**只有待办那一处**是勾选语义，其余八处都是真开关
// （联动闹钟 ×2、跟随法定节假日、液态玻璃、触觉、按天关闹钟、自定义闹钟启用、
// 重复待办启用）—— 所以是**新做一个件**，不是改开关。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/widgets/glass_check.dart';

/// 固定主色 —— 不跟着主题漂，量色相才有意义。
const Color _accent = Color(0xFF5B5BD6);

const Size _canvas = Size(120, 120);

void _ignore(bool _) {}

void main() {
  Future<List<bool>> pumpCheck(
    WidgetTester tester, {
    required bool liquid,
    bool value = false,
    bool enabled = true,
  }) async {
    final List<bool> calls = <bool>[];
    liquidGlassActive.value = liquid;
    addTearDown(() => liquidGlassActive.value = false);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => GlassCheck(
              value: value,
              enabled: enabled,
              activeColor: _accent,
              onChanged: (bool v) {
                calls.add(v);
                setState(() => value = v);
              },
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return calls;
  }

  Future<List<int>> shot(
    WidgetTester tester, {
    required bool liquid,
    required bool value,
  }) async {
    liquidGlassActive.value = liquid;
    addTearDown(() => liquidGlassActive.value = false);
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        // ⚠️ **必须关掉**：默认那面「DEBUG」红丝带是 rgb(161,63,64)，色相 359 ——
        // 它会一路混进「有没有走色相」的判据里（实测 266 个像素）。
        debugShowCheckedModeBanner: false,
        home: Material(
          // **底必须是中性的**：`Material` 默认的 surface 是 (254,247,255)，
          // 那种近白带一点紫的颜色在 HSL 里**饱和度算出来是 1.0**（L → 1 时分母趋零）
          // —— 「带色相」的判据会被整片背景淹没。`liquid_lens_test` 用的是同一个
          // 中性底，这里跟它对齐。
          child: ColoredBox(
            color: const Color(0xFFF5F6FA),
            child: Center(
              child: GlassCheck(
                value: value,
                activeColor: _accent,
                onChanged: _ignore,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    late List<int> px;
    await tester.runAsync(() async {
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 1.0);
      final ByteData? d =
          await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      px = d!.buffer.asUint8List().toList();
    });
    return px;
  }

  int luminanceAt(List<int> px, int i) =>
      (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) ~/ 1000;

  /// 最暗的那个不透明像素的亮度。
  int minLuminance(List<int> px) {
    int best = 255;
    for (int i = 0; i < px.length; i += 4) {
      if (px[i + 3] < 128) continue;
      final int l = luminanceAt(px, i);
      if (l < best) best = l;
    }
    return best;
  }

  /// 带色相的像素离主色最远的色相偏离（度）。**一个都没有就是 0。**
  ///
  /// 除了饱和度的门，还要一道**绝对彩度**的门（`max − min ≥ 24`）：近白与近黑的
  /// 颜色在 HSL 里饱和度是虚高的（(254,247,255) 算出来是 1.00），只按饱和度筛会把
  /// 整片背景当成「彩色」。
  double hueSpread(List<int> px, Color accent) {
    final double base = HSLColor.fromColor(accent).hue;
    double worst = 0;
    for (int i = 0; i < px.length; i += 4) {
      if (px[i + 3] < 128) continue;
      final int hi = px[i] > px[i + 1]
          ? (px[i] > px[i + 2] ? px[i] : px[i + 2])
          : (px[i + 1] > px[i + 2] ? px[i + 1] : px[i + 2]);
      final int lo = px[i] < px[i + 1]
          ? (px[i] < px[i + 2] ? px[i] : px[i + 2])
          : (px[i + 1] < px[i + 2] ? px[i + 1] : px[i + 2]);
      if (hi - lo < 24) continue;
      final HSLColor c = HSLColor.fromColor(
          Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]));
      if (c.saturation < 0.25) continue;
      double d = (c.hue - base).abs() % 360;
      if (d > 180) d = 360 - d;
      if (d > worst) worst = d;
    }
    return worst;
  }

  test('勾是「描出来」的：一半进度恰好是一半长度', () {
    // 「描出来」而不是「缩放出来」是这一处唯一像「被写上去」的写法 ——
    // 缩放只是弹一下，读者看不出笔顺。
    final double full = checkMarkPath(28).computeMetrics().first.length;
    final double half = checkMarkPathAt(28, 0.5).computeMetrics().first.length;
    expect(half, closeTo(full / 2, full * 0.02));
    expect(checkMarkPathAt(28, 0).computeMetrics().isEmpty, isTrue,
        reason: '进度 0 还画得出东西');
    expect(checkMarkPathAt(28, 1).computeMetrics().first.length,
        closeTo(full, 0.01));
  });

  testWidgets('两档是两棵树：光栅化像素必须不同', (tester) async {
    // 反过来说：这条要是绿着不动，说明液态档根本没生效（v0.10.1 出过这个岔子）。
    final List<int> off = await shot(tester, liquid: false, value: true);
    final List<int> on = await shot(tester, liquid: true, value: true);
    int differing = 0;
    for (int i = 0; i < off.length; i++) {
      if (off[i] != on[i]) differing++;
    }
    expect(differing, greaterThan(0), reason: '开了液态档却一个像素都没变');
  });

  testWidgets('未勾选时有一圈**看得见**的轮廓', (tester) async {
    // 这一条钉的是一个真犯过的错：描边原来用 `glassBorder(isDark)` —— 它在浅色下是
    // **白色 @0.90**，画在近白的页面上等于没画。判据要能把它照出来。
    final List<int> px = await shot(tester, liquid: false, value: false);
    expect(minLuminance(px), lessThan(170),
        reason: '未勾选的圆里一个明显暗于背景的像素都没有 —— 那圈描边是白画白');
  });

  testWidgets('勾上没有彩边', (tester) async {
    // 规格 §4.3：控件太小，理由与开关同（§3.1）。判据沿用 `liquid_lens_test`
    // 那条：带色相（离主色 > 25°）的像素一个都不该有。
    final List<int> px = await shot(tester, liquid: true, value: true);
    expect(hueSpread(px, _accent), lessThan(25),
        reason: '勾的边缘出现了走色相的像素 —— 那是给勾加了彩边');
  });

  testWidgets('点一下：值翻转一次', (tester) async {
    final List<bool> calls = await pumpCheck(tester, liquid: true);
    await tester.tap(find.byType(GlassCheck));
    await tester.pumpAndSettle();
    expect(calls, <bool>[true], reason: '点一下没有恰好拨一次');
  });

  testWidgets('勾上之后底色接近不透明（状态由底色承担，不能靠半透读）', (tester) async {
    // 规格 §3.4：28dp 的勾上「透出来的那部分」占了大半，用 `accentGradient`
    // （0.85 → 0.50）整枚会比标准档那枚实心淡一大截 —— 正是用户报的「颜色变浅了」。
    await pumpCheck(tester, liquid: true, value: true);
    final LiquidLens lens = tester.widget<LiquidLens>(find.byType(LiquidLens));
    final List<Color> fill = lens.fill!;
    expect(fill.first.a, greaterThan(0.9), reason: '勾上的底色太透 —— 读起来会发浅');
    expect(fill.last.a, greaterThan(0.75));
  });
}
