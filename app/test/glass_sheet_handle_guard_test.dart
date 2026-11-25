// app/test/glass_sheet_handle_guard_test.dart
//
// **每一个底部弹层都得有那只「往下拖」的小短横** —— 2026-11-25 用户原话：
// 「有的有，有的没有」。根因是把手长在 `GlassSheetHeader` 里：用了那个头的
// 七个弹层有，时间 / 日期 / 月份 / 年份四个选择器没有。
//
// 修法是把把手挪进共享外壳 `GlassSheetPanel`（面板 + SafeArea + 把手），
// 这个测试守两件事：
//   ① 行为：真开两个弹层（一个无头、一个有头），各自**恰好一个**把手；
//   ② 源码：凡是调 `showGlassSheet` 的文件，`GlassSheetPanel(` 的出现次数
//      必须与调用次数相等 —— 只拦到文件一级（半机器），盲区写在下面。
//
// 盲区：同一文件里多处弹层时，这个计数只保证「总数对得上」，挡不住把两处
// 都换成同一处（例如全都堆在一个函数里）。行为用例补了有无头两类；
// 新增弹层时请顺手在这里加一条行为用例。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_pickers.dart';
import 'package:shiftassistantpro/core/widgets/glass_sheet_panel.dart';

import 'support/source_scan.dart';

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // L10n.yearMonth 走 intl 的 'zh' 数据，不初始化会抛 LocaleDataException。
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
  });
  setUp(() => L10n.locale = 'zh');

  testWidgets('日期选择弹层（原来没有头的那一类）有把手', (tester) async {
    await _open(tester,
        (c) => showGlassDatePicker(c, initialDate: DateTime(2026, 11, 15)));
    expect(find.byKey(kGlassSheetHandleKey), findsOneWidget);
  });

  testWidgets('选项弹层（带 GlassSheetHeader 的那一类）只有一只把手，不重复',
      (tester) async {
    await _open(
      tester,
      (c) => showGlassOptionPicker<String>(
        c,
        title: '测试',
        options: const ['a', 'b'],
        labelOf: (s) => s,
        selected: 'a',
      ),
    );
    expect(find.byKey(kGlassSheetHandleKey), findsOneWidget,
        reason: '把手从 GlassSheetHeader 搬进外壳之后，头部不许再画一只');
  });

  testWidgets('把手在面板正中（左右对称）', (tester) async {
    await _open(tester,
        (c) => showGlassTimePicker(c, initialTime: const TimeOfDay(hour: 8, minute: 0)));
    final handle = find.byKey(kGlassSheetHandleKey);
    expect(handle, findsOneWidget);
    final panel = tester.getRect(find.byType(GlassSheetPanel));
    final bar = tester.getRect(handle);
    expect((bar.center.dx - panel.center.dx).abs(), lessThan(0.5),
        reason: '把手要居中，用户才知道这是往下拖的抓手');
    // 「贴近顶边」只钉「在上半部」：`GlassSheetPanel` 的 rect 还包着 12 的外边距、
    // 8 的上内边距，测试环境里再叠一层顶部内缩 —— 钉死具体像素只会变成脆弱断言。
    expect(bar.top - panel.top, lessThan(panel.height / 2),
        reason: '把手要挨着面板顶边，不能掉到内容中间');
  });

  test('每个 showGlassSheet 调用点都用玻璃弹层外壳', () {
    // 测试的工作目录是 app/，源码根就是 lib。
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: '工作目录不对（应从 app/ 跑测试）');

    const excluded = <String>{
      // 定义处：showGlassSheet 本体在这里，它当然不调自己。
      'lib/core/widgets/glass_dialog.dart',
      // 外壳自己的定义。
      'lib/core/widgets/glass_sheet_panel.dart',
    };

    var files = 0;
    var totalSheets = 0;
    final problems = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (excluded.contains(path)) continue;
      files++;
      // E7：先剥注释与字符串，注释里提一句不算。
      final code = blankNonCode(entity.readAsStringSync());
      final sheets = 'showGlassSheet<'.allMatches(code).length;
      if (sheets == 0) continue;
      totalSheets += sheets;
      final panels = 'GlassSheetPanel('.allMatches(code).length;
      if (panels != sheets) {
        problems.add('$path：showGlassSheet ×$sheets，GlassSheetPanel ×$panels');
      }
    }

    expect(problems, isEmpty,
        reason: '每个底部弹层都要套 GlassSheetPanel（把手只有那一处）:\n'
            '${problems.join('\n')}');
    // 兜底：扫到的弹层数不该比现在少（否则是剥壳过头或目录变了，恒绿）。
    expect(totalSheets, greaterThanOrEqualTo(11),
        reason: '全 app 现有 11 个底部弹层，扫到 $totalSheets 个就说明扫漏了');
    expect(files, greaterThan(50), reason: '扫到的文件数太少，路径或剥壳有问题');
  });
}
