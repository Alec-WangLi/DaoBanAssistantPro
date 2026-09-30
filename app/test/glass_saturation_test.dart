// 冒烟探针：`ColorFilter` 作为 `ImageFilter` 嵌进 `BackdropFilter`，像素真的会变吗？
//
// 为什么需要它：`ColorFilter implements ImageFilter`（`sky_engine/lib/ui/painting.dart`
// 的 `class ColorFilter implements ImageFilter`）是**类型层面**的事实，但本仓库
// 从来没有跑过这条路 —— `glass.dart` 一直是「一层 blur + 一层白渐变近似饱和度」。
// 整个「真实饱和度」的设计都建立在「这条路能跑」之上，所以它必须先被证明。
//
// 这个文件同时是**永久护栏**：它证明的是引擎行为（复合 filter 真的作用在像素上），
// 而那是设计的承重墙。哪天 Flutter 换了后端把它弄坏，这里会先红。
//
// 反向验证（本探针的牙齿）：`_identity` 那一组必须与基线**相等** —— 它证明这条
// 断言测的是「饱和度」而不是「有没有颜色」。把它去掉，这个文件就退化成一句废话。

import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rec.709 保亮度饱和度矩阵，s = 1.2。
///
/// 与要落进 `AppTokens` 的那份同源（这里先写字面量，因为本任务不改 `lib/`）。
/// 三行各自加和为 1 —— 所以中性灰保持不变。逐行手算：
///   中性灰 v：`0.2126v + 0.7152v + 0.0722v = v`，提饱和后仍是 v。
const List<double> _boost = <double>[
  1.15748, -0.14304, -0.01444, 0, 0, // R
  -0.04252, 1.05696, -0.01444, 0, 0, // G
  -0.04252, -0.14304, 1.18556, 0, 0, // B
  0, 0, 0, 1, 0,
];

/// 单位矩阵：什么都不做。反向验证用。
const List<double> _identity = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
];

/// 底色：低饱和的灰蓝。三通道彼此接近（122 / 138 / 154），提饱和才看得出差别。
const Color _backdrop = Color(0xFF7A8A9A);

/// 光栅化「底色 + 一层玻璃」，返回玻璃正中那个像素的 RGB。
///
/// `blur` 一律用 2：底面是一整块平色，糊不糊都是同一个颜色 —— 于是「模糊」这个
/// 变量被摘掉，只剩饱和度在动。（不用 `sigma: 0` 是为了避开「0 是不是合法 sigma」
/// 这类与本题无关的边角。）
Future<List<int>> _glassPixel(WidgetTester tester, ImageFilter filter) async {
  tester.view.physicalSize = const Size(40, 40);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: _backdrop),
            BackdropFilter(
              filter: filter,
              child: const ColoredBox(color: Color(0x00000000)),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  late List<int> rgb;
  // 取像要在真实异步区里做 —— 伪造时钟区里的 future 永远不会完成
  // （同 `tool/visual/visual_harness.dart` 的 renderScreen）。
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final width = image.width;
    final height = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final bytes = data!;
    final i = ((height ~/ 2) * width + width ~/ 2) * 4;
    rgb = <int>[
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    ];
  });
  return rgb;
}

/// 通道极差：饱和度的直接度量（越饱和，最大通道与最小通道差得越远）。
int _spread(List<int> rgb) {
  final hi = rgb.reduce((a, b) => a > b ? a : b);
  final lo = rgb.reduce((a, b) => a < b ? a : b);
  return hi - lo;
}

ImageFilter _composed(List<double> matrix) => ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      inner: ColorFilter.matrix(matrix),
    );

void main() {
  testWidgets('探针：ColorFilter 嵌进 BackdropFilter 后，像素真的被提饱和',
      (tester) async {
    // 基线 = 今天的样子（只有 blur，没有饱和度矩阵）
    final baseline =
        _spread(await _glassPixel(tester, ImageFilter.blur(sigmaX: 2, sigmaY: 2)));
    // 复合 = 设计要的样子
    final boosted = _spread(await _glassPixel(tester, _composed(_boost)));

    // 把实测值打出来 —— 探针的交付物是**证据**，不是「绿了」。
    // （同 `tool/visual/visual_harness.dart` 的 `[visual] …` 那套写法。）
    // ignore: avoid_print
    print('[probe] 通道极差：基线 $baseline → 提饱和 $boosted（底色 0xFF7A8A9A）');

    // 手算：底色 (122,138,154) 极差 32 → 提饱和后 (119,138,158) 极差 39。
    // 断言写「严格变大」而不是写死 39，免得将来换 s 值就要改测试。
    expect(boosted, greaterThan(baseline),
        reason: '复合 filter 没有提高饱和度 —— 基线 $baseline，提饱和 $boosted');
  });

  testWidgets('反向验证：单位矩阵不改变饱和度（证明上面那条断言有牙齿）',
      (tester) async {
    final baseline =
        _spread(await _glassPixel(tester, ImageFilter.blur(sigmaX: 2, sigmaY: 2)));
    final identity = _spread(await _glassPixel(tester, _composed(_identity)));

    // 若这条也「变大」了，说明上面那条测的是「有没有颜色」而不是「饱和度」。
    expect(identity, closeTo(baseline, 1),
        reason: '单位矩阵不该改变饱和度 —— 基线 $baseline，单位矩阵 $identity');
  });
}
