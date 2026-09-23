// app/lib/features/calendar/info_card_metrics.dart

/// 判定底栏信息卡该有多高。
///
/// **为什么要算而不是写死**：这一页竖屏是 `Column[顶栏, Expanded(网格), 信息卡]`，
/// 格子高度按**剩余空间**均分 —— 卡片只要随当天内容长高一像素，六个格子就集体
/// 矮一像素、选下一天再弹回来。所以卡片必须定高。
///
/// 但「定高」定成多少是个难题。曾经写死 248，代价有三层：
///   1. 248 是拿**最满的一天**标定的，内容少的日子下部空出一大截；
///   2. 最满的一天随**宽度、语言、系统字号**变，248 在窄屏 / 放大字号下装不下，
///      而卡片装不下时只在卡内静默滚动 —— 用户看到的是最后一行被裁掉；
///   3. 想把它调小一点，就得重新标定一次最坏情况，而最坏情况是随设备变的。
///
/// 所以改成**算**：取当前月里最满的那一天，量出它需要多高，卡片就多高。于是
/// 卡片永远是「这个月刚好够用」的高度，内容不裁、网格拿到全部剩余空间，而且
/// 不再依赖任何一台设备的字体度量。
///
/// 代价只有一个：**换月时卡片高度可能变一次**。换月是主动操作，不是点日期，
/// 点日期仍然逐像素不变。
///
/// 量的是**真实排版**：所有文字都用 [TextPainter] 按卡片里同一份样式与同一份
/// 约束排一遍，所以字体换了、字号被系统放大了，算出来的高度跟着走。
///
/// 算不算得准由 `calendar_screen_test.dart` 的「点开某天」用例盯着：它把整月
/// 每一天都点一遍，断言内容真的装得进算出来的高度。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../domain/lunar_info.dart';
import '../../domain/shift_rotation.dart';

/// 卡片**内部**的垂直固定开销：上下内边距 `spaceLg`×2 + 描边 1×2（[GlassTile]
/// 的 `Border.all(width: 1)`，`Container` 会把它算进自己的内边距）。
///
/// 写成 token 算式而不是 34，是为了和渲染侧同源：渲染侧的内边距就在
/// `calendar_screen.dart` 的 `GlassTile(padding: …)` 里，改那一处这里跟着走。
const double _cardChromeV = AppTokens.spaceLg * 2 + 2;

/// 同理，左右各是 `spaceXl`(20) / `spaceLg`(16) 的内边距与 1 的描边 ——
/// 内容区比卡片外框窄这么多。
const double _cardChromeH = AppTokens.spaceXl + AppTokens.spaceLg + 2;

/// 段落间距，与 `_infoCard` 里的取值一一对应。
const double _gapAfterDate = AppTokens.spaceSm; // 8
const double _gapAfterBadge = AppTokens.spaceXs; // 4
const double _gapBetweenSections = AppTokens.spaceMd; // 12

/// 「其他班组」色块的形状与排布，与 `_otherCrewChips` / `Wrap` 一一对应。
const double _chipGapX = AppTokens.spaceSm; // 8 — Wrap.spacing
const double _chipGapY = AppTokens.gapIconText; // 6 — Wrap.runSpacing
const double _chipPadH = 8;
const double _chipPadV = AppTokens.padChipV; // 3
const double _chipBorder = 1; // Border.all(width: 1)
const double _chipDot = 8;
const double _chipDotGap = AppTokens.gapIconText; // 6 — 色点↔文字
/// 班次行行首那个圆点的直径（`Container(width: 12, height: 12)`）。
const double _shiftDot = 12;
/// 标签「其他班组」与色块之间的间隔，以及标签自己的上内边距
/// （`Padding(top: AppTokens.spaceXs)`，与色块文字的实际起点对齐）。
const double _otherCrewsLabelGap = 8;
const double _otherCrewsLabelTop = AppTokens.spaceXs; // 4

/// 底栏信息卡高度的测算结果。
///
/// [outerHeight] 是卡片**外框**高度（竖屏 / 短屏非紧凑形态）。[dayContentHeights]
/// 是本月的逐日内容高度（下标 0 = 1 号，不含卡片内边距与描边），给「这一天还剩多少
/// 富余」用 —— 卡片里那行「本月统计」就靠它决定画不画（见 [slackOn]）。
class InfoCardMetrics {
  const InfoCardMetrics({
    required this.outerHeight,
    required this.dayContentHeights,
  });

  final double outerHeight;
  final List<double> dayContentHeights;

  /// 卡片**内容区**高度：外框减去上下内边距与描边（与渲染侧同源，见 [_cardChromeV]）。
  double get innerHeight => outerHeight - _cardChromeV;

