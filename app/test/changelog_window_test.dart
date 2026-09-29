// app/test/changelog_window_test.dart
//
// 更新日志的三条长期规则里，有两条是**机械可查**的，此前只靠人记：
//   1. 窗口固定 10 条（prepend 新版本、删掉最旧一条）；
//   2. 最新那条的版本号等于当前版本（`appVersion`）。
// 第三条「正式版条目要重写成归纳总结版」是写作判断，查不了，只能靠这条注释提醒。
//
// 为什么值得一条用例：这三条每次发版都要手工执行一遍，而**漏了不会报任何错** ——
// 窗口从 10 条涨到 11、12 条时，界面上的更新日志越滚越长（它在一个滚动框里，
// 短时间看不出来）；最新条目忘了改版本号，用户升级后第一眼看到的是上一版的内容。
// 2026-09-29（v0.9.9 那轮）就是纯手数了 10 条。
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
