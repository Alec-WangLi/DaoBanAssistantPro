// app/test/once_alarm_date_test.dart
//
// 一次性自定义闹钟「该落在哪天」的判据（`nextOnceDate`，见 `alarm_service.dart`）。
//
// **为什么要有这一层**：新建闹钟时时间默认此刻、日期默认今天，两个默认叠在一起，
// 触发时刻在按下「添加」之前就已经过去了。而一次性闹钟的排定判据是
// `fire.isAfter(now)` —— 过去的那一刻**直接不排**，`deleteExpiredOnceAlarms` 还会
// 在下一次进闹钟页时把它删掉。用户看到的是「加了一条、它自己没了」。
// `repeatType` 的默认值改成「一次性」之后（v0.9.6）这是常态，不是边角情况。
//
// 判据是纯函数，所以边界（正好等于、月末、年末、用户手选了过去/将来的日期）在这里
// 逐条钉死；它在界面上的落点由 `alarm_screen_test.dart` 那两条用例盯。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

void main() {
  // 结果与库里 `onceDate` 那一列同形：`dateOnly` 给的 **UTC 零点**（见
  // `shift_rotation.dart` 的 `dateOnly`），所以期望值也按 UTC 写。
  DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

  /// `now` 固定；`chosen` 不传就是「今天」（新建闹钟的默认值）。
  DateTime at(int y, int m, int d, int h, int min) => DateTime(y, m, d, h, min);

  DateTime roll(DateTime now, int hour, int minute, {DateTime? chosen}) =>
      nextOnceDate(
        now: now,
        chosen: chosen ?? DateTime(now.year, now.month, now.day),
        hour: hour,
        minute: minute,
      );

  test('今天这个钟点还没到 → 就是今天', () {
    expect(roll(at(2026, 9, 23, 14, 0), 20, 30), day(2026, 9, 23));
  });

  test('今天这个钟点已经过了 → 顺延到明天', () {
    // 新建闹钟的默认值正是这一条：时间默认此刻，存下去之前那一刻就过去了。
    expect(roll(at(2026, 9, 23, 14, 0), 7, 0), day(2026, 9, 24));
  });

  test('钟点正好等于此刻 → 也算过了，顺延', () {
    // 判据是 `isAfter`，严格大于。差一个「现在」在真实世界里等于已经过了。
    expect(roll(at(2026, 9, 23, 14, 0), 14, 0), day(2026, 9, 24));
  });

  test('差一分钟没过 → 还在今天', () {
    expect(roll(at(2026, 9, 23, 13, 59), 14, 0), day(2026, 9, 23));
  });

  test('月末顺延跨月：9月30日 23:00 顺延到 10月1日，不是 9月31日', () {
    expect(roll(at(2026, 9, 30, 23, 0), 22, 0), day(2026, 10, 1));
  });

  test('年末顺延跨年', () {
    expect(roll(at(2026, 12, 31, 23, 0), 22, 0), day(2027, 1, 1));
  });

  test('用户手选了更晚的日期 → 听用户的', () {
    expect(
      roll(at(2026, 9, 23, 14, 0), 7, 0,
          chosen: DateTime(2026, 10, 5)),
      // 用本地的 chosen，但期望值的年月日照抄 —— 函数只取年月日。
      day(2026, 10, 5),
      reason: '选了日子的人比默认值清楚，不能因为钟点已过就把它拽回明天',
    );
  });

  test('用户手选了过去的日期 → 顺延到下一次，不停在过去', () {
    // 落在过去的日期是排不出去的（不响 + 被自动删），顺延是唯一说得通的意思。
    expect(
      roll(at(2026, 9, 23, 14, 0), 7, 0, chosen: DateTime(2026, 9, 1)),
      day(2026, 9, 24),
    );
  });

  test('用户手选了今天、而钟点还没到 → 仍然是今天，不被顺延', () {
    expect(
      roll(at(2026, 9, 23, 14, 0), 20, 0, chosen: DateTime(2026, 9, 23)),
      day(2026, 9, 23),
    );
  });

  test('返回的是日期，与存库的 dateOnly 同形（UTC 零点）', () {
    final d = roll(at(2026, 9, 23, 14, 0), 20, 0);
    expect(d.isUtc, isTrue);
    expect([d.hour, d.minute, d.second], [0, 0, 0]);
  });
}
