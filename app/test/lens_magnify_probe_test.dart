// 探针：`BackdropFilter` + `ImageFilter.matrix` 能不能在透镜形状里「放大背景」？
//
// 为什么必须先问这一句：底栏的液态透镜要做到「像一块玻璃」而不是「像一枚画得很漂亮
// 的贴纸」，关键在**它底下的东西会在它里面被弯掉**（胶囊的描边、旁边的图标）。开源
// 实现全都靠一层逐像素 shader 做这件事（见 `oc_liquid_glass` 的 SDF 折射）。而 shader
// 在本项目的代价很大：新增构建链、Impeller-only 闸门、`flutter test` 里多半跑不了
// （出不了动图、出不了像素基线）—— 而这一轮的验收全靠它们。
//
// 但 SDK 自带的 `ImageFilter.matrix` **带 `filterQuality`**（对比 `ImageFilter.shader`
// 在 3.47.2 里是单参数、backdrop 采样器写死 Nearest），而且它就是「把当前图层按矩阵
// 变换」。所以问题变成：**它能不能拿来当透镜？** 三个未知：
//   ① 它读到的 backdrop 里**有没有同层里更早画的东西**（胶囊），还是只有页面；
//   ② Flutter 会不会把 backdrop 的读取范围**卡在 BackdropFilter 自己的绘制边界**上
//      —— 卡住的话放大就只能读到自己的那一小块，边缘会拉丝；
//   ③ 矩阵的方向是「内容 ×2」还是「内容 ÷2」（Skia 的 MatrixTransform 语义）。
//
// 素材刻意做成**一条已知位置的硬边**（x=16 的黑竖线）落在透镜（x∈[10,30]）里：
//   内容 ×2 关于中心 x=20 → 线搬到 x=12；
//   内容 ÷2             → 线搬到 x=18；
//   矩阵没生效           → 线还在 x=16。
// 三个答案互不相同，所以这一条能一次把 ①②③ 全部分开。**对照组用单位矩阵** ——
// 同一套机器、只差缩放，于是「是不是矩阵干的」这件事被隔离干净
//（同 `glass_saturation_test.dart` 里那组 `_identity` 的用法）。

import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const double _w = 60;
const double _h = 30;

/// 透镜在画布上的位置。中心 (20, 15)。
const Rect _lens = Rect.fromLTRB(10, 6, 30, 24);
const double _lineX = 16; // 黑竖线（模拟胶囊的描边）

/// 关于 [center] 缩放 [scale] 的矩阵。
Matrix4 _zoomAbout(Offset center, double scale) => Matrix4.identity()
  ..translateByDouble(center.dx, center.dy, 0, 1)
  ..scaleByDouble(scale, scale, 1, 1)
  ..translateByDouble(-center.dx, -center.dy, 0, 1);

