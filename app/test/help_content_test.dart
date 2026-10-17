// app/test/help_content_test.dart
//
// 第二层内容是**成块的文案**，最容易出的两种错都不会报错：英文漏翻（英文界面上
// 显示中文），以及**数字与实现漂了** —— 后者这个仓库真犯过：帮助里写着
// 「一个班次最多挂 6 条闹钟」，而 v0.11.1 早就放到 10 条了（这一版才发现）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/profile/help_content.dart';

List<HelpFaqItem> _allItems() =>
    [for (final g in helpFaqGroups) for (final s in g.sections) ...s.items];

/// 除了条目，**组标题与小节标题**也要查 —— 它们此前完全在护栏之外，
/// 漏翻一个标题，三条用例一条都不会响（独立审查 v0.11.17 报的 Minor）。
List<L10nText> _allHeadings() => [
      for (final g in helpFaqGroups) ...[
        g.title,
        for (final s in g.sections)
          if (s.heading != null) s.heading!,
      ],
    ];

/// 条目 + 标题的全部可翻译文本 —— 两条护栏（没翻译 / markdown）都遍历它。
List<L10nText> _allTexts() => [
      for (final it in _allItems()) ...[it.question, it.answer],
      ..._allHeadings(),
    ];

void main() {
  test('两组的条数下限（spec §4 那一份是下限，不许比它少）', () {
    expect(helpFaqGroups.length, 2, reason: '「我想办一件事」+「它不对劲」');
    expect(_allItems().length, greaterThanOrEqualTo(31),
        reason: 'spec §4 逐条数下来是 31 条；删条要回 spec 里改，别就地删');
  });

  test('每条的两种语言都写满了，且英文不是照抄中文', () {
    for (final t in _allTexts()) {
      expect(t.zh.trim(), isNotEmpty);
      expect(t.en.trim(), isNotEmpty,
          reason: '英文缺省会在英文界面上伪装成正常内容（L10nText 不回退，'
              '但空串同样看不出来）：${t.zh}');
      expect(t.en, isNot(t.zh), reason: '英文没翻：${t.zh}');
    }
  });

  test('帮助文案里不许出现 markdown 标记', () {
    // 与 changelog_window_test 同一套路：更新日志真犯过两次（v0.7.1/v0.7.2、
    // v0.9.14），用户看到的是星号本身。帮助也是纯文本渲染。
    final bad = RegExp(r'\*\*|`|^#|\[[^\]]+\]\([^)]+\)', multiLine: true);
    for (final t in _allTexts()) {
      for (final s in [t.zh, t.en]) {
        expect(bad.hasMatch(s), isFalse, reason: '命中了 markdown 标记：$s');
      }
    }
  });

  test('闹钟条数的数字与 maxAlarmsPerShift 一致', () {
    final item = _allItems()
        .firstWhere((it) => it.question.zh.contains('响两次'));
    expect(item.answer.zh, contains('$maxAlarmsPerShift'),
        reason: '帮助里写的条数必须从常量来 —— 改了上限就要回来改这句');
    expect(item.answer.en, contains('$maxAlarmsPerShift'));
  });
}
