// app/tool/visual/text_fit_guard_test.dart
//
// **常设护栏：全 app 不许把字悄悄吃掉。**
//
// 起因（用户 2026-10-13 报的，真我 GT7 Pro）：日历顶栏把「2026年10月」显示成
// 「2026年1…」。一份一次性探针量下来，**39 屏里有 28 屏**在「窄屏 × 大字号」下
// 有字被省略 —— 而在这条护栏之前，整个工装的唯一断言是「有没有布局溢出」，
// **这一整类它一个字都不会说**（界面从来不炸、不裁切，它只是安静地省略）。
//
// 判据有**两条**，缺一不可：
//
//   ① 段落自己按 `maxLines` 截了 —— `didExceedMaxLines`。
//   ② **容器把段落裁短了** —— 这一种 `didExceedMaxLines` 是 `false`，只查①会瞎。
//      典型是 `ListTile`：副标题写 `maxLines: 2` 而不加 `isThreeLine`，Tile 会把
//      第二行直接裁掉，而段落自己认为「我没被截」。
//
// 档位矩阵见下面的 `_configs`：**我们提供的每一档 × 两个保证宽度 × 中英双语**。
// 深色档不改变文字排版，不单独跑。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

import 'visual_harness.dart';
import 'visual_screens.dart';

