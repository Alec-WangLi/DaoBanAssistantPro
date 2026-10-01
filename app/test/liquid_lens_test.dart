// 透镜的弹簧解算器。
//
// 为什么不用 `TweenAnimationBuilder`：透镜要的不是「从 A 到 B 的一段补间」，
// 而是两样补间给不了的东西 ——
//   · **速度**：拖动时形状要跟着速度拉伸（Q 弹），速度得从解算器里读；
//   · **过冲**：松手落回格子那一下要越过一点再回来，那才是「Q 弹」。
//
// 纯 Dart、没有 widget 依赖，所以可以直接跑 200 步去断言它的行为。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_metrics.dart';
import 'package:shiftassistantpro/core/widgets/lens_warped_cell.dart';

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

  test('位置滑过去约 200ms —— **比标准档慢一档**（用户 2026-10-01 选的）', () {
    // ⚠️ **这条判据与上一版相反**：上一版钉的是「与标准档的 durFast（120ms）相当」，
    // 那是照用户反馈第 6 条「没有标准档那种缓慢优雅」定的。2026-10-01 用户说
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
    // 拉伸量 —— 用户 2026-10-01 说的「像帧率不够」有一半来自这里。
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

    test('几何默认值 = 底栏那档（10 / 10）—— 既有调用点的渲染一个字都不许变', () {
      // 这一条是「底栏逐像素不变」那条验收的地基：不给 `metrics` 时，行为必须与抽
      // 共享件之前**完全一样**。
      //
      // ⚠️ 矮屏那一档胶囊是 **52 高**，而它现在用的**也是 10 / 10** —— 几何参数化时
      // 若图省事写成「按胶囊高度取」，52 会变成 8.1，横屏与小窗两档的画面就变了。
      final s = LiquidLensShape.of(
          itemW: 90, capsuleH: 52, pad: 6, centerPage: 0, lift: 1, velocity: 0);
      expect(s.height, closeTo(52 - 12 + 2 * AppTokens.navLensProtrude, 0.001));
      expect(s.width, closeTo(90 + AppTokens.lensLiftWidth, 0.001));
    });

    test('metrics 真的进几何：protrude 只管纵向、liftWidth 只管横向', () {
      final s = LiquidLensShape.of(
          itemW: 20,
          capsuleH: 28,
          pad: 3,
          centerPage: 0,
          lift: 1,
          velocity: 0,
          metrics: const LiquidLensMetrics(protrude: 8, liftWidth: 0));
      expect(s.height, closeTo(22 + 16, 0.001)); // 基准 28−6，上下各探出 8
      expect(s.width, closeTo(20, 0.001)); // itemW，横向一点都不外扩
    });

    test('forCapsule 按高度取；底栏那一档与常量一致', () {
      expect(LiquidLensMetrics.forCapsule(64).protrude, closeTo(10, 0.001));
      expect(LiquidLensMetrics.forCapsule(64).liftWidth, closeTo(10, 0.001));
      expect(LiquidLensMetrics.forCapsule(40).protrude, closeTo(6.25, 0.001));
      expect(LiquidLensMetrics.forCapsule(40).liftWidth, closeTo(6.25, 0.001));
    });

    test('forCapsule 顺带导出彩边缩放；不给 metrics 时是 1.0（底栏那一档）', () {
      // 用户 2026-10-01：「既然这个开关是小的，那彩边范围自然也要自适应变小」。
      // 那四个宽度（10 / 6 / 8 / 2.4px）是照 **64 高**的胶囊量的常量，分母就在这里。
      expect(LiquidLensMetrics.forCapsule(64).rimScale, closeTo(1.0, 0.001));
      expect(LiquidLensMetrics.forCapsule(40).rimScale, closeTo(0.625, 0.001));
      expect(LiquidLensMetrics.forCapsule(30).rimScale, closeTo(0.46875, 0.001));
      // 底栏显式写死两个外扩量（不走 forCapsule）时，也必须是 1.0 ——
      // 矮屏那一档胶囊只有 52 高，跟着缩会改到横屏与小窗的画面。
      expect(
          const LiquidLensMetrics(protrude: 10, liftWidth: 10).rimScale, 1.0);
      expect(
          LiquidLensShape.of(
                  itemW: 90,
                  capsuleH: 52,
                  pad: 6,
                  centerPage: 0,
                  lift: 1,
                  velocity: 0)
              .rimScale,
          1.0);
    });

    test('velocityRef 默认就是全局那一档（底栏与分段器必须不变）', () {
      // 它下放成**每面的数**是这一轮才做的：形变强度走「位置的真实帧间差分 ÷
      // velocityRef」，而一格多宽决定了同一个手势能走几帧 —— 底栏一格 88px，
      // 800px/s 走 7 帧、峰值形变 0.77；开关一格 25px，同样 800px/s 只走 2 帧、
      // 峰值 0.22（**越快反而越短**）。全局那一档在 25px 的轨道上够不着。
      expect(const LiquidLensMetrics(protrude: 10, liftWidth: 10).velocityRef,
          AppTokens.lensVelocityRef);
      expect(LiquidLensMetrics.forCapsule(30).velocityRef,
          AppTokens.lensVelocityRef);
    });

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
      // 用户 2026-10-01 报「形状变化僵硬」，底下其实是一个**几何缺陷**。
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
    double? motion,
    List<Color>? fill,
    bool showRingCore = true,
    bool showRefractedEdge = true,
    LiquidLensMetrics? metrics,
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
        stretch: stretch,
        motion: motion,
        metrics: metrics);
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
                  fill: fill,
                  showRingCore: showRingCore,
                  showRefractedEdge: showRefractedEdge,
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

  testWidgets('本体填充可换：白玻璃与主色渐变必须是两幅像素', (tester) async {
    // 开关那枚钮是**白玻璃球**（底栏 / 分段器是主色玻璃滴）—— 压在淡染轨道上，
    // 主色玻璃滴会糊成一片。所以本体填充必须能换。
    const accent = Color(0xFF12B5A5);
    final List<int> tinted = await shotLens(tester, lift: 0, accent: accent);
    final List<int> white = await shotLens(tester, lift: 0, accent: accent,
        fill: <Color>[Colors.white, Colors.white]);
    int at(List<int> px, int x, int y, int c) =>
        px[(y * canvas.width.toInt() + x) * 4 + c];
    // 本体正中（透镜中心 = (60, 60)，见 shotLens 的几何）
    int worst = 0;
    for (int c = 0; c < 3; c++) {
      final int d = (at(tinted, 60, 60, c) - at(white, 60, 60, c)).abs();
      if (d > worst) worst = d;
    }
    expect(worst, greaterThan(20),
        reason: '换了 fill 本体却没变（最大差 $worst）—— 参数没接到 painter 上');
  });

  testWidgets('白芯可以关掉（白本体上它是一条看不见的线）', (tester) async {
    const accent = Color(0xFF12B5A5);
    final int top = ((canvas.height - capsule.height) / 2).round();
    int brightest(List<int> px) {
      int best = 0;
      for (int y = top - 2; y <= top + 4; y++) {
        final int v = px[(y * canvas.width.toInt() + 60) * 4];
        if (v > best) best = v;
      }
      return best;
    }

    final List<int> on = await shotLens(tester, lift: 0, accent: accent);
    final List<int> off = await shotLens(tester, lift: 0, accent: accent,
        showRingCore: false);
    expect(brightest(on), greaterThan(brightest(off) + 10),
        reason: '关掉白芯之后轮廓一点没暗 —— 参数没接到 painter 上');
  });

  testWidgets('折边可以关掉（小控件上它是几道乱弧）', (tester) async {
    const accent = Color(0xFF12B5A5);
    final int top = ((canvas.height - capsule.height) / 2).round();
    final List<int> on =
        await shotLens(tester, lift: 1, accent: accent);
    final List<int> off = await shotLens(tester, lift: 1, accent: accent,
        showRefractedEdge: false);
    expect(brightestRow(on, 60, top, top + 10), greaterThan(top + 1),
        reason: '这一档本来就该有折边 —— 前提不成立，这条测不出东西');
    expect(brightestRow(off, 60, top, top + 10), lessThanOrEqualTo(top + 1),
        reason: '关掉折边之后那条亮带还在 —— 参数没接到 painter 上');
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

  // `ringThickness`（数「带色相的连续行数」）在 v0.10.8 删掉了：光晕收小之后
  // 它量出来只有 3px，与那条 2.4px 的细线同量级 —— **没有鉴别力了**。
  // 现在改判「往轮廓里有没有衰减」，见下面那条的剖面表。

  testWidgets('彩边只在**动**的时候亮：静止时一个彩色像素都没有', (tester) async {
    // 用户 2026-10-01：「彩虹边缘在滑块静态时不应该出现。只有运动起来的时候，
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

  testWidgets('彩边随尺寸缩：rimScale 小一档，带色相的像素面积必须明显更小', (tester) async {
    // 用户 2026-10-01：「既然这个开关是小的，那彩边范围自然也要自适应变小」。
    // 那四个宽度是照 64 高胶囊量的常量；原样搬到 30 高的开关上，内晕（10px）比钮
    // 本身还粗 —— 用户看到的是「像两个半圆一样」（轮廓的上半个圆 + 下半个圆各被
    // 一道过宽的光晕糊成一团）。
    //
    // **反向验证**：把五处乘法去掉，两档面积相等，这条立刻红。
    const Color accent = Color(0xFF5B5BD6);
    Future<int> areaAt(double rimScale) async {
      final List<int> px = await shotLens(tester,
          lift: 1,
          accent: accent,
          velocity: AppTokens.lensVelocityRef,
          stretch: 1,
          metrics:
              LiquidLensMetrics(protrude: 10, liftWidth: 10, rimScale: rimScale),
          showRingCore: false,
          showRefractedEdge: false);
      return ringArea(px, accent);
    }

    final int big = await areaAt(1.0);
    final int small = await areaAt(0.469);
    expect(big, greaterThan(0), reason: '满速下一像素彩色都没有 —— 几何假设变了');
    expect(small / big, lessThan(0.75),
        reason: '彩边没跟着尺寸缩（1.0 档 $big 像素、0.469 档 $small 像素）—— '
            '那道 10px 的内晕在小控件上比控件本身还粗');
  });

  testWidgets('外圈那几层一起缩：rimScale 小的不透明像素更少', (tester) async {
    // 浮起阴影的偏移与模糊同样是常量，是「占满整个轨道」的另一半来源 —— 它跟着
    // `rimScale` 一起缩。
    //
    // ⚠️ **能挡住的只是「整组都忘了缩」**，挡不住「少缩了其中一层」（只缩四层光谱、
    // 漏掉阴影，这条仍然绿）。要分辨后者只能出图看 —— 样图里那圈灰晕最明显。
    const Color accent = Color(0xFF5B5BD6);
    Future<int> inked(double rimScale) async {
      final List<int> px = await shotLens(tester,
          lift: 1,
          accent: accent,
          metrics:
              LiquidLensMetrics(protrude: 10, liftWidth: 10, rimScale: rimScale));
      int n = 0;
      for (int i = 3; i < px.length; i += 4) {
        if (px[i] > 8) n++;
      }
      return n;
    }

    final int big = await inked(1.0);
    final int small = await inked(0.469);
    expect(small, lessThan(big),
        reason: '外圈那几层没缩（1.0 档 $big 个不透明像素、0.469 档 $small 个）');
  });

  testWidgets('彩边是「光晕」不是「等宽的带」：颜色往轮廓里会衰减', (tester) async {
    // 用户 2026-10-01：「现在给我的感觉就像在这个滑块的边缘加了一层彩带一样。
    // 我们想要的是加一层折射的光晕。」
    //
    // 「彩带」的判据是**等宽**，但量「厚度」这件事在光晕收小之后就不再有鉴别力了
    // （10px 的晕量出来只有 3px，与那条 2.4px 的细线同量级）。真正区分两者的是
    // **往轮廓里有没有衰减**：一条等宽的带要么到某处突然没了、要么处处一样亮；
    // 光晕则是「贴边最亮、往里化开」。
    //
    // **反向验证**：把光晕换成一条等亮度的描边，`d(edge+8)` 会掉到 0 或与边缘相等，
    // 这条立刻红。
    const accent = Color(0xFF12B5A5);
    final List<int> on = await shotLens(tester,
        lift: 1, accent: accent, velocity: AppTokens.lensVelocityRef, stretch: 1);
    final List<int> off = await shotLens(tester,
        lift: 1, accent: accent, velocity: 1, stretch: 1);

    // 轮廓上沿在 x = 60 那一列上的位置：直接用形状问，不靠估。
    final LiquidLensShape shape = LiquidLensShape.of(
        itemW: 120, capsuleH: 64, pad: 0, centerPage: 0, lift: 1,
        velocity: AppTokens.lensVelocityRef, stretch: 1);
    final Path path = shape.toPath();
    int edgeY = 0;
    for (int y = 0; y < 120; y++) {
      if (path.contains(Offset(60, y - 28))) {
        edgeY = y;
        break;
      }
    }
    expect(edgeY, greaterThan(0), reason: '没找到轮廓上沿 —— 几何假设变了，这条要重写');

    int delta(int y) {
      final int i = (y * canvas.width.toInt() + 60) * 4;
      int d = 0;
      for (int c = 0; c < 3; c++) {
        final int v = (on[i + c] - off[i + c]).abs();
        if (v > d) d = v;
      }
      return d;
    }

    final int atEdge = delta(edgeY + 1);
    final int at5 = delta(edgeY + 5);
    final int at8 = delta(edgeY + 8);
    final String profile = <int>[1, 3, 5, 6, 8, 10, 12]
        .map((int k) => '$k:${delta(edgeY + k)}')
        .join('  ');
    // ignore: avoid_print
    print('[probe] 剖面 $profile');
    // **往里 5px 那一点才有鉴别力**（两版实测的剖面）：
    //   真实现（糊开） 1:139  3:64  5:**23**  6:17  8:9  10:2
    //   拍扁成硬带     1:163  3:61  5:** 2**  6: 2  8:1  10:1
    // 差 11 倍，而且两者的**边缘值几乎一样** —— 所以判据必须取在「往里一点」：
    // 只看边缘、或只看「往里 8px > 0」（硬带在那里也是 1）都蒙混得过去。
    expect(atEdge, greaterThan(30), reason: '边缘没有颜色');
    expect(at5, greaterThan(10),
        reason: '往里 5px 只剩 $at5 —— 那是「一条等宽的硬带」（实测硬带在这里是 2），'
            '不是从边缘往里化开的光晕');
    expect(at8, lessThan((atEdge * 0.5).round()),
        reason: '往里 8px 还和边缘一样亮 —— 等宽 = 彩带');
    expect(ringArea(on, accent), greaterThanOrEqualTo(700),
        reason: '带色相的总量太少 —— 光晕那两层没生效（纯描边那版是 277）');
  });

  testWidgets('彩边「一动就满」：形状一模一样时，60px/s 已和满速一样亮', (tester) async {
    // 用户 2026-10-01：「彩色边缘不明显，还是恢复成一动就直接达到满效果吧。
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
    // 用户 2026-10-01：「不管我往左滑还是往右滑，感觉只有左边和上边有彩边，
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
    // 用户 2026-10-01：「往外也散一点」。这一档必须画在裁剪**之外**才有 ——
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

  testWidgets('四层都跟着亮度走：motion=0.3 留下的痕迹约为满档的三成', (tester) async {
    // 用户 2026-10-01：「彩边出现得太突然了……一动它就突然出来了。」
    // **「突然」的主要来源不是那条细彩线，而是光晕那两层与外溢那层** —— 它们原先
    // 只在 `motion > 0.05` 那道门上被一刀切开，一过门就是满亮度。这条单独钉它们。
    //
    // **反向验证过**：把 `_paintHalo` 那两层的 `* shape.motion` 去掉，比值会变成
    // 1.0（一过门就满），这条立刻红。
    const accent = Color(0xFF12B5A5);
    final List<int> off = await shotLens(tester,
        lift: 1, accent: accent, velocity: 1, stretch: 1, motion: 0);
    final List<int> dim = await shotLens(tester,
        lift: 1, accent: accent, velocity: 1, stretch: 1, motion: 0.3);
    final List<int> full = await shotLens(tester,
        lift: 1, accent: accent, velocity: 1, stretch: 1, motion: 1);
    int worst(List<int> a, List<int> b) {
      int d = 0;
      for (int i = 0; i < a.length; i += 4) {
        for (int c = 0; c < 3; c++) {
          final int v = (a[i + c] - b[i + c]).abs();
          if (v > d) d = v;
        }
      }
      return d;
    }

    final int dFull = worst(full, off);
    final int dDim = worst(dim, off);
    // ignore: avoid_print
    print('[probe] 满档最大差 = $dFull，三成档 = $dDim');
    expect(dFull, greaterThan(60), reason: '满档都没留下痕迹 —— 这条测不出东西');
    // 实测 0.43（不是 0.30）：四层是**叠**出来的，合成后的差不是严格线性。
    // 要钉住的只是「它确实跟着亮度走」—— 漏乘一层会把它推到 1.0 附近。
    expect(dDim / dFull, inInclusiveRange(0.2, 0.65),
        reason: '亮度没跟着 motion 走（$dDim/$dFull'
            ' = ${(dDim / dFull).toStringAsFixed(2)}）—— 有一层漏乘了');
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

  // ── 竖直档的折边（v0.10.13）───────────────────────────────────────────────
  //
  // 响铃页那枚「上滑关闭」的药丸是**竖着走**的滴 —— 它落进 `toPath()` 的竖直档
  // （`宽 ≤ 高`）。那一档此前有两个缺陷让折边**一次都不会亮**（spec §4）：
  //
  //   1. `refractedCapsuleEdge` 用的是**沿运动轴**的半径，而竖直档里那个半径被
  //      兜底钳位 `_cap = min(高, 宽) / 2` 卡住，`reach = max(rl, rr) − cy` 恒为负；
  //   2. 竖直档那枚滴其实是**椭圆**（不是「两个圆 + 外公切线」），横向那套弦长算式
  //      会把两个圆心算到对方的另一侧、得出一小段挤在正中间的弧。
  //
  // 前两条钉住修好之后的行为，第三条钉住**横向档没被带坏** —— 底栏与分段器走的是
  // 横向档，它们有「逐像素不变」的验收，这条就是那件事的可断言形式。

  /// 响铃页那枚药丸的几何：局部 `itemW 38 / capsuleH 72 / pad 10`。
  LiquidLensShape pillShape({double lift = 1, double stretch = 0}) =>
      LiquidLensShape.of(
        itemW: 38,
        capsuleH: 72,
        pad: 10,
        centerPage: 0,
        lift: lift,
        velocity: 0,
        stretch: stretch,
        metrics: const LiquidLensMetrics(
            protrude: 16, liftWidth: 6, rimScale: 0.7, velocityRef: 300),
      );

  test('竖直档：折边会亮（这条以前永远为 null）', () {
    final shape = pillShape();
    expect(shape.width <= shape.height, isTrue, reason: '前提错了：这一档应当是竖直档');
    final e = refractedCapsuleEdge(shape);
    expect(e, isNotNull, reason: '竖直档的折边算出来是 null —— 边永远折不了');
    expect(e!.fade, greaterThan(0));
  });

  test('竖直档：折边的弦长是椭圆那条，不是横向那套', () {
    final shape = pillShape();
    final e = refractedCapsuleEdge(shape)!;
    // 椭圆在边线（局部 y = 0 / capsuleH）上的弦长 = 宽 · √(1 − (2·cy/高)²)。
    final double k = 2 * shape.centerY / shape.height;
    final double expected = shape.width * math.sqrt(1 - k * k);
    expect(e.xR - e.xL, closeTo(expected, 0.5));
    expect(e.xL + e.xR, closeTo(2 * shape.centerX, 0.5), reason: '两端不对称');
  });

  test('横向档：横轴半径与原来那个逐值相等（底栏不受影响的可断言形式）', () {
    // 底栏那一档：itemW 88 / capsuleH 64 / pad 4。三个 stretch 各取一个。
    for (final double s in <double>[0, 0.5, 1]) {
      final shape = LiquidLensShape.of(
          itemW: 88,
          capsuleH: 64,
          pad: 4,
          centerPage: 0,
          lift: 1,
          velocity: 0,
          stretch: s);
      expect(shape.width > shape.height, isTrue,
          reason: '前提错了：这一档应当是横向档（stretch $s）');
      expect(shape.leftCrossRadius, closeTo(shape.leftRadius, 1e-9));
      expect(shape.rightCrossRadius, closeTo(shape.rightRadius, 1e-9));
    }
  });

  // ── 静止时的那圈边缘高光（v0.10.13）──────────────────────────────────────
  //
  // 光谱那几层全被 `motion` 关着 ——「静止时一个彩色像素都没有」是 v0.10.7 为底栏定的
  // 规矩，而底栏那枚旁边有图标与胶囊衬着、不缺这一圈。响铃页那枚药丸孤零零挂在深色
  // 页面上，关了它就只剩一块平色、读起来像漆 —— `restEdge` 就是给那种场合开的一档，
  // **默认 0**，既有四处一位都不动。
  //
  // 两条都在**纯黑画布**上量：白边在浅色底上等于没画（那正是它只给深色页面用的原因）。

  /// 把一枚 60 直径的正圆光栅化到 200×200 的纯黑画布上。
  ///
  /// `lift: 0` → 连阴影都不画；`velocity: 0` → `motion = 0` → 连光谱都不画。
  /// 于是这张图上**只剩本体填充与新加的那圈边**，别的都干扰不到。
  Future<List<int>> rasterRoundLens(
    WidgetTester tester, {
    required double restEdge,
  }) async {
    const int edge = 200;
    tester.view.physicalSize = const Size(edge * 1.0, edge * 1.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final LiquidLensShape shape = LiquidLensShape.of(
        itemW: 60, capsuleH: 60, pad: 0, centerPage: 0, lift: 0, velocity: 0);
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: const Color(0xFF000000),
          child: Center(
            child: SizedBox(
              width: 60,
              height: 60,
              child: LiquidLens(
                size: const Size(60, 60),
                shape: shape,
                lift: 0,
                isDark: true,
                accent: const Color(0xFF4C4CE0),
                restEdge: restEdge,
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
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      px = data!.buffer.asUint8List().toList();
    });
    return px;
  }

  /// 圆心在 (100, 100)、半径 30 —— 轮廓那一点就在 y = 70。
  int lumAt(List<int> px, int x, int y) {
    final int i = (y * 200 + x) * 4;
    return (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) ~/ 1000;
  }

  testWidgets('restEdge = 1：轮廓上真的亮出一圈', (tester) async {
    final List<int> off = await rasterRoundLens(tester, restEdge: 0);
    final List<int> on = await rasterRoundLens(tester, restEdge: 1);
    int brightest(List<int> px) {
      var v = 0;
      for (int y = 64; y <= 76; y++) {
        final int l = lumAt(px, 100, y);
        if (l > v) v = l;
      }
      return v;
    }

    expect(brightest(on) - brightest(off), greaterThan(20),
        reason: '开了 restEdge 轮廓上却没亮（关 ${brightest(off)} / 开 ${brightest(on)}）');
  });

  testWidgets('restEdge = 1：只画边，不往里面填', (tester) async {
    final List<int> off = await rasterRoundLens(tester, restEdge: 0);
    final List<int> on = await rasterRoundLens(tester, restEdge: 1);

    // 圆心与圆心下方 20px（都在轮廓里侧 10px 以上）：两版应当几乎一样。
    // 差得大 = 实现写成了「填一层淡白」而不是沿轮廓描一圈边。
    expect((lumAt(on, 100, 100) - lumAt(off, 100, 100)).abs(), lessThan(8));
    expect((lumAt(on, 100, 120) - lumAt(off, 100, 120)).abs(), lessThan(8));
  });

  // ── 竖着走的透镜也要挤内容（v0.10.13）────────────────────────────────────
  //
  // 响铃页那行「上滑关闭」正好躺在药丸经过的路上（用户原话：「如果这个滑轨上面有字，
  // 记得这个字是不是也得扭曲效果」）。`LensWarpedCell` 的参数全是 x，套不上去 ——
  // 所以有了 [LensWarpedVertical]：**同一份纯函数 `lensIconWarp`**，只把位移落到 dy、
  // 两个缩放互换（因为「被挤」永远是**垂直于运动方向**的那一根）。

  group('竖着走的透镜：LensWarpedVertical', () {
    Future<void> pump(
      WidgetTester tester, {
      required double itemCenterY,
      required double lensCenterY,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: LensWarpedVertical(
            listenable: ValueNotifier<int>(0),
            itemCenterY: itemCenterY,
            lensCenterY: () => lensCenterY,
            halfHeight: 50,
            child: const Text('上滑关闭'),
          ),
        ),
      ));
    }

    testWidgets('内容压在透镜边缘时被挤：位移沿 y、两个缩放互换', (tester) async {
      // 半高 50 —— itemCenterY 放在透镜中心上方整整一个半高，t 正好 = 1（= 边缘）。
      await pump(tester, itemCenterY: 150, lensCenterY: 100);
      final Matrix4 m = tester
          .widget<Transform>(find.descendant(
              of: find.byType(LensWarpedVertical),
              matching: find.byType(Transform)))
          .transform;

      expect(m.entry(0, 3), 0.0, reason: '位移跑到 x 上去了 —— 那是横向那一份');
      expect(m.entry(1, 3).abs(), greaterThan(0.5), reason: '沿 y 没有位移');
      // 「被挤」垂直于运动方向：竖着走 → **纵向压扁、横向拉长**。
      expect(m.entry(1, 1), lessThan(1.0), reason: '纵向没压扁');
      expect(m.entry(0, 0), greaterThan(1.0), reason: '横向没拉长');
    });

    testWidgets('内容落在透镜正中心时一层都不套（恒等就不套，那是要付代价的）',
        (tester) async {
      await pump(tester, itemCenterY: 100, lensCenterY: 100);
      expect(
          find.descendant(
              of: find.byType(LensWarpedVertical),
              matching: find.byType(Transform)),
          findsNothing);
    });
  });

  // ── 日历那枚选中块要的形状：圆角方，而不是胶囊 ────────────────────────────
  //
  // 这一族到今天只会画「半径 = min(高, 宽)/2」的胶囊。日历的格子是 52 × 81 的
  // **圆角方**（半径 16）—— 半径远小于半高，所以必须另开一支；直接套胶囊那一支
  // 会画成一枚竖着的椭圆，贴在 `radiusM` 的卡片上四角对不上。
  //
  // 三条自证缺一不可：默认值不许变（既有四处逐像素不变靠它）、给了就走新支、
  // 给的太大时要自动退回老支（小窗的格宽只有 21 —— 那里连圆角方都画不出来）。
  group('圆角方那一支（cornerR）', () {
    LiquidLensShape s({double cornerR = double.infinity}) => LiquidLensShape.of(
        itemW: 52,
        capsuleH: 85,
        pad: 2,
        centerPage: 0,
        lift: 0,
        velocity: 0,
        stretch: 0,
        cornerR: cornerR);

    test('不给 cornerR：还是今天那枚胶囊（半径 = min(高,宽)/2）', () {
      expect(s().leftRadius, closeTo(26, 0.01)); // min(81, 52) / 2
    });

    test('给了 cornerR：端头半径就是它，轮廓是那个矩形', () {
      final LiquidLensShape sh = s(cornerR: 16);
      expect(sh.leftRadius, closeTo(16, 0.01));
      final Rect b = sh.toPath().getBounds();
      expect(b.width, closeTo(52, 0.01));
      expect(b.height, closeTo(81, 0.01));
    });

    test('圆角方那一支的四角是**真圆**（不是被纵向拉长的椭圆）', () {
      final LiquidLensShape sh = s(cornerR: 16);
      final Rect b = sh.toPath().getBounds();
      // 45° 那一点：真圆的角上落在 (r(1−1/√2), r(1−1/√2))；
      // 而竖直档那一支会把半径 26 纵向拉成 40.5，同一个角落在 (4.7, 11.9)
      // —— 差 2.9px，用 0.6 的容差分得开。
      final double k = 16 * (1 - math.sqrt(2) / 2);
      final Offset p = Offset(b.left + k, b.top + k);
      expect(sh.toPath().contains(p + const Offset(0.6, 0.6)), isTrue,
          reason: '圆角内侧那一点应当在轮廓里 —— 不在说明角被拉成了椭圆');
      expect(sh.toPath().contains(p - const Offset(0.6, 0.6)), isFalse,
          reason: '圆角外侧那一点应当在轮廓外');
    });

    test('cornerR 比半宽还大时自动退回胶囊那支（小窗的格宽只有 21）', () {
      final LiquidLensShape sh = LiquidLensShape.of(
          itemW: 21,
          capsuleH: 40,
          pad: 2,
          centerPage: 0,
          lift: 0,
          velocity: 0,
          cornerR: 16);
      expect(sh.leftRadius, closeTo(21 / 2, 0.01));
      expect(sh.toPath().getBounds().height, closeTo(36, 0.01));
    });

    test('四个角恒为 cornerR —— 满形变下也不收后缘（不然会露月牙）', () {
      // 胶囊那族的「后缘半径 ×(1−0.35·stretch)」是给端头用的；圆角方上收半径只是
      // 把一个角磨尖，而它必须与卡片的 radiusM 逐像素对齐 —— 差一档就是那两个角
      // 各露出一条月牙（v0.7.3 真机反馈的那一类）。
      final LiquidLensShape sh = LiquidLensShape.of(
          itemW: 52,
          capsuleH: 85,
          pad: 2,
          centerPage: 0,
          lift: 1,
          velocity: 600,
          stretch: 1, // 满形变：胶囊那支这一档会把后缘半径打到 65%
          cornerR: 16);
      final Rect b = sh.toPath().getBounds();
      // 半径 16 的 45° 点离角 4.69；半径 10.4（= 16×0.65）的离角 3.05 —— 取中间的 3.9。
      const double d = 3.9;
      for (final Offset p in <Offset>[
        Offset(b.left + d, b.top + d),
        Offset(b.right - d, b.top + d),
        Offset(b.right - d, b.bottom - d),
        Offset(b.left + d, b.bottom - d),
      ]) {
        expect(sh.toPath().contains(p), isFalse,
            reason: '有一个角比 cornerR 小 —— 它会与卡片的圆角对不上');
      }
    });
  });

  // ── 形变分横纵两份 ──────────────────────────────────────────────────────
  //
  // 日历那枚块是**二维**走的（上下左右都是相邻的格子），所以「沿运动方向拉长、
  // 垂直于运动方向收细」要按分量各算各的。今天只有横向那一份：纵向那一份**只会
  // 被压扁、从不被拉长**。`stretchY` 不给时取 0，两条算式逐字退回今天 ——
  // 这是既有四处逐像素不变的可断言形式。
  group('纵向形变（stretchY）', () {
    LiquidLensShape s({required double sx, double? sy}) => LiquidLensShape.of(
        itemW: 88,
        capsuleH: 64,
        pad: 10,
        centerPage: 0,
        lift: 1,
        velocity: 0,
        stretch: sx,
        stretchY: sy,
        metrics: const LiquidLensMetrics(
            protrude: 10, liftWidth: 10, rimScale: 1));

    test('不给 stretchY：宽高与今天逐字相同', () {
      final LiquidLensShape sh = s(sx: 1);
      expect(sh.width, closeTo(88 * (1 + AppTokens.lensStretch) + 10, 0.001));
      expect(sh.height, closeTo(44 * (1 - AppTokens.lensSquash) + 20, 0.001));
    });

    test('纵向那一份独立：给 vy 时高变高、宽变窄，且不影响横向那一条', () {
      final LiquidLensShape x = s(sx: 1, sy: 0);
      final LiquidLensShape y = s(sx: 0, sy: 1);
      expect(x.width, greaterThan(y.width), reason: '横着拖那份没有拉宽');
      expect(y.height, greaterThan(x.height), reason: '竖着拖那份没有拉高');
      // 交叉项：横向那一份也会把高压矮、纵向那份也会把宽收窄（面积近似守恒）。
      expect(y.width, lessThan(88 + 10));
      expect(x.height, lessThan(44 + 20));
    });
  });

  // ── 挤字的二维版 ────────────────────────────────────────────────────────
  //
  // 一维版只认 x（底栏 / 分段器那种「一排」的控件）。日历的格子**四面八方都相邻**，
  // 所以「到透镜中心的距离」要换成椭圆归一化距离、把「被挤」的方向换成径向。
  // 一维版必须是它在 `dy = 0` 时的特例 —— 底栏那四处一个字都不改，靠的就是这条。
  group('二维挤字（lensIconWarp2d）', () {
    test('dy = 0 时与一维版逐点相同', () {
      for (final double dx in <double>[0, 12, 34, 60, 90]) {
        final ({double scaleX, double scaleY, double dx}) a = lensIconWarp(
            iconCenterX: 60 + dx, lensCenterX: 60, lensHalfWidth: 44);
        final ({
          double scaleRadial,
          double scaleTangent,
          double dx,
          double dy,
          double angle
        }) b = lensIconWarp2d(
            itemCenterX: 60 + dx,
            itemCenterY: 100,
            lensCenterX: 60,
            lensCenterY: 100,
            lensHalfWidth: 44,
            lensHalfHeight: 44);
        expect(b.scaleRadial, closeTo(a.scaleX, 1e-9));
        expect(b.scaleTangent, closeTo(a.scaleY, 1e-9));
        expect(b.dx, closeTo(a.dx, 1e-9));
        expect(b.dy, closeTo(0, 1e-9));
        expect(b.angle, closeTo(0, 1e-9));
      }
    });

    test('正中心不挤（t = 0 权重见底，恒等就不套变换）', () {
      final r = lensIconWarp2d(
          itemCenterX: 100,
          itemCenterY: 100,
          lensCenterX: 100,
          lensCenterY: 100,
          lensHalfWidth: 44,
          lensHalfHeight: 44);
      expect(r.scaleRadial, 1.0);
      expect(r.dx, 0.0);
      expect(r.dy, 0.0);
    });

    test('峰值在边缘（t = 1 正好落在透镜轮廓上）', () {
      double pinchAt(double t) => 1 -
          lensIconWarp2d(
                  itemCenterX: 44 * t,
                  itemCenterY: 0,
                  lensCenterX: 0,
                  lensCenterY: 0,
                  lensHalfWidth: 44,
                  lensHalfHeight: 44)
              .scaleRadial;
      expect(pinchAt(1), greaterThan(pinchAt(0.6)));
      expect(pinchAt(1), greaterThan(pinchAt(1.4)));
    });

    test('纯竖直偏移：方向朝上、沿径向压扁、垂直方向拉长', () {
      final r = lensIconWarp2d(
          itemCenterX: 0,
          itemCenterY: 40,
          lensCenterX: 0,
          lensCenterY: 0,
          lensHalfWidth: 44,
          lensHalfHeight: 44);
      expect(r.angle, closeTo(math.pi / 2, 1e-6));
      expect(r.scaleRadial, lessThan(1));
      expect(r.scaleTangent, greaterThan(1));
      expect(r.dy, greaterThan(0));
    });
  });
}
