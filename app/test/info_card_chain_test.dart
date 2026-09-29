// app/test/info_card_chain_test.dart
//
// 卡片高度必须**按月定死**（点哪天都不能变），所以「其他班组」那一行在跨方案的
// 月份里要按「哪天要就哪天算」来取大 —— 只按兜底那套算的话，某个归另一套的日子
// （组数更多、色块折更多行）会把内容顶出定高，而卡片装不下时**只在卡内静默滚动**
// （最后一行被裁掉，没有任何报错）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/info_card_metrics.dart';

DateTime _d(int y, int m, int day) => DateTime.utc(y, m, day);

ShiftSchedule _sched(String name, int teamCount) => ShiftSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: [
        ShiftClass(
            name: '$name-白', abbr: '白', startMinute: 480, endMinute: 1080),
        ShiftClass(name: '$name-休', abbr: '休', isRest: true),
      ],
      cycle: const [0, 1],
      teamCount: teamCount,
      teamNames: List.generate(teamCount, (i) => '$name组${i + 1}'),
      teamOffsets: List.generate(teamCount, (i) => i),
    );

void main() {
  setUp(() async {
    L10n.locale = 'zh';
    // 卡片里要按 `L10n.monthDayWeekday` 量日期行 —— intl 的本地化数据不初始化
    // 就会在 `DateFormat` 上抛 `LocaleDataException`（别的界面测试同样都要这一步）。
    await initializeDateFormatting('zh');
  });

  testWidgets('跨方案的月份：高度按两套里更满的那个取，且逐日存在', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        const w = 400.0;
        final month = DateTime(2026, 9, 1);

        InfoCardMetrics measure(ScheduleChain chain) =>
            measureBottomInfoCardHeight(
              context: context,
              cardOuterWidth: w,
              chain: chain,
              month: month,
              hasTodoHint: false,
              hasOverrideHint: false,
            );

        // 上半月归 1 班组的 B、下半月归 6 班组的 A。
        //
        // 边界特意放在 9/14/15：**全月最满的那天是 9/25（中秋 —— 节假日徽章 +
        // 两行农历）**，它必须落在 6 班组那半边，否则「取更满的那天」这件事根本
        // 没被考到（第一版就是这么写错的：那天归了 1 班组，于是混着来反而更矮，
        // 期望值写反了）。
        final mixed = measure(ScheduleChain(spans: [
          ScheduleSpan(
              id: 1,
              schedule: _sched('B', 1),
              from: _d(2026, 9, 1),
              to: _d(2026, 9, 14)),
          ScheduleSpan(id: 2, schedule: _sched('A', 6), from: _d(2026, 9, 15)),
        ]));
        // 整月都是 6 班组
        final allSix = measure(ScheduleChain(spans: [
          ScheduleSpan(
              id: 1,
              schedule: _sched('A', 6),
              from: _d(2026, 1, 1),
              to: _d(2026, 12, 31)),
        ]));
        // 整月都是 1 班组（没有「其他班组」那一行）
        final onlyOne = measure(ScheduleChain(spans: [
          ScheduleSpan(
              id: 3,
              schedule: _sched('B', 1),
              from: _d(2026, 1, 1),
              to: _d(2026, 12, 31)),
        ]));

        // 混着来也要按**更满的那天**（下半月的 A）定高，否则那几天会被裁。
        expect(mixed.outerHeight, allSix.outerHeight);
        // 逐日数组长度 = 月长（九月 30 天）
        expect(mixed.dayContentHeights.length, 30);
        // 前半月那 14 天确实矮一截（没有那一行），只是被后半月盖过去了
        expect(mixed.dayContentHeights.first,
            lessThan(mixed.dayContentHeights[24]));
        // 真的矮一截：没有那一行
        expect(onlyOne.outerHeight, lessThan(allSix.outerHeight));
        return const SizedBox();
      }),
    ));
  });
}
