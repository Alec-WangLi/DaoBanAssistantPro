// app/test/support/fixed_clock.dart
//
// 日历页的「今天」钉死用的夹具。
//
// 为什么钉：日历页拿「今天」决定显示哪个月、哪一格高亮、「本月统计」统计哪个月，
// 用例又拿真实日期算期望值 —— 于是整套用例随真实月份漂移。2026-11-05 那天一起红了
// 10 条，全是「11 月」这个月份本身的属性：无法定节假日、只有 30 天、且是 6 行月。
//
// 锚点挑 2026-10-15，同时满足三件事：
//   ① **有法定节假日**：国庆 10/1–10/7（`domain/lunar_info.dart` 的 2026 表），
//      节假日徽章用例有东西可量；
//   ② **有 31 号**：`day-card-31` 那条横屏用例需要它存在；
//   ③ **是 5 行月**：10/1 是周四 → 月初偏移 3 → 3 + 31 = 34 格 → 5 行，
//      与「高 ≥ 780dp 不许滚」那条保证线当初被量出来的月份一致（6 行月会多一行，
//      360×780 上实测溢出 1.0 / 21.0dp —— 那是另一件事，不在本轮范围）。
// 取 15 号而不是 1 号：避开国庆整段，让「选中日」落在普通工作日上。
//
// ⚠️ `DateTime` 没有 const 构造，所以这里是 `final` 而不是 `const`。
// ⚠️ `appNow` 是模块级状态，`useFixedNow()` 用 `tearDown` 还原成 `DateTime.now`。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/clock.dart';

/// 测试里钉死的「今天」：2026-10-15（周四）。
final DateTime kAnchor = DateTime(2026, 10, 15);

/// 在 `main()` 里调一次：本文件的每个用例都把「今天」当成 [kAnchor]。
void useFixedNow() {
  setUp(() => appNow = () => kAnchor);
  tearDown(() => appNow = DateTime.now);
}