  /// [dayOfMonth]（1 起）那天的内容装进卡片之后还剩多少垂直富余。
  ///
  /// 这是**卡片高度一个像素都不用动**就能把空白用起来的全部秘密：高度按月定死，
  /// 富余只有多少之分，没有「卡片跟着当天长」这回事（那会把网格带得一起抖）。
  ///
  /// 富余可能为负 —— 逐日用的是**按月闸门**算出来的高度（日期行给「待办徽章」、
  /// 班次行给「已调整」胶囊各留了一份，见 [measureBottomInfoCardHeight]），它 ≥
  /// 那天实际渲染出来的高度。也就是说这里偏保守：宁可少画一次，也不裁字。
  double slackOn(int dayOfMonth) {
    final i = dayOfMonth - 1;
    if (i < 0 || i >= dayContentHeights.length) return 0;
    return innerHeight - dayContentHeights[i];
  }
}

/// 底栏信息卡的外框高度（竖屏 / 短屏非紧凑形态）。
///
/// [cardOuterWidth] 是卡片**外框**宽度（还没扣内边距与描边）。[month] 只用到
/// 年月，用来枚举这个月有哪些天。
///
/// [hasTodoHint] 表示这个月里存在待办 —— 有的话日期行要按「今天/待办徽章」的
/// 高度预留（见 [_todoHintH]）。按月而不是按天：按天算的话，点一天卡片高度就
/// 变一次，上面的网格跟着抖 —— 那正是这个文件要消灭的东西。
///
/// [hasOverrideHint] 同理，管的是班次行尾巴上那颗「已调整」胶囊（见
/// [_adjustedBadgeH]）：这个月里有被按天调整过的日子才要预留。也按月。
///
/// **高度是「逐日取大」的结果，不是把各项的月内最大值相加。** 后者会把「A 天有
/// 节假日徽章」「B 天色块折三行」「C 天的农历描述两行」叠成一天的高度，而一个月里
/// 没有哪天真需要那么高 —— 多出来的部分白占网格。逐日算这一天自己的总和、再取
/// 最大，才是这个月实际需要的高度。代价只有一个：换月时高度可能变一次。
InfoCardMetrics measureBottomInfoCardHeight({
  required BuildContext context,
  required double cardOuterWidth,
  required ShiftSchedule? schedule,
  required DateTime month,
  required bool hasTodoHint,
  required bool hasOverrideHint,
}) {
  final measure = _Measure(
    // 卡片里的 `Text` 用的都是 `AppTokens` 的角色令牌，字体族与其它属性来自
    // 环境，所以这里也要按同一套 `DefaultTextStyle` 合并，量出来才和渲染一致。
    // 下面的每个字号都直接引用**卡片渲染所用的同一个令牌对象**。
    def: DefaultTextStyle.of(context),
    scaler: MediaQuery.textScalerOf(context),
  );
  final contentW = cardOuterWidth - _cardChromeH;

  // ── 固定项：与具体哪天无关，量一次即可 ──
  //
  // 日期行。`monthDayWeekday` 在整月里都是「9月25日 周五」这种单行，取任意一天。
  // 「今天」徽章只有一天有，且比日期那 18px 矮，所以不参与取大。
  //
  // 但**待办提示徽章要参与**：它也是这一行里的元素，字号比日期小一档（12px），
  // 却带上下内边距与描边 —— 行高被字体压得紧的时候（测试字体就是），它比日期
  // 那行还高一点点。不把它算进来的话，有待办的那天卡片内容会顶出定高，而没
  // 待办的日子又不会 —— 正是「卡片高度不能随选中哪天变」要防的。
  final dateTextH = measure.text(
    L10n.monthDayWeekday(DateTime(month.year, month.month, 1)),
    AppTokens.sectionTitle,
    maxWidth: contentW,
  ).height;
  final dateH =
      hasTodoHint ? math.max(dateTextH, _todoHintH(measure)) : dateTextH;

  // 班次行：有班次时是「● 上夜班  20:30 – 次日08:30   闹钟 19:30」一行富文本，
  // 时间是 16px，所以行高由 16px 那一档决定；富文本整串 `maxLines: 1`，多长都
  // 只占一行，所以这里不需要拿真的班次名去量宽度。
  final shiftLineH = measure.text(
    '班次',
    AppTokens.titleStrong,
    maxLines: 1,
    maxWidth: contentW,
  ).height;
  // 没有班次的日子走另外两种文案，都可能比班次行矮，取大兜住。
  final noShiftH = measure.text(
    L10n.noSchedule,
    AppTokens.rowSecondary,
    maxWidth: contentW,
  ).height;
  final blankH = measure.text(
    L10n.rest,
    AppTokens.labelStrong,
    maxWidth: contentW,
  ).height;
  // 「已调整」胶囊也塞在**这一行**里（班次行尾巴上），就不新占一行。它是这一行
  // 的一个元素，高度就得一起取大 —— 少了它，有标记的那天行高只按班次那行字算，
  // 内容会顶出定高。它是不是行里最高的那个取决于字体行高与系统字号：紧凑的字体
  // 下（16px 那行字只约 19 —— **示意值，未实量**，实量的是下面两个）胶囊的 21.8
  // 就是最高件，而本仓库测试字体走的 Material
  // 行高 1.43（≈ 22.9）反而比它高 —— 界面侧因此看不见差别，那一步由
  // `calendar_screen_test.dart` 里直接量模型的用例钉住。
  final shiftRowH = [
    shiftLineH,
    noShiftH,
    blankH,
    _shiftDot,
    if (hasOverrideHint) _adjustedBadgeH(measure),
  ].reduce((a, b) => a > b ? a : b);

  final showChips = schedule != null && schedule.teamCount > 1;

  // 「其他班组」那一行是 `Row[标签, 色块]`，高度取两者的大者。标签不折行，
  // 它那份是定值，先算好。这两项与具体哪天无关，逐日的循环里不用重量。
  final otherCrewsLabelH = showChips
      ? measure
              .text(L10n.otherCrews, AppTokens.microText)
              .height +
          _otherCrewsLabelTop
      : 0.0;
  final chipLineH = showChips ? _chipLineH(measure) : 0.0;

  // ── 逐日取大：把**这一天自己**的各项加起来，最后取月内最大的那天 ──
  final days = DateTime(month.year, month.month + 1, 0).day;
  final dayContentHeights = <double>[];
  var maxDayContent = 0.0;

  for (var d = 1; d <= days; d++) {
    final date = DateTime(month.year, month.month, d);
    final lunar = lunarOf(date);

    // 这一天自己的节假日徽章高度（不是这个月里最高的那个徽章）。图标 16 + 小字
    // 「法定节假日」12 + 大字节日名 14，外加 3×2 内边距与 1×2 描边。
    var badgeH = 0.0;
    if (lunar.isLegalHoliday) {
      final textH = measure
          .rich(
            [
              TextSpan(text: L10n.legalHoliday, style: AppTokens.microLabel),
              TextSpan(text: lunar.legalHolidayName, style: AppTokens.labelStrong),
            ],
            maxLines: 1,
            maxWidth: contentW,
          )
          .height;
      badgeH = textH + _chipPadV * 2 + _chipBorder * 2;
    }

    final lunarH = measure.text(
      lunar.fullDescription,
      AppTokens.rowSecondary,
      maxLines: 2,
      maxWidth: contentW,
    ).height;

    var chipsH = 0.0;
    if (showChips) {
      final rows = _chipRows(measure, contentW, schedule, date);
      chipsH =
          math.max(otherCrewsLabelH, rows * chipLineH + (rows - 1) * _chipGapY);
    }

    var dayContent =
        dateH + _gapAfterDate + lunarH + _gapBetweenSections + shiftRowH;
    if (badgeH > 0) dayContent += badgeH + _gapAfterBadge;
    if (showChips) dayContent += _gapBetweenSections + chipsH;

    dayContentHeights.add(dayContent);
    if (dayContent > maxDayContent) maxDayContent = dayContent;
  }

  return InfoCardMetrics(
    outerHeight: maxDayContent + _cardChromeV,
    dayContentHeights: dayContentHeights,
  );
}

