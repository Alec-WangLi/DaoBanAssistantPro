// `LiquidLensController` 的手感护栏。
//
// 这一层是从底栏原样抽出来的（数值一个都没改），所以这些用例量的就是底栏现在的行为：
// **点按不提起 / 长按才提起 / 拖动 1:1 跟手 / 亮度渐入渐出 / 帧率无关**。
//
// ⚠️ **pump 的步长必须是 16ms 或更小**：`LiquidLensSpring.step` 把每帧积分封顶在
// `lensMaxStep`（16ms），喂更大的步长整段动画会变慢，量出来的时间全是假的
// （v0.10.8 出 GIF 时就栽过一次：55ms 一帧拍出来「渐入要 440ms」）。

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_controller.dart';

void main() {
  const double itemW = 90;

  LiquidLensController make({int slots = 4, int initialSlot = 0}) {
    final c = LiquidLensController(
      slots: slots,
      pad: 6,
      liftWidth: 10,
      vsync: const TestVSync(),
      initialSlot: initialSlot,
    )..setItemW(itemW);
    addTearDown(c.dispose);
    return c;
  }

  /// 推 [ms] 毫秒，16ms 一帧。
  Future<void> advance(WidgetTester tester, int ms) async {
    for (int t = 0; t < ms; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// 把四个弹簧推到全部静止 —— **每条用例收尾都要调它**。
  ///
  /// 亮度那条弹簧的 `isAtRest` 门槛是 0.01，而从满亮淡下来要 ~600ms；不等它静下来，
  /// ticker 就还挂着，测试结束时会报
  /// 「An animation is still running even after the widget tree was disposed」。
  /// **那是真行为（底栏也一样），不是 bug** —— 所以要等，而不是去放宽门槛。
  Future<void> settleToRest(WidgetTester tester) => advance(tester, 1600);

  testWidgets('开局：停在那一格的中心，什么都没提起', (tester) async {
    final c = make(initialSlot: 2);
    expect(c.position, closeTo(2.5, 0.001));
    expect(c.lift, 0);
    expect(c.motion, 0);
    await advance(tester, 64);
    expect(c.position, closeTo(2.5, 0.001), reason: '没人动它，它自己走了');
 
    await settleToRest(tester);
  });

  testWidgets('点按：不提起，位置滑到目标格', (tester) async {
    // 交互契约：点一下只是「滴自动过来」，**不提起** —— 凸出容器是「按住」的专属信号。
    final c = make();
    c.press(itemW * 2 + itemW / 2); // 第 3 格
    await advance(tester, 48); // 短于 lensHoldDelay（110ms）
    expect(c.lift, lessThan(0.05), reason: '点了一下就提起了');
    expect(c.previewIndex, 2);

    c.release();
    await advance(tester, 480);
    expect(c.position, closeTo(2.5, 0.02), reason: '没滑到目标格');
    expect(c.lift, lessThan(0.05), reason: '松手之后还提着');
 
    await settleToRest(tester);
  });

  testWidgets('长按 + 拖动：提起、1:1 跟手', (tester) async {
    final c = make();
    c.press(itemW / 2); // 第 1 格中间
    await advance(tester, 240); // 过 lensHoldDelay（110ms）
    expect(c.lift, greaterThan(0.5), reason: '按住够久了却没提起');

    c.dragStart(itemW / 2);
    c.dragUpdate(itemW / 2 + itemW); // 往右拖一格
    expect(c.position, closeTo(1.5, 0.05),
        reason: '拖动没有 1:1 跟手 —— 位置是弹簧算的（会拖出一条橡皮筋尾巴）');
    expect(c.dragging, isTrue);

    c.release();
    await advance(tester, 480);
    expect(c.position, closeTo(1.5, 0.02));
 
    await settleToRest(tester);
  });

  testWidgets('帧率无关：同一段位移在 8.33ms 与 16.67ms 下速度一致', (tester) async {
    // 60Hz 每帧 5px ≡ 120Hz 每帧 2.5px ≡ **300px/s**。两路必须给出同一个速度。
    // 坏了它的是分母上那个 `max(dt, 16ms)` 的地板（16ms 正好是一帧 60Hz）。
    Future<double> run(Duration step, double pxPerFrame) async {
      final c = make();
      c.press(itemW / 2);
      for (int i = 0; i < 10; i++) {
        await tester.pump(step);
      }
      c.dragStart(itemW / 2);
      for (int i = 0; i < 20; i++) {
        c.dragUpdate(itemW / 2 + pxPerFrame * (i + 1));
        await tester.pump(step);
      }
      final double v = c.velocity;
      c.release(); // 松手：否则 `_pressed` 恒真、ticker 永远不停
      return v;
    }

    final double at120 = await run(const Duration(microseconds: 8333), 2.5);
    final double at60 = await run(const Duration(microseconds: 16667), 5.0);
    expect(at120, closeTo(300, 20));
    expect(at60, closeTo(300, 20));
    expect((at120 - at60).abs() / at60, lessThan(0.08),
        reason: '120Hz 算出 $at120、60Hz 算出 $at60 —— 速度跟帧率绑在一起了');
 
    await settleToRest(tester);
  });

  testWidgets('手停下来：亮度渐出（160ms 时仍 > 0.4，480ms 时 < 0.1）', (tester) async {
    // 「彩边出现得太突然了……咱们手停下来的时候，也得有点过渡，不要突然就没了。」
    final c = make();
    c.press(itemW / 2);
    await advance(tester, 320);
    c.dragStart(itemW / 2);
    for (int i = 0; i < 20; i++) {
      c.dragUpdate(itemW / 2 + 3.0 * (i + 1));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.motion, greaterThan(0.95), reason: '一直拖着却没亮到满');

    await advance(tester, 160); // 手指停住、不松手
    expect(c.motion, greaterThan(0.4), reason: '停手 160ms 就基本没了 —— 那是「突然就没了」');
    await advance(tester, 320); // 共 480ms
    expect(c.motion, lessThan(0.1), reason: '停手 480ms 了还亮着 —— 淡不干净');
 
    c.release();
    await settleToRest(tester);
  });

  testWidgets('松手：**逻辑页也吸附**到落下的那一格（标准档的高亮块靠它）', (tester) async {
    // 独立审查抓的 Critical：`release()` 原先只挪了弹簧的目标，忘了 `_page`。
    // 于是「拖了一点点、又松在同一格上」时 —— `onSelected` 不触发、里面没有别的东西
    // 去纠正它 —— **标准档那块高亮会永远停在差一点的位置上**。
    //
    // 抽共享件之前两处都是自己吸附的（底栏 `_visualPage = target`、分段器 `_visual = target`），
    // 那两行在抽取时丢了。
    final c = make();
    c.press(itemW / 2); // 第 1 格中间
    await advance(tester, 48);
    c.dragStart(itemW / 2);
    c.dragUpdate(itemW / 2 + 9); // 只往右挪 9px，仍在第 1 格里
    expect(c.page, closeTo(0.1, 0.001), reason: '拖动中逻辑页该是连续的');
    c.release();
    expect(c.page, closeTo(0, 0.001),
        reason: '松手之后逻辑页没吸附回那一格（停在 ${c.page}）—— 标准档的高亮块会偏着');
    await settleToRest(tester);
  });

  testWidgets('按住够久再竖直滑走：升程**必须落回来**（它原来冻在满档）', (tester) async {
    // 用户 2026-10-01：「长按这些滑块，手指快速上下滑动页面时，滑块会定格在放大的
    // 那个瞬间，需要再次点击一下滑块，才会恢复正常」。
    //
    // 根因：`_syncTicker()` 拿 `_lift.isAtRest` 判「还要不要推帧」，而它比的是
    // `value` 与 `target` —— **`target` 只在 `_onTick` 里刷新**。`tapCancel()` 翻完
    // 状态立刻判，此时 `value == target == 1`，判成「已静止」→ 停 ticker →
    // `_onTick` 再也不跑 → `target` 永远停在 1。
    //
    // **按得够久是复现的关键**：400ms 时升程弹簧速度还没落到 1 以下、不算静止，
    // ticker 照跑，于是自愈 —— 它在真机上只在「弹簧停稳之后再滑」时出现。
    final c = make();
    c.press(itemW + itemW / 2);
    await advance(tester, 1200); // 升程彻底停稳
    expect(c.lift, closeTo(1, 0.001), reason: '这一档本该已经提满了');

    c.tapCancel();
    await advance(tester, 800);
    expect(c.lift, lessThan(0.01), reason: '升程冻在 ${c.lift} —— ticker 被提前停了');

    await settleToRest(tester);
  });

  testWidgets('速度门调低之后，慢速拖动也积得起形变；松手会收回去', (tester) async {
    // 规格 §3.3：一格 25px 的轨道上，全局 900px/s 的峰值形变只有 0.22~0.28 ——
    // 钮一两个帧就到头了，速度积不起来（**越快反而越短**）。
    // 这一条同时钉两头：够得着，以及**松手之后不留在那儿**。
    // 反向验证过：把这里的 180 换成 900，形变掉到 0.19。
    final c = LiquidLensController(
      slots: 2,
      pad: 3,
      liftWidth: 25 * 0.15625,
      vsync: const TestVSync(),
      initialSlot: 1,
      velocityRef: 180,
    )..setItemW(25);
    addTearDown(c.dispose);

    c.dragStart(25 * 1.5);
    for (int i = 0; i < 8; i++) {
      c.dragUpdate(25 * 1.5 - 3 * (i + 1)); // 187px/s，一次不紧不慢的正常拖动
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.stretch, greaterThan(0.7),
        reason: '慢速拖动只积到 ${c.stretch} —— 速度门没接上');

    c.release();
    await advance(tester, 800);
    expect(c.stretch, lessThan(0.05), reason: '松手之后尾巴还挂着（${c.stretch}）');

    await settleToRest(tester);
  });

  testWidgets('取消：只有真正在拖才回退，点按被取消不回退', (tester) async {
    final c = make();
    // 点按之后竖直滑走 → 只该取消「按住」，位置仍然去它本来要去的格
    c.press(itemW * 3 + itemW / 2);
    await advance(tester, 48);
    c.tapCancel();
    await advance(tester, 480);
    expect(c.pressed, isFalse, reason: '_pressed 卡在 true —— 滴会一直提着');
    expect(c.position, closeTo(3.5, 0.02), reason: '点按被取消却把位置也回退了');
 
    await settleToRest(tester);
  });
}
