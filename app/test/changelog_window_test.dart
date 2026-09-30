// app/test/changelog_window_test.dart
//
// 更新日志的四条长期规则里，有三条是**机械可查**的，此前只靠人记：
//   1. 窗口固定 10 条（prepend 新版本、删掉最旧一条）；
//   2. 最新那条的版本号等于当前版本（`appVersion`）；
//   3. **不许写 markdown**（见下面那条「裸标记」用例）。
// 第四条「正式版条目要重写成归纳总结版」是写作判断，查不了，只能靠这条注释提醒。
//
// 为什么值得一条用例：这几条每次发版都要手工执行一遍，而**漏了不会报任何错** ——
// 窗口从 10 条涨到 11、12 条时，界面上的更新日志越滚越长（它在一个滚动框里，
// 短时间看不出来）；最新条目忘了改版本号，用户升级后第一眼看到的是上一版的内容。
// 2026-09-29（v0.9.9 那轮）就是纯手数了 10 条。
//
// 第 3 条是**真犯过两次**的：v0.7.1 / v0.7.2 的条目里混进过 `**`，当时只手工清掉；
// v0.9.14 又混进去三处（`**两段时间不许重叠**`、`**多段**`、`**App 长期不开也照常响**`），
// 用户真机上看到的是星号本身 —— 更新日志走的是纯文本渲染（`showAppInfoDialog` 里
// 就是一个 `Text`），markdown 一律不解析。只清一次不留护栏，它就会一直长回来。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/features/profile/app_dialogs.dart';

/// 更新日志里出现的版本号，按出现顺序。
List<String> _versions() => RegExp(r'^v(\d+\.\d+\.\d+)$', multiLine: true)
    .allMatches(appChangelog)
    .map((m) => m.group(1)!)
    .toList();

void main() {
  for (final locale in const ['zh', 'en']) {
    test('$locale 更新日志：窗口恒 10 条、版本号严格递减、首条是当前版本', () {
      L10n.locale = locale;
      final versions = _versions();

      expect(versions, isNotEmpty, reason: '一条都没解析出来 —— 条目格式变了？');
      expect(versions.length, 10,
          reason: '窗口固定 10 条：prepend 新版本之后要 DELETE THE OLDEST，'
              '当前 ${versions.length} 条（多半是只加了新的、忘了删最旧的）');
      expect(versions.first, appVersion,
          reason: '最新那条必须是当前版本 —— 忘了 prepend 的话，用户升级后'
              '看到的还是上一版的更新内容');

      // 严格递减：既挡「顺序放反」，也挡「prepend 到了中间」。
      for (var i = 1; i < versions.length; i++) {
        expect(_compare(versions[i - 1], versions[i]), greaterThan(0),
            reason: '${versions[i - 1]} 应当排在 ${versions[i]} 前面');
      }
    });
  }

  test('中英两份的版本号列表完全一致', () {
    L10n.locale = 'zh';
    final zh = _versions();
    L10n.locale = 'en';
    final en = _versions();
    expect(en, zh,
        reason: '两个语言各写一份常量，只改一边就会出现「中文有 10 条、英文 9 条」'
            '这类只在切语言时才看得见的错位');
  });

  for (final locale in const ['zh', 'en']) {
    test('$locale 更新日志：不许出现 markdown 标记', () {
      L10n.locale = locale;
      final hits = _markdownHits(appChangelog);
      expect(hits, isEmpty,
          reason: '更新日志是**纯文本渲染**的（`showAppInfoDialog` 里就是一个 '
              '`Text`），markdown 不会被解析 —— 用户看到的是标记本身'
              '（`**粗体**` 显示成两个星号）。命中的行：\n${hits.join('\n')}');
    });
  }
}

/// 更新日志里的 markdown 标记 —— **纯文本渲染下会以标记本身示人**的那几种。
///
/// 只列真的会看见的：`**` 粗体、`` ` `` 行内代码、行首 `#` 标题、`[文字](链接)`。
/// 行首的 `·`（全仓的要点标记）与「——」「（）」都是普通字符，不在列。
///
/// 返回命中处的**整行**（而不是只返回 true）：文案是人写的，报出是哪一行才好改。
List<String> _markdownHits(String text) {
  final pattern = RegExp(r'\*\*|`|^#{1,6}\s|\[[^\]]+\]\(');
  return [
    for (final line in text.split('\n'))
      if (pattern.hasMatch(line)) line,
  ];
}

/// 语义版本比较：返回正数表示 a 比 b 新。
int _compare(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] - pb[i];
  }
  return 0;
}