/// 卡片底部那行「本月统计」，[dayOfMonth] 这天到底画不画。
///
/// 比的是**这天的富余**（[InfoCardMetrics.slackOn]）：卡片高度按月定死，富余就是
/// 那截空白 —— 够就把这截空白用起来，不够就不画。**永远不为这一行去动卡片高度**，
/// 否则卡片一长，上面六个格子就一起矮（那正是这个文件要消灭的东西）。
///
/// [metrics] 为 null 表示右栏 / 横屏那张卡：那种形态下高度跟着内容走，没有「装不下」
/// 这回事，所以恒为 true。
///
/// 判定里留 1dp 容差：量高的取整与渲染的取整不是同一条路，差一两个 dp 就翻脸的话，
/// 这行会时有时无地闪。宁可退一步不画，也不让它压到内容上。
bool infoCardTallyFits({
  required BuildContext context,
  required InfoCardMetrics? metrics,
  required String tally,
  required double cardOuterWidth,
  required int dayOfMonth,
}) {
  if (metrics == null) return true;
  final h = _measureLine(
    context: context,
    text: tally,
    // 与渲染那一行同一套样式（`_infoCard` 里的 `microText`）。
    style: AppTokens.microText,
    maxWidth: cardOuterWidth - _cardChromeH,
  ).height;
  return metrics.slackOn(dayOfMonth) >= h + AppTokens.spaceSm + 1;
}

