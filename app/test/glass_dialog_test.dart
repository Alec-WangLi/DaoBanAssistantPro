// app/test/glass_dialog_test.dart
//
// `GlassDialog` 的**动作行几何**：靠右、窄弹层里折行、每颗都留在面板里。
//
// 这一条是补 v0.9.18 欠下的账。那一版为了让小窗下「删除 / 取消 / 保存」三颗
// 按钮不横向溢出，把动作行从 `Row(mainAxisAlignment: end)` 换成了
// `Wrap(alignment: WrapAlignment.end)` —— **溢出不溢出了，但整行跑到左边去了**，
// 而且不是一处：全 app 二十来个弹窗走的是同一个 `GlassDialog`
// （版本更新的「知道了」、删除确认、时段弹层、重复待办面板……），一处改错、
// 处处靠左，用户 2026-10-01 真机一眼看出来（「好多按钮都跑到左边去了」）。
//
// 根因是两种组件的**宽度行为不一样**：`Row` 默认 `mainAxisSize.max`，会把整行
// 撑满、`end` 才有富余可对齐；`Wrap` 收缩到**内容宽度**，外层 Column 又是
// `crossAxisAlignment.start`，于是整块贴左，`WrapAlignment.end` 在「自己就是内容
// 那么宽」时不起任何作用。
//
// 所以这两条用例必须**一起**存在：
//   1. 正常宽度 —— 最后一颗按钮贴着面板内容右缘（靠右，这条是新的）；
//   2. 窄弹层 —— 三颗按钮折行、且一颗都不越出面板（v0.9.18 修的那条，别退化）。
// 只留其中一条，另一种错法就能悄悄回来。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_action_button.dart';
import 'package:shiftassistantpro/core/widgets/glass_dialog.dart';

/// 面板左右各 20 的内边距（`GlassDialog` 的 `EdgeInsets.fromLTRB(20, 20, 20, 16)`）。
/// 断言「按钮贴到内容右缘」时用它换算 —— 写死数字会和那处 padding 各改各的。
const double _panelPad = 20;

/// 面板那道 1px 描边（`Border.all(...)`，宽度用默认值）。它在 **padding 之外**，
/// 所以内容右缘是 `panel.right - 1 - 20`。第一版漏了它，量出来差整 1.0 ——
/// 别靠放宽公差糊过去，那会把「差 1px」和「差一整行」一起放行。
const double _panelBorder = 1;

/// 面板**内容**的右缘：按钮该贴到的那条线。
double _contentRight(Rect panel) => panel.right - _panelBorder - _panelPad;

Widget _dialogWith(List<Widget> actions, {Widget? content}) => GlassDialog(
      title: '删除排班',
      content: content ?? const Text('删掉之后这几天就没有排班了。'),
      actions: actions,
    );

/// 长到必须滚的内容：末行带 key，用来断言「滑到底时它整个在按钮之上」。
Widget _longContent() => Column(
      key: const Key('long-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 40; i++) Text('第 $i 行内容，这一段是用来把弹窗撑到必须滚动的。'),
        const Text('末行', key: Key('last-line')),
      ],
    );

/// 三颗按钮的弹窗 —— 全 app 真正的形态（删除 / 取消 / 保存）。
List<Widget> _threeActions() => [
      GlassActionButton(
        variant: GlassActionVariant.danger,
        onPressed: () {},
        label: L10n.delete,
      ),
      const SizedBox(width: 8),
      GlassActionButton(onPressed: () {}, label: L10n.cancel),
      const SizedBox(width: 8),
      GlassActionButton(
        variant: GlassActionVariant.primary,
        onPressed: () {},
        label: L10n.save,
      ),
    ];

Future<void> _open(WidgetTester tester, Size size, {Widget? content}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierColor: Colors.black26,
              builder: (_) => _dialogWith(_threeActions(), content: content),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Rect _panel(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('glass-dialog-panel')));

