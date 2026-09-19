// `todayCard` 的时间基准。
//
// 为什么值得单独钉：`todayCard` 里的农历、待办数、其他班组都是**生成那天**的，
// 而跨天时原生只能拿 `LocalDate.now().toEpochDay()` 去 `days[]` 对表右移 ——
// `todayCard` 右移不了。原生据此判「这份卡片还是不是今天」，对不上就走**降级态**
// （农历与其他班组留空），而不是把旧数据当成今天显示。
//
// 这条测试保证那个判定所依赖的前提成立：`todayCard.day` **恒等于生成那天的
// epochDay**，且与 `days[0].day` 一致。
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/widget/widget_snapshot.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });
  setUp(() => L10n.locale = 'zh');

  test('todayCard.day 恒等于生成那天，且与 days[0] 同天', () {
    for (final d in [
      DateTime(2026, 9, 19, 0, 5),
      DateTime(2026, 9, 19, 23, 55),
      DateTime(2026, 12, 31, 12),
      DateTime(2027, 1, 1, 0, 1),
    ]) {
      final s = buildWidgetSnapshot(
        schedule: null,
        now: d,
        themeMode: 'system',
        accent: 0xFF4F5BE8,
        todayTodoCount: 0,
      );
      final tc = s['todayCard']! as Map;
      final days = s['days']! as List;
      expect(tc['day'], dayNumber(d), reason: '生成于 $d 时应当带那天的 epochDay');
      expect(tc['day'], (days.first as Map)['day']);
    }
  });

  test('跨过午夜之后，同一个生成时刻的 todayCard.day 不再等于「今天」', () {
    final generated = DateTime(2026, 9, 19, 23, 0);
    final s = buildWidgetSnapshot(
      schedule: null,
      now: generated,
      themeMode: 'system',
      accent: 0xFF4F5BE8,
      todayTodoCount: 0,
    );
    final cardDay = (s['todayCard']! as Map)['day'] as int;
    // 第二天再看：原生的判定就是这一句。
    final tomorrow = dayNumber(DateTime(2026, 9, 20, 0, 30));
    expect(cardDay == tomorrow, false,
        reason: '这份卡片生成于 9/19，9/20 再看时它不该被当成今天 —— 那时要走降级态');
  });
}
