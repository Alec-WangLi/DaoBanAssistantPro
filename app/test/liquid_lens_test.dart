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

  test('同一段位移在任何帧率下算出同一个速度（16ms 地板会让它差近一倍）', () {
    // 120Hz 每帧 2.5px ≡ 60Hz 每帧 5px ≡ **300px/s**。两路必须给出同一个速度。
    //
    // 破坏它的是 `_onTick` 里原来的 `max(dt, 16ms)` 地板：16ms 正好是**一帧 60Hz**，
    // 于是在 120Hz 上 dt 被抬到 16ms、速度被算成真实值的一半（156 vs 300）；
    // 而帧间隔一旦在 8.33 / 16.7 之间跳（可变刷新率），同一根手指就算出两个
    // 拉伸量 —— 用户 2026-10-05 说的「像帧率不够」有一半来自这里。
    // 这台机器正是 120Hz，所以这个地板**一直在生效**。
    //
    // **反向验证**：把地板加回 `lensVelocityStep`，这条立刻红（120Hz 那路掉到 156）。
    const double itemW = 90;
    double steady(double pxPerFrame, Duration dt) {
      double v = 0;
      for (int i = 0; i < 40; i++) {
        v = lensVelocityStep(
            deltaPage: pxPerFrame / itemW, itemW: itemW, dt: dt, previous: v);
      }
      return v;
    }

    final double at120 = steady(2.5, const Duration(microseconds: 8333));
    final double at60 = steady(5.0, const Duration(microseconds: 16667));
    expect(at120, closeTo(300, 1));
    expect(at60, closeTo(300, 1));
    expect((at120 - at60).abs() / at60, lessThan(0.02),
        reason: '120Hz 算出 $at120、60Hz 算出 $at60 —— 速度跟帧率绑在一起了');
  });

  test('dt 为 0 时返回上一帧的值（不拿假 dt 去凑，也不抛）', () {
    expect(
        lensVelocityStep(
            deltaPage: 0.5, itemW: 90, dt: Duration.zero, previous: 42),
        42);
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

    test('拖动时凸出不许被形变吃掉：满升程 + 任何速度下都高于胶囊', () {
      // 用户 2026-10-05 报「形状变化僵硬」，底下其实是一个**几何缺陷**。
      //
      // 原式是 `(基准 + 2·凸出·lift) × (1 − squash·s)` —— 压扁**乘在凸出上**。
      // 实测（扫出来的）：squash 还是 0.12 的版本里，lift=1 / 700px/s 时透镜高
      // **63.4**，而胶囊高 **64**：**透镜整个沉回胶囊里面**，按住拖动时
      // 「一枚浮起来的玻璃滴」直接掉回「一枚躺着药丸」——「按住」这个动作的
      // 全部读感就在那零点几个像素上。
      //
      // 修法是让外扩**加在压扁之后的基准上**，不许与形变相乘。
      for (double v = 0; v <= 2000; v += 25) {
        final s = at(lift: 1, velocity: v);
        expect(s.height, greaterThan(capsuleH),
            reason: 'lift=1 / v=$v 时透镜高 ${s.height} ≤ 胶囊高 $capsuleH —— '
                '沉回胶囊里了，「提起」的信号没了');
      }
    });

    test('凸出量恒等于 2×navLensProtrude，**与速度无关**（乘法顺序的守卫）', () {
      // 上面那条只断言「还高于胶囊」—— 它**抓不住乘法顺序**：squash 从 0.12 收到
      // 0.08 之后，就算把乘法顺序改回去，满速下也还剩 66.2 > 64，照样绿。
      // （第一版就是这么写的，反向验证时才现形。）
      //
      // 真正的不变量是**差值**：外扩是加在压扁之后的基准上的，所以
      // 「lift=1 的高 − lift=0 的高」恒等于 2×protrude，**跟 s 一点关系都没有**。
      // 乘进去的话这个差会随 s 缩水（`20 × (1 − squash·s)`）。
      for (final double s in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
        final double v = s * AppTokens.lensVelocityRef;
        final up = at(lift: 1, velocity: v);
        final down = at(lift: 0, velocity: v);
        expect(up.height - down.height,
            closeTo(2 * AppTokens.navLensProtrude, 0.001),
            reason: 's=$s 时凸出只剩 ${up.height - down.height} —— '
                '压扁又乘在凸出上了');
      }
    });

    test('折边：按住时**任何速度下**都画得出来（它原来在高速下整个消失）', () {
      // 这条钉的是一个「洞」，不是手感：原早退条件是「**两个端头半径都**大于胶囊
      // 半高」，而速度一上来后缘半径（`×(1 − 0.35·stretch)`）必然先掉下去 ——
      // 于是整条折边被一票否决。实测 lift=1 时超过约 150px/s 它就完全消失，
      // 而常态拖动是 300~1000px/s：**这个效果只在「按住而且手指不动」时存在**，
      // 恰好是唯一不会去拖的状态。用户说的「僵硬、像帧率不够」有一半来自这个
      // 忽有忽无的开关。
      for (double v = 0; v <= 2000; v += 25) {
        final e = refractedCapsuleEdge(at(lift: 1, velocity: v));
        expect(e, isNotNull, reason: 'lift=1 / v=$v —— 折边不画了');
        expect(e!.xR - e.xL, greaterThan(10),
            reason: 'lift=1 / v=$v 跨度只有 ${e.xR - e.xL}');
        expect(e.fade, greaterThan(0.2),
            reason: 'lift=1 / v=$v 淡入只剩 ${e.fade} —— 太淡就等于没有');
      }
    });

    test('折边：没按住时一定不画（对照组）', () {
      // 缺了这条，上面那条可能因为别的原因变绿（例如门被开得过宽）。
      for (double v = 0; v <= 2000; v += 50) {
        expect(refractedCapsuleEdge(at(lift: 0, velocity: v)), isNull,
            reason: 'lift=0 / v=$v —— 没凸出就把胶囊的边折了');
      }
    });

    test('折边：凸出越多越鼓、越实（不是开关）', () {
      // 「不再啪地出现」的可断言形式：淡入是**连续**的，不是 0/1。
      final mid = refractedCapsuleEdge(at(lift: 0.8, velocity: 0))!;
      final full = refractedCapsuleEdge(at(lift: 1, velocity: 0))!;
      expect(mid.fade, lessThan(full.fade),
          reason: '凸出更少却一样实 —— 那是开关，回到「啪地出现」了');
      expect(mid.bow, lessThan(full.bow));
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
    double? stretch,
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
        velocity: velocity,
        stretch: stretch);
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

  testWidgets('彩边是「光晕」不是「等宽的带」：带色相的厚度远大于那条细线', (tester) async {
    // 用户 2026-10-06：「现在给我的感觉就像在这个滑块的边缘加了一层彩带一样。
    // 我们想要的是加一层折射的光晕。」
    //
    // 「彩带」最硬的那条判据就是**等宽** —— 原来那条 4.5px 的彩色描边量出来厚度
    // 就是 2px（贴边那一条）。光晕是从边缘往里化开的一层，所以带色相的厚度必须
    // **明显大于那条线本身**（现在线是 2.4px）。
    //
    // 标定：上一版（纯描边）**面积 277 / 厚度 2**；这一版 **2092 / 7**。
    const accent = Color(0xFF12B5A5);
    final List<int> px = await shotLens(tester,
        lift: 1, accent: accent, velocity: AppTokens.lensVelocityRef);
    final int area = ringArea(px, accent);
    final int thickness = ringThickness(px, 60, accent);
    // ignore: avoid_print
    print('[probe] 彩边面积 = $area 像素（厚度 ${thickness}px）');
    expect(thickness, greaterThan(AppTokens.lensRingWidth * 1.8),
        reason: '带色相的厚度只有 ${thickness}px，与那条线'
            '（${AppTokens.lensRingWidth}px）同量级 —— 又回到「一条等宽的彩带」了');
    expect(area, greaterThanOrEqualTo(1200),
        reason: '彩边的面积不够 —— 光晕那两层没生效（纯描边那版是 277）');
  });

  testWidgets('彩边「一动就满」：形状一模一样时，60px/s 已和满速一样亮', (tester) async {
    // 用户 2026-10-05：「彩色边缘不明显，还是恢复成一动就直接达到满效果吧。
    // 现在是跟随速度越快效果才越明显，但这样几乎看不出来。本来它这个效果范围
    // 就不大，所以还是直接生效到最大效果吧。」
    //
    // 原来环的亮度是 `× stretch`（= 速度 / lensVelocityRef）—— 要甩到满速才满亮，
    // 而常态拖动就在那个数上下，于是它长期停在半亮，等于一直是淡的。现在门换成了
    // `motion`：`lensRingFullSpeed`（60px/s）就封顶。
    //
    // **把 `stretch` 固定成 0 是关键**：形状因此完全不动、周长没有变化，三次取样
    // 之间**只有门在变**。不固定的话，「v 大 → 形状被拉长 → 周长更大 → 面积更大」
    // 会让这条断言变成一个恒真的空话。
    //
    // **反向验证**：把 `_paintSpectralRing` 的乘数改回 `shape.stretch`，这条立刻红
    // （60px/s 那档会掉到近乎 0）。
    const accent = Color(0xFF12B5A5);
    final List<int> still =
        await shotLens(tester, lift: 1, accent: accent, stretch: 0);
    final List<int> slow = await shotLens(tester,
        lift: 1, accent: accent, velocity: AppTokens.lensRingFullSpeed,
        stretch: 0);
    final List<int> fast = await shotLens(tester,
        lift: 1, accent: accent, velocity: AppTokens.lensVelocityRef * 3,
        stretch: 0);

    expect(ringArea(still, accent), 0, reason: '静止时还有彩色 —— 那圈彩虹不该出现');
    expect(ringArea(slow, accent), greaterThan(0), reason: '动起来了却不亮');
    expect(ringArea(slow, accent),
        greaterThanOrEqualTo((ringArea(fast, accent) * 0.95).round()),
        reason: '60px/s 还没到满效果（${ringArea(slow, accent)} vs '
            '${ringArea(fast, accent)}）—— 门又在跟速度大小走了');
  });

  /// 两帧在 [center] 附近（半径 [r] 的方框内）有多少个像素**肉眼可见地**不一样。
  ///
  /// [minDelta] 是单通道的可见门槛，与 `scripts/diff_visual.py` 同一个值（8）。
  /// **不设门槛的话这条判据没有鉴别力** —— 环的底面即使压到 0.06，也还是会让像素
  /// 动 1~2 级，`a[i] != b[i]` 照样为真（第一版就是这么写的，反向验证时才发现）。
  ///
  /// **也别用「色相偏离主色」来判**：色相沿轮廓走 300°，在**正右那一点正好绕回
  /// 主色**，色相偏离恒为 0。判「看不看得见」的正确量法是**与「不画环」那一帧
  /// 做差**，且带一个可见门槛。
  int diffNear(List<int> a, List<int> b, Offset center,
      {int r = 6, int minDelta = 8}) {
    int n = 0;
    for (int y = (center.dy - r).round(); y <= (center.dy + r).round(); y++) {
      for (int x = (center.dx - r).round(); x <= (center.dx + r).round(); x++) {
        if (x < 0 || y < 0 || x >= canvas.width || y >= canvas.height) continue;
        final int i = (y * canvas.width.toInt() + x) * 4;
        int d = 0;
        for (int c = 0; c < 3; c++) {
          final int v = (a[i + c] - b[i + c]).abs();
          if (v > d) d = v;
        }
        if (d >= minDelta) n++;
      }
    }
    return n;
  }

  /// 透镜在 `shotLens` 那张画布里的几何（都是算出来的，不是估的）：
  /// itemW = 胶囊宽 120、pad 0、centerPage 0 → 中心在画布 (60, 28 + 32)；
  /// lift=1 / 满形变时半宽 `120×1.2+10 ÷ 2 = 77`、半高 `(64×0.92+20) ÷ 2 = 39.4`。
  const Offset lensCenter = Offset(60, 60);
  const double lensHalfW = 77, lensHalfH = 39.4;

  testWidgets('彩边四面八方都有颜色：右边与下边不许是空的', (tester) async {
    // 用户 2026-10-06：「不管我往左滑还是往右滑，感觉只有左边和上边有彩边，
    // 右边和下边缘都没有。」
    //
    // 根因在算式里：`α = (0.06 + 0.86·toward²) · motion`，而 `toward` 的峰值
    // 锚在 225°（左上）、并且**又平方了一次**。代进八个方位：
    //   左上 **0.92** / 左 0.69 / 上 0.69 / 右上 0.28 / 左下 0.28 /
    //   右 **0.08** / 下 **0.08** / 右下 **0.06** —— 后三档等于没有颜色。
    // 它画在**固定的屏幕方位**上，所以与往哪边滑无关（用户观察到的正是这一点，
    // 也是这条判据的鉴别力所在：跟着运动方向走的写法过不了这一组）。
    //
    // 量法：与**同一枚透镜但不画环**的那一帧做差 —— 有差 = 那里看得见。
    //
    // ⚠️ **对照帧必须把 `stretch` 显式钉住、速度只留一个正值**（第一版写的是
    // `velocity: 0`，那会**连带把形状也改掉**，于是两帧到处都不一样、这条判据
    // 变成永远为真 —— 反向验证时才发现）。`movingRight` 也要一致，所以速度取 1
    // 而不是 0：`motion` 只有 0.017，落在 0.05 那道门之下 = 不画。
    const accent = Color(0xFF12B5A5);
    final List<int> on = await shotLens(tester,
        lift: 1, accent: accent, velocity: AppTokens.lensVelocityRef,
        stretch: 1);
    final List<int> off = await shotLens(tester,
        lift: 1, accent: accent, velocity: 1, stretch: 1);
    for (final MapEntry<String, Offset> e in <String, Offset>{
      '右': Offset(lensCenter.dx + lensHalfW, lensCenter.dy),
      '下': Offset(lensCenter.dx, lensCenter.dy + lensHalfH),
      '右下': Offset(lensCenter.dx + lensHalfW * 0.7,
          lensCenter.dy + lensHalfH * 0.7),
      '右上': Offset(lensCenter.dx + lensHalfW * 0.7,
          lensCenter.dy - lensHalfH * 0.7),
      '上': Offset(lensCenter.dx, lensCenter.dy - lensHalfH), // 对照组：本来就有
    }.entries) {
      expect(diffNear(on, off, e.value), greaterThan(0),
          reason: '${e.key}边一个像素都没被彩边影响 —— 彩边又被锚在左上那一侧了');
    }
  });

  testWidgets('光晕往**外**也散一点：轮廓之外也受影响', (tester) async {
    // 用户 2026-10-06：「往外也散一点」。这一档必须画在裁剪**之外**才有 ——
    // 本体那层挂在 `ClipPath` 底下，外半边会被裁掉（那就是「只往内散」的实现方式）。
    const accent = Color(0xFF12B5A5);
    final List<int> on = await shotLens(tester,
        lift: 1, accent: accent, velocity: AppTokens.lensVelocityRef,
        stretch: 1);
    final List<int> off = await shotLens(tester,
        lift: 1, accent: accent, velocity: 1, stretch: 1);
    // 轮廓右侧外 6px 一小块：本体够不到那里，只有外溢光晕能到。
    expect(diffNear(on, off, Offset(lensCenter.dx + lensHalfW + 6, lensCenter.dy),
            r: 4),
        greaterThan(0),
        reason: '轮廓外一点都没变 —— 外溢那层没画（或被裁掉了）');
  });

  testWidgets('静止时轮廓外的像素与主色无关（光晕没在静止时画）', (tester) async {
    // 两帧只有主色不同、几何完全一样。**静止时不画环也不画光晕**，所以轮廓外
    // 那些像素不该随主色变 —— 变了就说明有东西在静止时漏出来了。
    final List<int> teal =
        await shotLens(tester, lift: 1, accent: const Color(0xFF12B5A5));
    final List<int> orange =
        await shotLens(tester, lift: 1, accent: const Color(0xFFF08800));
    expect(
        diffNear(teal, orange, Offset(lensCenter.dx + lensHalfW + 6, lensCenter.dy),
            r: 4),
        0,
        reason: '静止时轮廓外还随主色变 —— 那圈光晕没跟着 motion 一起灭');
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
