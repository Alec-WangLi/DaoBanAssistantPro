// app/test/widget_cell_block_guard_test.dart
//
// 桌面小组件那几张卡底的**结构不变量**。Kotlin 在这个仓库里没有可跑的测试目标
// （真机是唯一的眼睛），所以这一族护栏只能**扫源码**：它们证明不了「画出来好不好
// 看」，只证明「该在的东西都在、该成对的都成对、两个方向的状态都设满了」。
//
// 与 `widget_fixed_cards_guard_test.dart` 同一套路、同一份家法。
//
// ⚠️ 这一族是**分任务长大**的（见实施计划）：本文件在任务 1 只守资源，
// 任务 2 加月历格那三条，任务 3 扩到周条并把下界提到 6，任务 4 提到 7。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/theme/app_colors.dart';

/// 读一个相对 `app/` 的文件（Dart 测试的工作目录就是 `app/`）。
String _read(String rel) {
  final f = File(rel);
  expect(f.existsSync(), true,
      reason: '$rel 不存在 —— 要么实现还没做，要么这条护栏自己跟源码对不上了');
  return f.readAsStringSync();
}

void main() {
  test('四张资源成对存在：格子卡底与页面底，浅深各一', () {
    for (final base in ['widget_cell', 'widget_page']) {
      for (final tier in ['light', 'dark']) {
        final f = File('android/app/src/main/res/drawable/${base}_$tier.xml');
        expect(f.existsSync(), true,
            reason: '${base}_$tier.xml 不在 —— 少一张就是**某一档静默没有底**'
                '（另一档看不出来，真机上只有把系统切过去才会现形）');
      }
    }
  });

  test('页面底必须不透明（97% 会跌破 AA）', () {
    for (final tier in ['light', 'dark']) {
      final src = _read('android/app/src/main/res/drawable/widget_page_$tier.xml');
      final colors = RegExp(r'#([0-9A-Fa-f]{8})')
          .allMatches(src)
          .map((m) => m.group(1)!.toUpperCase())
          .toList();
      // 自证：扫不到色值时这条护栏是句空话，必须红。
      expect(colors.length, greaterThanOrEqualTo(2),
          reason: '页面底应当有渐变的两端色 —— 只扫到 ${colors.length} 个 8 位色值，'
              '要么资源被改回了单色，要么这条正则跟源码对不上了');
      for (final c in colors) {
        expect(c.substring(0, 2), 'FF',
            reason: '页面底 $tier 档有一个半透明端（#$c）—— 叠黑壁纸时 wg_muted '
                '只有 4.33:1，跌破 AA 4.5。这个数在 spec §5 里算过，别改成 97%');
      }
    }
  });

  test('两张 cell 布局都有「今天」那块 ImageView，且 id 与 Kotlin 引用逐字一致', () {
    void check(String layout, String id) {
      final kt = _read(
          'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
      final xml = _read('android/app/src/main/res/layout/$layout.xml');
      expect(RegExp('android:id="\\@\\+id/$id"').hasMatch(xml), true,
          reason: '$layout.xml 里没有 $id —— 块画不出来，而且**不报错**');
      // 两个方向都要设满：只 setImageViewBitmap 不 setViewVisibility(GONE)，
      // 翻月 / 翻周之后非今天那一格会挂着上一次的块（宿主 reapply 只重放新动作）。
      expect(kt.contains('R.id.$id'), true,
          reason: 'WidgetRenderer.kt 里没引用 $id —— 布局改了、Kotlin 没跟');
      expect(kt.contains('R.id.$id, android.view.View.GONE'), true,
          reason: '$id 没有显式 GONE 那一支 —— 块会残留到别的格子上');
    }

    check('widget_month_cell', 'wg_mc_block');
    check('widget_strip_cell', 'wg_sc_block');
  });

  test('「今天」块的位图尺寸来自 AppWidgetOptions，不是写死的', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    expect(kt.contains('WidgetChip.block('), true, reason: '一处都没用上块原语');
    for (final fn in ['monthCellPx', 'stripCellPx']) {
      final i = kt.indexOf('private fun $fn');
      expect(i, greaterThanOrEqualTo(0), reason: '$fn 不见了');
      final body = kt.substring(i, kt.indexOf('\n    }', i));
      expect(body.contains('OPTION_APPWIDGET_MIN_WIDTH'), true,
          reason: '$fn 没读 AppWidgetOptions —— 尺寸写死的话，5 行月与 6 行月'
              '（格子高差约 18%）里必有一档的圆角被拉变形、四角露出白卡的角尖');
      expect(body.contains('OPTION_APPWIDGET_MIN_HEIGHT'), true,
          reason: '同上，高度那一路');
    }
  });

  test('月历「今天」那格的字**不许**走 onSolidInk（块是半透明的浅底）', () {
    // 2026-10-15 反转：那枚块从实心改回**半透明**之后，块上字走 `onSolidInk` 就会
    // 在 teal / orange 上给白字 —— 白压浅底读不出来，而且是**静默**的（默认那颗蓝
    // 选出来是对的，只有换到浅主色才现形）。
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    final monthCard = kt.substring(
      kt.indexOf('private fun monthCard('),
      kt.indexOf('private fun stripCellPx('),
    );
    expect(monthCard.length, greaterThan(500), reason: '没截出 monthCard —— 护栏自己跟源码对不上了');
    expect(monthCard.contains('onSolidInk(context,'), false,
        reason: 'monthCard 里还有 onSolidInk 的调用 —— 半透明块是浅底，那会给白字');
    expect(monthCard.contains('glassBlock'), true, reason: '块没换成半透明那一支');

    // 而周条那一列与今日卡的「今天」药丸**仍然**要它（那两处还是实心块，
    // 药丸更是白字压主色）。这是一个**下界**：4 处 = 周条三处 + 今日卡药丸一处。
    final uses = RegExp(r'onSolidInk\(context, ').allMatches(kt).length;
    expect(uses, greaterThanOrEqualTo(4),
        reason: 'onSolidInk 的调用点只剩 $uses 处 —— 周条三处 + 今日卡药丸一处应当凑齐 4 处');
  });

  test('半透明块上的字：五种主色下 ink 都过 AA，而白字都过不了', () {
    // Review Focus 第 2 条（规格 §5）：今天那格的块从实心改成半透明之后，
    // 块上字改走中性 `ink`。这条把「为什么必须改」也算出来 —— 旧代码走
    // `onSolidInk(accent)`（黑/白二选一），而对 **teal** 它会选白字，白字压在
    // 「白卡 + 22% teal」这种浅底上根本读不出来。
    //
    // 这是**静默**的：默认那颗蓝选出来是对的，只有换到浅主色才现形。
    for (final accent in AppColors.accentPalette) {
      // 块的最深那一端（22%）叠在白卡上 —— 那是对深字最不利的一档。
      final blockOverCard =
          Color.alphaBlend(accent.withValues(alpha: 56 / 255), Colors.white);
      const ink = Color(0xFF111118); // wg_ink_light
      expect(AppTokens.contrastRatio(ink, blockOverCard), greaterThanOrEqualTo(4.5),
          reason: '$accent 下 ink 压在半透明块上只有 '
              '${AppTokens.contrastRatio(ink, blockOverCard).toStringAsFixed(2)}:1');

      // 自证这条判据有鉴别力：**白字**压在同一块上过不了 AA。
      // （旧做法走 `onSolidInk(accent)` —— 那是「按**实心主色**在黑/白里二选一」，
      //  而半透明块是浅底，两者的底色根本不是一回事。它今天恰好没选中白色，
      //  但那是巧合，不是保证 —— 所以块上字改成写死的中性 `ink`。）
      expect(AppTokens.contrastRatio(Colors.white, blockOverCard), lessThan(4.5),
          reason: '$accent 下白字居然过得去？那这条判据就抓不住「选错字色」这一类');
    }
  });

  test('页面底的**每一个**端色都要让 muted 过 AA', () {
    // 这条是补一个真实的漏：判「不透明」只查了 alpha 是不是 FF，
    // 于是渐变**暗端** #F1F3F8 上 muted 只有 4.487:1（差 0.013 就不过 AA）也没人报。
    // 现在按端色逐个真算对比度。
    final colors = _read('android/app/src/main/res/values/widget_colors.xml');
    int token(String name) {
      // ⚠️ 收 6 位与 8 位两种写法：`widget_colors.xml` 里两种都有
      // （`wg_muted_light` 是 `#6E6E82`，格子卡底是 `#FFFFFFFF`）。
      final m = RegExp('<color name="$name">#([0-9A-Fa-f]{6,8})</color>')
          .firstMatch(colors);
      expect(m, isNotNull, reason: '$name 不见了');
      final hex = m!.group(1)!;
      return int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    }

    for (final tier in ['light', 'dark']) {
      final src = _read('android/app/src/main/res/drawable/widget_page_$tier.xml');
      final ends = RegExp(r'#([0-9A-Fa-f]{8})')
          .allMatches(src)
          .map((m) => int.parse(m.group(1)!, radix: 16))
          .toList();
      expect(ends.length, greaterThanOrEqualTo(2),
          reason: '页面底 $tier 档扫不到两端色 —— 正则跟源码对不上了');
      final ink = Color(token('wg_muted_$tier'));
      for (final e in ends) {
        final r = AppTokens.contrastRatio(ink, Color(e));
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '页面底 $tier 档的端色 #${e.toRadixString(16)} 上，'
                'muted 只有 ${r.toStringAsFixed(3)}:1 —— 跌破 AA 4.5');
      }
    }
  });

  test('「今天」块的尺寸在循环**外**算，且行数来自 monthGridRows', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    // ① 尺寸不能放在 42 格的循环里：`getAppWidgetOptions` 是一次 binder IPC，
    //    一格一次就是每次渲染 42 次。
    // ⚠️ 取**最后**一个 42 格循环：`monthGridRows` 自己也有一个「数 42 个槽位」的
    // 循环，而它排在 `monthCard` **前面** —— 拿 `indexOf` 会对着那个比，结论正好相反
    // （这条护栏第一版就是这么错的：它报「在循环里」，而代码其实已经提到了循环外）。
    final loop = kt.lastIndexOf('for (slot in 0 until 42)');
    expect(loop, greaterThanOrEqualTo(0), reason: '月历那个 42 格循环不见了');
    final calls = RegExp(r'monthCellPx\(').allMatches(kt).toList();
    expect(calls.length, 2,
        reason: 'monthCellPx 出现了 ${calls.length} 次（应当是「定义 1 次 + 调用 1 次」）');
    final callAt = calls.last.start;
    expect(callAt, lessThan(loop),
        reason: 'monthCellPx 的调用落在 42 格循环**里面**了 —— 一格一次 binder IPC，'
            '应当提到循环外（`stripCellPx` 就是这么做的）');
    // ② 行数必须真的喂进去：写死 rows = 6 的话，5 行月那格会偏矮、四角露白尖。
    final m = RegExp(r'monthCellPx\(context, widgetId, (\w+)\)').firstMatch(kt);
    expect(m, isNotNull,
        reason: 'monthCellPx 的第三个实参不是变量 —— 行数写死就失去了「按真实行数反推」的意义');
    final arg = m!.group(1)!;
    expect(kt.contains('val $arg = monthGridRows('), true,
        reason: '传给 monthCellPx 的 $arg 不是 monthGridRows(...) 算出来的');
  });

  test('两张 cell 布局里，块排在内容**之前**（后画的盖在上面）', () {
    // 层序反了 = 块盖住日期与胶囊，而「id 存在」「有 GONE 分支」两条照样绿 ——
    // 与 `AGENTS.md` 里 `removeAllViews` 那条「只查出现过、不查顺序」是同一类缺口。
    for (final entry in {
      'widget_month_cell': 'wg_mc_block',
      'widget_strip_cell': 'wg_sc_block',
    }.entries) {
      final xml = _read('android/app/src/main/res/layout/${entry.key}.xml');
      final block = xml.indexOf('android:id="@+id/${entry.value}"');
      final content = xml.indexOf('<LinearLayout');
      expect(block, greaterThanOrEqualTo(0), reason: '${entry.key} 里没有 ${entry.value}');
      expect(content, greaterThanOrEqualTo(0), reason: '${entry.key} 里没有内容层');
      expect(block, lessThan(content),
          reason: '${entry.value} 排在了内容**之后** —— 那一层会盖住日期与胶囊，'
              '而真机上看起来就是「格子里什么都没有」');
    }
  });

  test('月历胶囊：**文字**驱动宽度、位图贴上去（不是位图驱动尺寸）', () {
    // 2026-10-16 反转。上一版（v0.11.23）是「位图驱动尺寸、宽度写死 40dp × 缩放」——
    // 那在格子小的时候会把胶囊顶到格边：真机量到占格宽 **95.5%**，而 App 里同一颗
    // 只有 **81%**（用户原话：「跟里边班次的胶囊又重合了……APP 里边其实不重合，有点间隙」）。
    // 现在反过来：**TextView 按简称现量**决定宽度，位图贴满它。
    final xml = _read('android/app/src/main/res/layout/widget_month_cell.xml');
    expect(xml.contains('android:layout_width="40dp"'), false,
        reason: '胶囊盒子还写着 40dp —— 那是个定值，格子一小就顶满格宽');
    final pill = xml.indexOf('android:id="@+id/wg_mc_pill"');
    final abbr = xml.indexOf('android:id="@+id/wg_mc_abbr"');
    expect(pill, greaterThanOrEqualTo(0), reason: '没有 wg_mc_pill');
    expect(abbr, greaterThanOrEqualTo(0), reason: '没有 wg_mc_abbr');
    expect(pill, lessThan(abbr), reason: '胶囊底要排在简称之前（后画的在上面）');

    // 位图那层只负责贴满：两个方向都 match_parent
    final pillBlock = xml.substring(pill, abbr);
    expect(pillBlock.contains('layout_width="match_parent"'), true,
        reason: 'wg_mc_pill 不是 match_parent —— 它贴不满 TextView 量出来的宽度');
    expect(pillBlock.contains('layout_height="match_parent"'), true);

    // 简称那层是**宽度驱动者**：wrap_content + 居中 + 左右内边距（与 Kotlin 侧那 4dp 对齐）
    // ⚠️ 拿 `/>` 当右界 —— 这个文件里的 TextView 都是自闭合的，找 `</TextView>` 会返回 -1。
    final abbrBlock = xml.substring(abbr, xml.indexOf('/>', abbr));
    expect(abbrBlock.contains('layout_width="wrap_content"'), true,
        reason: 'wg_mc_abbr 不是 wrap_content —— 那它就不是宽度的驱动者');
    expect(abbrBlock.contains('layout_gravity="center"'), true,
        reason: '简称没有在（可能比它宽的）位图里居中');
    expect(abbrBlock.contains('paddingHorizontal="4dp"'), true,
        reason: '简称没有左右内边距 —— 文字会贴着胶囊边');
  });

  test('胶囊位图宽度来自**文字现量**，不是写死的比例', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    expect(kt.contains('measureText'), true,
        reason: '胶囊宽度没按简称现量 —— 定值宽度在格子小的时候会顶满格宽，'
            '与格子重合（实测占 95.5%，App 只有 81%）');

    final monthCard = kt.substring(
      kt.indexOf('private fun monthCard('),
      kt.indexOf('private fun stripCellPx('),
    );
    expect(monthCard.length, greaterThan(500), reason: '没截出 monthCard');
    expect(monthCard.contains('chipWidthPx'), true,
        reason: 'monthCard 还在用写死的胶囊宽度');
    expect(monthCard.contains('40f * cellScale'), false,
        reason: '月历胶囊宽度还是「40dp × 缩放」那个定值');
  });
}