// `truncatedParagraphs` / `kDeliberateEllipsis` 已抽进 `visual_harness.dart`
// —— 单屏的用例（Task 5~8）也要用它，抄两份迟早走样。

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await ensureVisualFonts();
  });
  setUp(setUpVisualPrefs);

  // ── 判据自己先立住 ──
  //
  // 构造两处**已知**的截断，确认两条判据各自抓得住。少了这一条，护栏红了也
  // 分不清是「真的有东西被截」还是「判据写错了」。
  testWidgets('判据能抓住两种截断', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: <Widget>[
          // 方式 1：段落自己按 maxLines 截
          SizedBox(
            width: 80,
            child: Text('这一串字在八十像素里一定放不下',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          // 方式 2：容器给的高度比段落**需要**的小 —— 段落自己不知道被裁了。
          // 用 `SizedBox(height:)` 给死高度是真机制（实测过：`ListTile` 的副标题
          // **不会**被裁，它会把整块长高；所以别拿 ListTile 当这个判据的样本）。
          //
          // 这段字在这个宽度下要占三行，而 `maxLines` 给到 6 —— 于是
          // `didExceedMaxLines` 是 false（判据 1 抓不到），而盒子只给了 20px 高。
          SizedBox(
            height: 20,
            width: 60,
            child: Text('这段文字在这一格宽度下要占三行',
                maxLines: 6, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    ));
    final hits = truncatedParagraphs(tester);
    expect(hits.where((h) => h.startsWith('方式 1')), isNotEmpty,
        reason: '段落自己截的没抓到');
    expect(hits.where((h) => h.startsWith('方式 2')), isNotEmpty,
        reason: '容器裁短的那种没抓到 —— 只查 didExceedMaxLines 会瞎');
  });

  // ── 全屏 × 每一档 × 两个保证宽度 × 中英 ──
  // 矩阵：**保证线（320/360）× 每一档 × 中英**，外加两格既有档位的冒烟
  // （420×900 常见机、200×400 小窗）—— 独立审查指出原先少了它们，而
  // 小窗与横屏正是「最容易顺手弄坏、又最不容易被看见」的两档。
  //
  // `strict: false` 的那两格是**冒烟**：只把发现**打出来**、不算失败。
  // 小窗（200×400）里编辑排班那种「一行并排三个控件」的版式**物理上放不下**
  // 标签（标签字段只剩个位数宽度），要它不省略得把那一行改成两行排 —— 那是
  // 独立的一件事，见 spec §8 的「200×400 冒烟」（原先写的就是冒烟）。
  // **但发现照样打在输出里** —— 故意不查的东西要看得见（同 `design_tokens_test`
  // 的豁免规矩）。
  const configs = <({
    String label,
    Size size,
    AppFontSize font,
    String lang,
    bool strict
  })>[
    (label: '320·小·中', size: Size(320, 640), font: AppFontSize.small, lang: 'zh', strict: true),
    (label: '320·标准·中', size: Size(320, 640), font: AppFontSize.standard, lang: 'zh', strict: true),
    (label: '320·大·中', size: Size(320, 640), font: AppFontSize.large, lang: 'zh', strict: true),
    (label: '320·特大·中', size: Size(320, 640), font: AppFontSize.extraLarge, lang: 'zh', strict: true),
    (label: '320·标准·英', size: Size(320, 640), font: AppFontSize.standard, lang: 'en', strict: true),
    (label: '320·大·英', size: Size(320, 640), font: AppFontSize.large, lang: 'en', strict: true),
    (label: '320·特大·英', size: Size(320, 640), font: AppFontSize.extraLarge, lang: 'en', strict: true),
    (label: '360·小·中', size: Size(360, 780), font: AppFontSize.small, lang: 'zh', strict: true),
    (label: '360·标准·中', size: Size(360, 780), font: AppFontSize.standard, lang: 'zh', strict: true),
    (label: '360·大·中', size: Size(360, 780), font: AppFontSize.large, lang: 'zh', strict: true),
    (label: '360·特大·中', size: Size(360, 780), font: AppFontSize.extraLarge, lang: 'zh', strict: true),
    (label: '360·特大·英', size: Size(360, 780), font: AppFontSize.extraLarge, lang: 'en', strict: true),
    (label: '420·标准·中', size: Size(420, 900), font: AppFontSize.standard, lang: 'zh', strict: true),
    (label: '420·特大·中', size: Size(420, 900), font: AppFontSize.extraLarge, lang: 'zh', strict: true),
    (label: '小窗·标准·中', size: Size(200, 400), font: AppFontSize.standard, lang: 'zh', strict: false),
    (label: '小窗·特大·中', size: Size(200, 400), font: AppFontSize.extraLarge, lang: 'zh', strict: false),
  ];

  // 收进列表、**最后一次性报**（见文件末尾那条汇总用例）—— 在循环里当场 fail
  // 会让异常抛进帧管线，一轮只看得到第一条，修一条要重跑一次。
  final findings = <String>[];

  for (final screen in visualScreens) {
    for (final cfg in configs) {
      testWidgets('${screen.title} · ${cfg.label}', (tester) async {
        failOnOverflow(tester);
        useStandardGlassTier();
        final db = await makeVisualDatabase();
        final extraPrefs = <String, Object>{
          ...(screen.needsOnboardingPrefs ? onboardingPrefs : const {}),
          ...screenExtraPrefs(screen.slug),
        };
        if (extraPrefs['liquidGlass'] == true) useLiquidGlassTier();
        await pumpScreen(
          tester,
          home: await screen.build(db),
          overrides: <Override>[databaseProvider.overrideWithValue(db)],
          size: cfg.size,
          fontSize: cfg.font,
          language: cfg.lang,
          extraPrefs: extraPrefs,
        );
        for (final hit in truncatedParagraphs(tester)) {
          final line =
              '${screen.slug}（${screen.title}）· ${cfg.label} ▸ $hit';
          if (cfg.strict) {
            findings.add(line);
          } else {
            // 冒烟档：发现照样**打出来**，只是不判失败（理由见上面 `configs`）。
            debugPrint('[text-fit-guard 冒烟] $line');
          }
        }
        await teardownVisual(tester);
        await db.close();
      });
    }
  }

  // 班组设置**展开态**：主矩阵渲染的是首屏，班组卡在很下面、根本不会被构建。
  // 这条滚到展开的班组卡再查两种截断 —— 不给 `initialCrewExpanded` 这条路的话，
  // 它会在一张永远收起的卡上通过，等于没验。
  for (final cfg in configs.where((c) => c.strict)) {
    testWidgets('班组设置展开 · ${cfg.label}', (tester) async {
      failOnOverflow(tester);
      useStandardGlassTier();
      final db = await makeVisualDatabase();
      await pumpScreen(
        tester,
        home: ScheduleEditorScreen(
          scheduleId: await currentScheduleId(db),
          initialCrewExpanded: true,
        ),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        size: cfg.size,
        fontSize: cfg.font,
        language: cfg.lang,
        extraPrefs: onboardingPrefs,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('crew-name-0')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      for (final hit in truncatedParagraphs(tester)) {
        findings.add('67_editor_crew_expanded · ${cfg.label} ▸ $hit');
      }
      await teardownVisual(tester);
      await db.close();
    });
  }

  // 汇总。**声明顺序就是执行顺序**，所以它一定跑在全部屏之后。
  test('汇总：这一轮谁把字吃掉了', () {
    if (findings.isEmpty) return;
    fail('字被吃掉了（${findings.length} 处）：\n${findings.join('\n')}');
  });
}