/// 量卡片内**一段文字**排出来要多高、多宽（给上面那个判定用）。
///
/// 与卡片里其它文字走同一套 `DefaultTextStyle` 合并与 `TextScaler`，所以系统字号
/// 放大后量出来的跟着涨、判定跟着收紧。`maxLines: 2` 与渲染侧一致 —— 班次多、简称
/// 长的排班会折两行，折行的高度要照量。
Size _measureLine({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required double maxWidth,
  int maxLines = 2,
}) {
  final measure = _Measure(
    def: DefaultTextStyle.of(context),
    scaler: MediaQuery.textScalerOf(context),
  );
  final p = measure.text(text, style, maxLines: maxLines, maxWidth: maxWidth);
  return Size(p.width, p.height);
}

/// 单个色块的高度（`Wrap` 里一行的高度）。
double _chipLineH(_Measure m) =>
    m.text('班', AppTokens.microLabel).height +
    _chipPadV * 2 +
    _chipBorder * 2;

/// 日期行上「N 项待办」徽章的高度：图标与文字取高，加上下内边距与描边。
/// 与 `calendar_screen.dart` 的 `_todoHintBadge` 一一对应（改那边要改这里）。
double _todoHintH(_Measure m) =>
    math.max(m.text(L10n.todoCount(1), AppTokens.microStrong).height,
        AppTokens.iconSm) +
    AppTokens.padChipV * 2 +
    2;

/// 班次行尾巴上那颗「已调整」胶囊的高度。
///
/// 与 `calendar_screen.dart` 里那颗胶囊一一对应（改那边要改这里）：**同一套
/// 信息胶囊配方**（14% 淡染底 + 45% 描边 + `radiusL`），只是不带图标 —— 所以
/// 取高那一项是纯文字，没有 [_todoHintH] 里那个 `AppTokens.iconSm`。
///
/// 与 [_todoHintH] 一样**真量一个同款胶囊**（`padChipV × 2 + 描边 2`），不手算
/// 那个数：胶囊高是「文字行高 + 内边距 + 描边」的和，手算的值换个字体就飘了。
double _adjustedBadgeH(_Measure m) =>
    m.text(L10n.adjusted, AppTokens.microStrong).height +
    AppTokens.padChipV * 2 +
    2;

/// 某天色块折成几行 —— 按 `Wrap` 的贪心排布复算一遍。
int _chipRows(
    _Measure m, double contentW, ShiftSchedule schedule, DateTime date) {
  final labelW = m.text(L10n.otherCrews, AppTokens.microText).width;
  final avail = contentW - labelW - _otherCrewsLabelGap;
  if (avail <= 0) return 1;

  var rows = 1;
  var used = 0.0;
  for (var i = 0; i < schedule.teamCount; i++) {
    if (i == schedule.ourTeamIndex) continue;
    final t = schedule.teamShift(i, date);
    if (t == null) continue;
    final name = i < schedule.teamNames.length
        ? schedule.teamNames[i]
        : (L10n.isEn ? 'Team ${i + 1}' : '${i + 1}班');
    // 与 `_otherCrewChips` 同一个算式：色点 + 间隔 + 文字 + 左右内边距 + 描边。
    final w = _chipDot +
        _chipDotGap +
        m.text('$name ${t.shortLabel}', AppTokens.microLabel).width +
        _chipPadH * 2 +
        _chipBorder * 2;
    // `Wrap` 的贪心：放不下就换行，换行后这一块重新起算。
    if (used > 0 && used + _chipGapX + w > avail) {
      rows++;
      used = w;
    } else {
      used = used == 0 ? w : used + _chipGapX + w;
    }
  }
  return rows;
}

/// 按当前环境排一段文字，只为了拿尺寸。[TextPainter] 的样式要显式合并
/// `DefaultTextStyle`，否则拿不到环境里的字体族，量出来的行高会和渲染差一截。
class _Measure {
  _Measure({required this.def, required this.scaler});

  final DefaultTextStyle def;
  final TextScaler scaler;

  TextPainter text(
    String s,
    TextStyle style, {
    int? maxLines,
    double maxWidth = double.infinity,
  }) =>
      (TextPainter(
        text: TextSpan(text: s, style: def.style.merge(style)),
        maxLines: maxLines,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: maxWidth));

  TextPainter rich(
    List<InlineSpan> spans, {
    int? maxLines,
    double maxWidth = double.infinity,
  }) =>
      (TextPainter(
        text: TextSpan(style: def.style, children: spans),
        maxLines: maxLines,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: maxWidth));
}
