// 透镜的弹簧解算器。
//
// 为什么不用 `TweenAnimationBuilder`：透镜要的不是「从 A 到 B 的一段补间」，
// 而是两样补间给不了的东西 ——
//   · **速度**：拖动时形状要跟着速度拉伸（Q 弹），速度得从解算器里读；
//   · **过冲**：松手落回格子那一下要越过一点再回来，那才是「Q 弹」。
//
// 纯 Dart、没有 widget 依赖，所以可以直接跑 200 步去断言它的行为。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';

void main() {
  test('收敛：从中点出发最终停到目标上', () {
    final s = LiquidLensSpring(target: 100)..value = 0;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect(s.value, closeTo(100, 0.5));
    expect(s.isAtRest, isTrue);
  });

  test('过冲：落回时越过目标再回来（这就是 Q 弹的观感来源）', () {
    final s = LiquidLensSpring(target: 100)..value = 0;
    double peak = 0;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
      if (s.value > peak) peak = s.value;
    }
    expect(peak, greaterThan(101),
        reason: '没有过冲 —— 那和 easeOut 没有区别，松手那一下就不会有 Q 弹感');
    expect(peak, lessThan(140), reason: '过冲太大（>40%），读起来是「甩过头」');
  });

  test('不发散：目标半路被改写也不炸', () {
    final s = LiquidLensSpring(target: 100);
    for (int i = 0; i < 5; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    s.target = -100; // 连点另一格
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 16));
    }
    expect(s.value, closeTo(-100, 0.5));
  });

  test('帧间隔封顶：喂一个 1 秒的 dt，位移不超过按 maxStep 算出来的那一步', () {
    final capped = LiquidLensSpring(target: 100)..step(LiquidLensSpring.maxStep);
    final huge = LiquidLensSpring(target: 100)..step(const Duration(seconds: 1));
    expect(huge.value, closeTo(capped.value, 1e-9),
        reason: '掉帧时按真实 dt 积分会让透镜瞬移，还会把数值积爆');
  });

  test('掉帧也不发散：按 40ms 一帧跑 200 步，仍然收敛', () {
    // 这一条是**实测撞出来的**（Task 8 接底栏时）：`maxStep` 第一版按「半隐式
    // 欧拉的失稳门槛」`2 / ω`（ω = 38 时是 53ms）取成 48ms，结果在 40ms 一帧下
    // 弹簧**直接发散** —— 速度冲到 2528 格/s（≈ 22.7 万 px/s），透镜被甩到屏幕外
    // 几千像素。那个门槛只是**临界**，能用的步长要严得多。
    //
    // 掉帧（40ms 一帧）不是假想的：widget 测试就按这个节奏泵帧，真机上只要卡一下
    // 也是这个量级。
    final s = LiquidLensSpring(target: 3.5)..value = 0.5;
    for (int i = 0; i < 200; i++) {
      s.step(const Duration(milliseconds: 40));
    }
    expect(s.value, closeTo(3.5, 0.05));
  });

  /// 从 0 出发、**最后一次**离开目标 2% 用了多少毫秒（按 8ms 一帧 = 120Hz 跑）。
  ///
  /// **必须是「最后一次」**：欠阻尼弹簧会在过冲之前先穿过目标，量「第一次进到
  /// 容差内」得到的是「冲上去那一刻」而不是整定时间 —— 第一版就这么量错了，
  /// 差了两倍多（ω=12.6 量成 248ms，实际是 460 上下）。
  double settleMs(double omega, double zeta) {
    const Duration dt = Duration(milliseconds: 8);
    final s = LiquidLensSpring(target: 1, omega: omega, zeta: zeta);
    double last = 0;
    for (int i = 0; i < 500; i++) {
      s.step(dt);
      if ((s.value - 1).abs() >= 0.02) last = (i + 1) * 8.0;
    }
    return last;
  }

  test('位置滑过去约 200ms —— **比标准档慢一档**（用户 2026-10-04 选的）', () {
    // ⚠️ **这条判据与上一版相反**：上一版钉的是「与标准档的 durFast（120ms）相当」，
    // 那是照用户反馈第 6 条「没有标准档那种缓慢优雅」定的。2026-10-04 用户说
    // 「点按吸附过去太快，不够优雅」，于是挑了慢一档。**反馈变了，判据跟着变** ——
    // 别把旧那条当成「原本的契约」。
    final double ms = settleMs(AppTokens.lensSlideOmega, AppTokens.lensSlideZeta);
    expect(ms, inInclusiveRange(160, 300),
        reason: '位置滑过去是 ${ms}ms，不是「慢一档」那档（目标 200ms 上下）');
    expect(ms, greaterThan(AppTokens.durFast.inMilliseconds.toDouble() + 40),
        reason: '还是跟标准档一样快 —— 那就退回上一版的毛病了');
  });

  test('提起与落下是两条不同的弹簧：落下明显更从容', () {
    // Apple 自己的数字（UIKitCore 逆向）：Lift ζ=0.625 / response 0.27s、
    // Unlift ζ=0.7 / response 0.5s。**两条方向不同是有意的** —— 提起要跟手、
    // 落下要从容。用户说「太快、不够优雅」时，我用的是一条 ω=38 的弹簧（快一倍）。
    final double lift = settleMs(AppTokens.lensLiftOmega, AppTokens.lensLiftZeta);
    final double drop = settleMs(AppTokens.lensDropOmega, AppTokens.lensDropZeta);
    // ignore: avoid_print
    print('[probe] 弹簧整定：提起 ${lift}ms / 落下 ${drop}ms');
    expect(lift, inInclusiveRange(160, 400), reason: '提起是 ${lift}ms —— 不该拖沓也不该窜');
    expect(drop, inInclusiveRange(320, 650), reason: '落下是 ${drop}ms —— 要「从容」');
    expect(drop, greaterThan(lift * 1.3), reason: '落下没有比提起更从容 —— 那就白分两条了');
  });

  group('透镜几何', () {
    const double itemW = 85, capsuleH = 64, pad = 6;

    LiquidLensShape at({double lift = 0, double velocity = 0, double page = 0}) =>
        LiquidLensShape.of(
            itemW: itemW,
            capsuleH: capsuleH,
            pad: pad,
            centerPage: page,
            lift: lift,
            velocity: velocity);

    test('静止：是一枚胶囊（两端半径相等、且等于高的一半）', () {
      final s = at();
      expect(s.width, closeTo(itemW, 0.01));
      expect(s.height, closeTo(capsuleH - 2 * pad, 0.01));
      expect(s.leftRadius, closeTo(s.rightRadius, 0.001));
      expect(s.leftRadius, closeTo(s.height / 2, 0.001));
    });

    test('按住：高度 = 基准 + 2 × navLensProtrude（凸出胶囊）', () {
      final s = at(lift: 1);
      expect(s.height,
          closeTo(capsuleH - 2 * pad + 2 * AppTokens.navLensProtrude, 0.01));
      expect(s.height, greaterThan(capsuleH), reason: '按住时要高于胶囊才叫凸出');
    });

    test('拖动：沿运动方向拉伸、垂直方向压缩（面积近似守恒）', () {
      final s = at(lift: 1, velocity: AppTokens.lensVelocityRef);
      expect(s.width, greaterThan(itemW));
      expect(s.height,
          lessThan(capsuleH - 2 * pad + 2 * AppTokens.navLensProtrude));
    });

    test('拖动：前缘比后缘圆（向右拖时右端半径更大），向左拖镜像', () {
      final right = at(lift: 1, velocity: AppTokens.lensVelocityRef);
      expect(right.rightRadius, greaterThan(right.leftRadius));

      final left = at(lift: 1, velocity: -AppTokens.lensVelocityRef);
      expect(left.leftRadius, greaterThan(left.rightRadius));
    });

    test('窄窗：两端圆不许重叠（外公切线必须存在），且形状仍闭合', () {
      // 工装的小窗是 200×400：可用宽 = 200 − 2×16 = 168，扣掉 pad ×2 后
      // trackW = 156，n = 4 → itemW = 39；而按住时透镜高 60 —— **宽比高还小**。
      // 水平胶囊在「宽 < 高」时数学上不成立（两个端头圆会重叠、外公切线不存在），
      // 这不是假想的，是算出来的。
      final s = LiquidLensShape.of(
          itemW: 39,
          capsuleH: 64,
          pad: 6,
          centerPage: 1,
          lift: 1,
          velocity: 0);
      expect(s.leftRadius + s.rightRadius, lessThanOrEqualTo(s.width + 0.001),
          reason: '两个端头圆重叠了 —— 外公切线不存在，Path 会画出乱形');
      expect(s.toPath().getBounds().isEmpty, isFalse);
    });

    test('轮廓落在该落的框里：竖直居中于胶囊中轴，宽度就是 width', () {
      // 这条钉住 `toPath()` 的坐标约定 —— 按住时 height > capsuleH，
      // 若按自己的 height/2 居中，凸出会全部跑到下面去。
      final s = at(lift: 1);
      final bounds = s.toPath().getBounds();
      expect(bounds.center.dy, closeTo(capsuleH / 2, 0.01), reason: '没竖直居中');
      expect(bounds.center.dx, closeTo(s.centerX, 0.01));
      expect(bounds.width, closeTo(s.width, 0.5));
      expect(bounds.height, closeTo(s.height, 0.5));
    });

    test('外壳连成一片：两枚端头圆之间的空隙被切线填上了', () {
      // 反面是「两个端头圆各画一个圈、中间没接上」—— 包围盒照样对，但中间是空的。
      //
      // **探针必须落在两圆之间的空隙里**，不能取形状正中央：拉伸时前缘圆变大，
      // 正中央其实落在**前缘圆内部**，两个圈分开画也照样判真（第一版就是这么
      // 写错的，靠下面第一条断言才看得出来）。
      //
      // 空隙的中点（在水平中轴上）：`c1.dx + rl` 与 `c2.dx − rr` 的均值，
      // 展开后 = `centerX + leftRadius − rightRadius`。
      final s = at(lift: 1, velocity: AppTokens.lensVelocityRef);
      expect(s.rightRadius, greaterThan(s.leftRadius),
          reason: '这一档本该是「前缘大、后缘小」（向右拖 → 右端是前缘），'
              '不然空隙不存在、这条白测');

      final double probeX = s.centerX + s.leftRadius - s.rightRadius;
      final double distanceToLeftCap =
          (probeX - (s.centerX - s.width / 2 + s.leftRadius)).abs();
      final double distanceToRightCap =
          (probeX - (s.centerX + s.width / 2 - s.rightRadius)).abs();
      expect(distanceToLeftCap, greaterThan(s.leftRadius),
          reason: '探针落进了左端圆里 —— 那样 `contains` 为真什么都说明不了');
      expect(distanceToRightCap, greaterThan(s.rightRadius),
          reason: '探针落进了右端圆里 —— 同上');

      final p = s.toPath();
      expect(p.contains(Offset(probeX, s.centerY)), isTrue,
          reason: '两圆之间的空隙是空的 —— 外公切线没把它们连起来');
      expect(p.contains(Offset(s.centerX, s.centerY - s.height / 2 - 2)), isFalse,
          reason: '形状外面那个点被判成在里面 —— 外壳封错了');
    });
  });

  // ── 渲染（光栅化，不是「有没有画东西」）─────────────────────────────────

  const Size canvas = Size(200, 120);
  const Size capsule = Size(120, 64);

  /// 把「一枚透镜盖在一块胶囊底上」光栅化成原始 RGBA。
  Future<List<int>> shotLens(
    WidgetTester tester, {
    required double lift,
    required Color accent,
    double velocity = 0,
  }) async {
    tester.view.physicalSize = canvas;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final GlobalKey key = GlobalKey();
    final shape = LiquidLensShape.of(
        itemW: capsule.width,
        capsuleH: capsule.height,
        pad: 0,
        centerPage: 0,
        lift: lift,
        velocity: velocity);
    final double top = (canvas.height - capsule.height) / 2;
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: canvas,
            child: Stack(clipBehavior: Clip.none, children: <Widget>[
              Positioned(
                left: 0,
                top: top,
                width: capsule.width,
                height: capsule.height,
                child: const ColoredBox(color: Color(0xFFF5F6FA)),
              ),
              Positioned(
                left: 0,
                top: top,
                width: capsule.width,
                height: capsule.height,
                child: LiquidLens(
                  size: capsule,
                  shape: shape,
                  lift: lift,
                  isDark: false,
                  accent: accent,
                ),
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late List<int> bytes;
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List()
          .toList();
      image.dispose();
    });
    return bytes;
  }

  int alphaAt(List<int> px, int x, int y) => px[(y * canvas.width.toInt() + x) * 4 + 3];

  testWidgets('按住时透镜凸出胶囊：外框之外上下各有非透明像素', (tester) async {
    final px = await shotLens(tester,
        lift: 1, accent: const Color(0xFF12B5A5));
    final int top = ((canvas.height - capsule.height) / 2).round();
    expect(alphaAt(px, 60, top - 2), greaterThan(0), reason: '没凸出胶囊上沿');
    expect(alphaAt(px, 60, top - 2), lessThan(255), reason: '凸出来的应该还是玻璃，不是实心块');
    expect(alphaAt(px, 60, top + capsule.height.toInt() + 1), greaterThan(0),
        reason: '没凸出胶囊下沿');
  });

  testWidgets('静止时不凸出：胶囊外框之外全是透明的', (tester) async {
    // 与上一条是一对 —— 缺了它，上一条可能因为别的原因（比如阴影）变绿。
    final px = await shotLens(tester,
        lift: 0, accent: const Color(0xFF12B5A5));
    final int top = ((canvas.height - capsule.height) / 2).round();
    expect(alphaAt(px, 60, top - 2), 0);
    expect(alphaAt(px, 60, top + capsule.height.toInt() + 1), 0);
  });

  /// 在某一列上、画布 y ∈ [from, to] 这一段里找最亮的那一行。
  int brightestRow(List<int> px, int x, int from, int to) {
    int best = -1, bestV = -1;
    for (int y = from; y <= to; y++) {
      final int v = px[(y * canvas.width.toInt() + x) * 4];
      if (v > bestV) {
        bestV = v;
        best = y;
      }
    }
    return best;
  }

  testWidgets('胶囊那条边被透镜折进去：亮带落在胶囊上沿之下', (tester) async {
    // 这一条替掉了计划里的「放大层」。原方案（`ImageFilter.matrix` 放大背景）
    // 被四条探针否掉：滤镜的坐标空间永远是**根坐标**，而 `LiquidLens` 不知道
    // 自己在屏幕上的绝对位置，底栏外面还套着一层会动的 `QScale`。
    // 换成自己画那条被折射的边 —— 在 1px 的宽度上读起来是同一件事。
    final int top = ((canvas.height - capsule.height) / 2).round();
    final px = await shotLens(tester,
        lift: 1, accent: const Color(0xFF12B5A5));
    expect(brightestRow(px, 60, top, top + 10), greaterThan(top + 1),
        reason: '透镜中心那一列上，最亮的还是胶囊上沿本身 —— 那条边没被折进去');
  });

  testWidgets('没凸出时没有这条折线（对照组）', (tester) async {
    // 缺了这条，上面那条可能只是「透镜自己的白描边正好落在下面一点」。
    final int top = ((canvas.height - capsule.height) / 2).round();
    final px = await shotLens(tester,
        lift: 0, accent: const Color(0xFF12B5A5));
    expect(brightestRow(px, 60, top, top + 10), lessThanOrEqualTo(top + 1),
        reason: '还没凸出就把胶囊的边折了 —— 静止时本该什么都不发生');
  });

  /// 透镜范围内，色相离 [from] 最远的那个像素偏了多少度。
  ///
  /// 只算**饱和度 > 0.25 且不透明**的像素：白色高光芯与那条被折射的边都是低饱和的，
  /// 它们的色相是不稳的（数值噪声），算进来会让这条断言变成抽奖。
  double maxHueDelta(List<int> px, Color from) {
    final double base = HSLColor.fromColor(from).hue;
    double worst = 0;
    for (int i = 0; i < px.length; i += 4) {
      if (px[i + 3] < 128) continue;
      final HSLColor c = HSLColor.fromColor(
          Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]));
      if (c.saturation < 0.25) continue;
      double d = (c.hue - base).abs() % 360;
      if (d > 180) d = 360 - d;
      if (d > worst) worst = d;
    }
    return worst;
  }

  /// 在某一列上数「带色相」的连续行数 —— 就是那一圈彩边的**厚度**。
  ///
  /// 沿透镜竖直中轴那一列往下扫：那里正好横穿透镜**上沿**那一段环。
  int ringThickness(List<int> px, int x, Color accent) {
    final double base = HSLColor.fromColor(accent).hue;
    int count = 0;
    bool started = false;
    for (int y = 0; y < canvas.height.toInt(); y++) {
      final int i = (y * canvas.width.toInt() + x) * 4;
      bool hit = false;
      if (px[i + 3] >= 128) {
        final HSLColor c =
            HSLColor.fromColor(Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]));
        if (c.saturation >= 0.25) {
          double d = (c.hue - base).abs() % 360;
          if (d > 180) d = 360 - d;
          hit = d > 25;
        }
      }
      if (hit) {
        count++;
        started = true;
      } else if (started) {
        break; // 连续的一段结束
      }
    }
    return count;
  }

  testWidgets('彩边只在**动**的时候亮：静止时一个彩色像素都没有', (tester) async {
    // 用户 2026-10-04：「彩虹边缘在滑块静态时不应该出现。只有运动起来的时候，
    // 它才会跟光线发生这些折射反应」。
    const accent = Color(0xFF12B5A5);
    final List<int> still = await shotLens(tester, lift: 1, accent: accent);
    expect(maxHueDelta(still, accent), lessThan(12),
        reason: '静止（速度 0）时还有彩色 —— 那圈彩虹不该出现');
  });

  testWidgets('动起来就走色相：速度满档时至少有像素离主色 30° 以上', (tester) async {
    // teal（色相约 174°）。本体那层染色无论多浓，色相都贴着主色（偏离 ≈ 0）——
    // 只有真**走了色相**的环才会把它顶到 30° 以上。所以这条不是「有没有画东西」，
    // 它分得开「走色相的环」与「给主色加了个亮边」。
    const accent = Color(0xFF12B5A5);
    final List<int> px = await shotLens(tester,
        lift: 1, accent: accent, velocity: AppTokens.lensVelocityRef);
    expect(maxHueDelta(px, accent), greaterThan(30),
        reason: '动了却不走色相 —— 那是「给主色加了个亮边」，不是走色相');
  });

  /// 带色相（离主色 > 25°）的像素总数 —— 彩边的**面积**。
  ///
  /// 用得比的「厚度」稳：周长一样，面积随线宽线性涨，而且基数是几百而不是个位数。
  int ringArea(List<int> px, Color accent) {
    final double base = HSLColor.fromColor(accent).hue;
    int n = 0;
    for (int i = 0; i < px.length; i += 4) {
      if (px[i + 3] < 128) continue;
      final HSLColor c = HSLColor.fromColor(
          Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]));
      if (c.saturation < 0.25) continue;
      double d = (c.hue - base).abs() % 360;
      if (d > 180) d = 360 - d;
      if (d > 25) n++;
    }
    return n;
  }

  testWidgets('彩边比上一版更宽（3px → 4.5px）', (tester) async {
    // 用户：「现在彩虹边缘的宽度太细了，不太容易察觉，需要再稍微加宽一点点」。
    // 量**面积**而不是「有没有」—— 3px 那版也过得了上面那条。
    const accent = Color(0xFF12B5A5);
    final List<int> px = await shotLens(tester,
        lift: 1, accent: accent, velocity: AppTokens.lensVelocityRef);
    final int area = ringArea(px, accent);
    // ignore: avoid_print
    print('[probe] 彩边面积 = $area 像素（厚度 ${ringThickness(px, 60, accent)}px）');
    // 标定过：3px 那版量到 **132**，4.5px 这版 **229**（厚度 2 → 3）。阈值取两者之间，
    // 所以退回 3px 会让这条变红。
    expect(area, greaterThanOrEqualTo(180),
        reason: '彩边的面积不够 —— 加宽没生效（3px 那版是 132）');
  });

  test('几何在任何尺寸 × 任何速度下都画得出东西（参数化扫一遍）', () {
    // **实测撞出来的 Critical**（独立审查抓的，我漏了）：
    // 端头半径取 `min(高, 宽)/2` 之后，只要 **宽 <= 高**，前后缘半径之差就
    // **恰好等于**圆心距 —— `mx` 正好是 1，外公切线塌成一条竖线，右端那段圆弧的
    // 扫描角正好是 **2π**，而 **`Path.arcTo` 在扫描角为 2π 时什么都不画**
    // （`sky_engine/lib/ui/painting.dart` 的文档写着）。于是整条路径面积为 0：
    // **透镜整个消失**，而且死区的边界由浮点舍入决定 —— 表现是拖动中**一闪一没**。
    //
    // 它落在哪些尺寸上：「宽 <= 高」即 `itemW + 10·lift <= 52 + 20·lift`，
    // 也就是 **itemW 小于约 62** 的窗口 —— 200×400 那个工装档（itemW 39）在
    // lift=1 时**一半的速度**都落在死区里。而按面积算，工装那份窄窗图里透镜
    // 贡献 0 像素。
    //
    // 原来那条窄窗用例只喂了 `velocity: 0`，正好落在 `d == 0` 那一个点上
    // （那条有 `addOval` 兜底），所以它是绿的。
    for (final double itemW in <double>[39, 45, 55, 60, 62, 64, 85, 90]) {
      for (final double capsuleH in <double>[52, 64]) {
        for (final double lift in <double>[0, 0.5, 1]) {
          for (double v = 0; v <= 1500; v += 25) {
            final LiquidLensShape s = LiquidLensShape.of(
                itemW: itemW,
                capsuleH: capsuleH,
                pad: 6,
                centerPage: 1,
                lift: lift,
                velocity: v);
            final ctx = 'itemW=$itemW 胶囊高=$capsuleH lift=$lift v=$v';
            expect(s.toPath().getBounds().isEmpty, isFalse,
                reason: '$ctx —— 路径是空的（面积为零），透镜整个画不出来');
            expect(s.toPath().contains(Offset(s.centerX, s.centerY)), isTrue,
                reason: '$ctx —— 形状正中央不在路径内，等于没画');
          }
        }
      }
    }
  });

  group('图标被透镜边缘影响', () {
    const double half = 50; // 透镜半宽
    ({double scaleX, double scaleY, double dx}) at(double iconX, double lensX) =>
        lensIconWarp(
            iconCenterX: iconX, lensCenterX: lensX, lensHalfWidth: half);

    test('透镜正中的图标几乎不变形（厚透镜中间是平的）', () {
      final w = at(100, 100); // t = 0
      expect(w.scaleX, closeTo(1, 0.01));
      expect(w.scaleY, closeTo(1, 0.01));
      expect(w.dx.abs(), lessThan(0.2));
    });

    test('正好在透镜边缘的图标变形最大', () {
      final w = at(150, 100); // t = 1
      expect(1 - w.scaleX, closeTo(AppTokens.lensIconPinch, 0.01));
      expect(w.dx, closeTo(AppTokens.lensIconPush, 0.1));
    });

    test('离透镜一个半宽以外的图标完全不动', () {
      // 这一条是「不影响显示」的保证：只有边缘那一圈有值。
      final w = at(250, 100); // t = 3
      expect(w.scaleX, 1.0);
      expect(w.scaleY, 1.0);
      expect(w.dx, 0.0);
    });

    test('推的方向永远朝远离透镜中心的那一侧', () {
      expect(at(150, 100).dx, greaterThan(0)); // 图标在右 → 往右推
      expect(at(50, 100).dx, lessThan(0)); // 图标在左 → 往左推
    });

    test('边缘两侧对称', () {
      final left = at(50, 100), right = at(150, 100);
      expect(left.scaleX, closeTo(right.scaleX, 1e-9));
      expect(left.dx, closeTo(-right.dx, 1e-9));
    });

    test('半宽非正（退化档）时什么都不做，不抛异常', () {
      final w = lensIconWarp(
          iconCenterX: 10, lensCenterX: 0, lensHalfWidth: 0);
      expect(w.scaleX, 1.0);
      expect(w.dx, 0.0);
    });
  });
}