Rect _action(WidgetTester tester, String label) =>
    tester.getRect(find.widgetWithText(GlassActionButton, label));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  setUp(() => L10n.locale = 'zh');

  testWidgets('动作靠右：最后一颗的右边缘贴着面板内容右缘', (tester) async {
    await _open(tester, const Size(420, 900));

    final panel = _panel(tester);
    final last = _action(tester, L10n.save);

    // **判据只有这一条，而且它有鉴别力**：改回 `Wrap` 收缩宽度那版，这颗按钮的
    // 右边缘会落在面板左半部分（约等于左侧内边距 + 两颗按钮的宽度），差着一整行。
    expect(last.right, closeTo(_contentRight(panel), 0.5),
        reason: '弹窗的动作行必须贴右；贴左说明整行没有被撑满');
  });

  testWidgets('窄弹层（200×400）：三颗按钮折行、一颗都不越出面板、仍然靠右',
      (tester) async {
    // 这一档的弹层内宽只剩约 112dp，三颗按钮排不下 —— v0.9.18 修的横向溢出
    // 就在这里现形。`Wrap` 折行是**不变的**，别为了恢复靠右把它退回 `Row`。
    await _open(tester, const Size(200, 400));

    final panel = _panel(tester);
    final rects = {
      for (final label in [L10n.delete, L10n.cancel, L10n.save])
        label: _action(tester, label),
    };

    for (final entry in rects.entries) {
      expect(
          entry.value.left,
          greaterThanOrEqualTo(panel.left + _panelBorder + _panelPad - 0.5),
          reason: '${entry.key} 越出面板左缘');
      expect(entry.value.right, lessThanOrEqualTo(_contentRight(panel) + 0.5),
          reason: '${entry.key} 越出面板右缘（横向溢出的老毛病）');
    }

    expect(rects.values.map((r) => r.top).toSet().length, greaterThan(1),
        reason: '内宽 112 装不下三颗 —— 必须折成两行');

    expect(rects[L10n.save]!.right, closeTo(_contentRight(panel), 0.5),
        reason: '折行之后最后一行同样要贴右');
  });

  // ---------------------------------------------------------------------------
  // 动作行浮在正文上
  // ---------------------------------------------------------------------------
  //
  // 用户 2026-10-01 真机反馈：「版本更新和使用帮助这两个界面，不也有胶囊按钮吗？
  // 它底下有个类似蒙版的东西，我们要的是让它悬浮在上边。」
  //
  // 那块「蒙版」是内容区**在动作行上沿被硬切**：`Column[标题, 可滚内容, 动作行]`
  // 里内容区的视口到按钮就结束了，滚动时正文被齐刷刷切断、下面是面板底部的空白 ——
  // 读起来就像有块板子压着正文。走同一个件的**每个**弹窗都中招（版本更新 / 使用帮助 /
  // 检查更新 / 重复待办管理 / 我的模板 / 日志），内容越长越明显。
  //
  // 修法：内容区铺满整块面板、动作行浮在它上面，内容自己留一段等于按钮高的底部空白。
  group('动作行浮在正文上', () {
    Finder scrollView() => find.byType(SingleChildScrollView);

    testWidgets('内容的视口铺到面板底边（不再在按钮上沿被切断）', (tester) async {
      await _open(tester, const Size(420, 900), content: _longContent());

      final panel = _panel(tester);
      final view = tester.getRect(scrollView().first);
      // 反面：改之前这里等于「动作行的上沿」—— 面板底边再往上「按钮行 + 两处 16 间距」，
      // 那段差就是用户看到的那条硬边。
      expect(view.bottom, closeTo(panel.bottom - _panelBorder - 16, 0.5),
          reason: '内容区要一直铺到面板底边 —— 停在按钮行上沿就是那块「蒙版」');
      expect(view.bottom, greaterThan(_action(tester, L10n.save).top),
          reason: '内容要伸到按钮**下面**去，而不是到它上沿就停');
    });

    testWidgets('滑到底：最后一行整个抬到按钮之上', (tester) async {
      await _open(tester, const Size(420, 900), content: _longContent());

      await tester.drag(scrollView().first, const Offset(0, -4000));
      await tester.pumpAndSettle();

      final last = tester.getRect(find.byKey(const Key('last-line')));
      final save = _action(tester, L10n.save);
      expect(last.bottom, lessThanOrEqualTo(save.top - 8),
          reason: '滑到底之后最后一行要整个在按钮之上（留 8 的让位）—— 不然它被按钮压着看不全');
      expect(last.top, greaterThan(0), reason: '末行确实在屏幕上，不是滚过头了');
    });

    testWidgets('短内容与从前一致：正文与按钮之间仍是 16 的间距', (tester) async {
      await _open(tester, const Size(420, 900));

      final view = tester.getRect(scrollView().first);
      final text = tester.getRect(find.text('删掉之后这几天就没有排班了。'));
      final save = _action(tester, L10n.save);
      expect(save.top - text.bottom, closeTo(16, 1),
          reason: '短弹窗里按钮就贴着正文下方 16 —— 浮起来之后这条间距不该变');
      expect(view.bottom, greaterThan(save.top),
          reason: '内容区的视口同样铺到面板底边（只是内容没长到那儿）');
    });
  });
}