/// 「胶囊」：白底 + 一条 2px 黑竖线。
class _BarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(
      Rect.fromLTWH(_lineX - 1, 0, 2, size.height),
      Paint()..color = const Color(0xFF000000),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 光栅化「胶囊 + 透镜」，返回整张图的灰度矩阵（行优先）。
Future<List<int>> _render(WidgetTester tester, ImageFilter? lensFilter) async {
  tester.view.physicalSize = const Size(_w, _h);
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
          children: <Widget>[
            SizedBox.expand(child: CustomPaint(painter: _BarPainter())),
            Positioned(
              left: _lens.left,
              top: _lens.top,
              width: _lens.width,
              height: _lens.height,
              child: lensFilter == null
                  // 纯对照：透镜位置什么都不画。
                  ? const SizedBox.expand()
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: BackdropFilter(
                        filter: lensFilter,
                        child: const ColoredBox(color: Color(0x00000000)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  late List<int> gray;
  // 取像要在真实异步区里做 —— 伪造时钟区里的 future 永远不会完成。
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final int width = image.width;
    final int height = image.height;
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    gray = <int>[];
    for (int i = 0; i < width * height; i++) {
      gray.add(data.getUint8(i * 4)); // 灰阶 B/W 素材，取 R 即可
    }
  });
  return gray;
}

/// 在某一行里找最暗的那一列 —— 也就是黑竖线的位置。
int _darkestColumn(List<int> gray, int row) {
  int best = 0;
  int bestVal = 256;
  for (int x = 0; x < _w.toInt(); x++) {
    final int v = gray[row * _w.toInt() + x];
    if (v < bestVal) {
      bestVal = v;
      best = x;
    }
  }
  return best;
}

void main() {
  const int row = 15; // 透镜的垂直中心

  testWidgets('探针：透镜里用 ImageFilter.matrix 放大，底下的东西真的被搬动了吗',
      (tester) async {
    // ① 完全不放透镜（基线）
    final List<int> bare = await _render(tester, null);
    // ② 透镜里套**单位矩阵** —— 同一套机器，只差缩放
    final List<int> identity = await _render(
        tester, ImageFilter.matrix(Matrix4.identity().storage));
    // ③ 透镜里套**关于自身中心 2× 的矩阵**
    final List<int> zoomed = await _render(
        tester,
        ImageFilter.matrix(
          _zoomAbout(_lens.center, 2).storage,
          filterQuality: FilterQuality.high,
        ));

    final int bareX = _darkestColumn(bare, row);
    final int identityX = _darkestColumn(identity, row);
    final int zoomedX = _darkestColumn(zoomed, row);

    // 探针的交付物是**证据**，不是「绿了」。
    // ignore: avoid_print
    print('[probe] 黑竖线的列位置：无透镜 $bareX → 单位矩阵 $identityX → 2× $zoomedX'
        '（原始 $_lineX，透镜中心 ${_lens.center.dx}）');

    // 单位矩阵必须与基线一致：否则下面那条测的是「有没有透镜」而不是「有没有放大」。
    expect(identityX, closeTo(bareX, 1),
        reason: '单位矩阵不该搬动任何东西 —— 基线 $bareX，单位矩阵 $identityX');

    // 放大必须真的搬动它。三种可能的位置（内容×2 → 12 / 内容÷2 → 18 / 没生效 → 16）
    // 互不相同，所以「变了」本身就足以判定矩阵生效。
    expect(zoomedX, isNot(closeTo(identityX, 1)),
        reason: '矩阵没生效或读不到 backdrop —— 单位矩阵 $identityX，2× $zoomedX');
  });

  // 上面那条是玩具场景。**这一条才是底栏的真实分层** —— 胶囊自己就套着一层
  // `BackdropFilter`（模糊），而透镜是它的兄弟、画在它之后。要问的是：胶囊那层
  // 模糊会不会把 backdrop 截断，让透镜只看到页面、看不到胶囊。
  //
  // 高对比的素材（一条 2px 黑竖线）故意做成**胶囊子树里的一部分**，这样「透镜
  // 看到的到底是胶囊还是页面」在数值上就分得开：看到胶囊 → 线被搬走；只看到
  // 页面 → 线纹丝不动（页面是纯色，没有线）。
  testWidgets('探针：胶囊自己套着 BackdropFilter 时，上面的透镜还看得见它吗',
      (tester) async {
    Future<List<int>> render({required bool magnify}) async {
      tester.view.physicalSize = const Size(_w, _h);
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
              children: <Widget>[
                // 页面底色：纯色，**没有**那条线 —— 于是「透镜采到的是页面」
                // 会表现为「线不见了」。
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFFDDDDDD)),
                ),
                // 胶囊：自己的 BackdropFilter（模糊）+ 一条作为其内容的黑竖线。
                // **left 必须是 0** —— `_BarPainter` 是它的子树，画的是局部坐标，
                // 胶囊一偏移那条线就跟着偏（第一版写成 left:4，量到的 19 其实是
                // 「线在胶囊里的真实位置」，探针因此报了个假失败）。
                Positioned.fromRect(
                  rect: const Rect.fromLTRB(0, 6, 56, 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: CustomPaint(painter: _BarPainter()),
                    ),
                  ),
                ),
                // 透镜：兄弟节点，画在胶囊之后。
                Positioned.fromRect(
                  rect: _lens,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: magnify
                          ? ImageFilter.matrix(
                              _zoomAbout(_lens.center, 2).storage,
                              filterQuality: FilterQuality.high,
                            )
                          : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: const ColoredBox(color: Color(0x00000000)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      late List<int> gray;
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
        final int width = image.width;
        final int height = image.height;
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        image.dispose();
        gray = <int>[];
        for (int i = 0; i < width * height; i++) {
          gray.add(data.getUint8(i * 4));
        }
      });
      return gray;
    }

    // 只扫**透镜之内**那一行，看线在不在、在哪儿。
    int darkestInsideLens(List<int> gray) {
      int best = -1;
      int bestVal = 256;
      for (int x = _lens.left.toInt(); x < _lens.right.toInt(); x++) {
        final int v = gray[row * _w.toInt() + x];
        if (v < bestVal) {
          bestVal = v;
          best = x;
        }
      }
      return best;
    }

    final int flat = darkestInsideLens(await render(magnify: false));
    final int zoomed = darkestInsideLens(await render(magnify: true));

    // ignore: avoid_print
    print('[probe] 透镜区域内最暗的列：不放大 $flat → 2× $zoomed'
        '（线原本在 $_lineX，透镜中心 ${_lens.center.dx}）');

    // 不放大时线应该就在它原来的位置（这正是「透镜看到胶囊」的底证）。
    expect(flat, closeTo(_lineX, 1),
        reason: '不放大时透镜里看不到那条线 —— 胶囊那层模糊把 backdrop 截断了？'
            '实测 $flat，期望 $_lineX');

    // 放大时必须被搬走 —— 否则「透镜弯掉胶囊」这件事在真实分层下不成立。
    expect(zoomed, lessThan(flat - 2),
        reason: '镜头没看到胶囊（只看到页面）—— 不放大 $flat，2× $zoomed');
  });
}
