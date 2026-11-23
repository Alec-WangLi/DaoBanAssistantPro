// app/test/stats_charts_test.dart
//
// 环形图分段几何的纯函数单测。
//
// 这套几何（圆头描边 + 按像素折角的缝隙）最容易出错的地方是「只有一天的那段」：
// 缝隙一旦大于这一段自己的弧长，那段就在画面上消失了 —— 而它只在某几个月才出现，
// 视觉工装未必撞得上。这里把 1/31、2/31、单段整圈三档钉死。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/features/stats/stats_charts.dart';

const double _radius = (132 - 16) / 2;

void main() {
  test('环图分段：极小段不许被缝隙吃掉，单段整圈不留缝', () {
    // 31 个月里只有一天的那一段：缝隙被夹到它自己的 45%，仍要画出可见弧。
    final tiny = debugDonutArcs(
        counts: [1, 30], radius: _radius, ring: AppTokens.chartRing);
    expect(tiny, hasLength(2));
    expect(tiny.first.sweep, greaterThan(0.05),
        reason: '只有一天的那一段必须还剩可见弧长（不是被缝吃掉）');
    expect(tiny.first.sweep, lessThan(2 * 3.141592653589793 / 31),
        reason: '缝隙确实从这一段里让出来了');

    // 31 段各一天：每一段都还画得出来。
    final many = debugDonutArcs(
        counts: List<int>.filled(31, 1),
        radius: _radius,
        ring: AppTokens.chartRing);
    expect(many, hasLength(31));
    for (final arc in many) {
      expect(arc.sweep, greaterThan(0.02), reason: '31 段时每段都要可见');
    }

    // 单独一段（整个月只有一种班）：整圈不留缝，否则 12 点方向会叠出小瓣。
    final single = debugDonutArcs(
        counts: [31], radius: _radius, ring: AppTokens.chartRing);
    expect(single, hasLength(1));
    expect(single.single.sweep, closeTo(2 * 3.141592653589793, 1e-9));
    expect(single.single.start, closeTo(-3.141592653589793 / 2, 1e-9));

    // 空数据 / 零进度：一个弧都不返回，不崩。
    expect(
        debugDonutArcs(counts: const [], radius: _radius, ring: 16), isEmpty);
    expect(
        debugDonutArcs(
            counts: const [1, 2],
            radius: _radius,
            ring: 16,
            progress: 0),
        isEmpty);
  });
}
