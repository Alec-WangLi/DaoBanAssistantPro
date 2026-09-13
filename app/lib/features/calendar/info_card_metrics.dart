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

/// 底栏信息卡的外框高度（竖屏 / 短屏非紧凑形态）。
///
/// [cardOuterWidth] 是卡片**外框**宽度（还没扣内边距与描边）。[month] 只用到
/// 年月，用来枚举这个月有哪些天。
double measureBottomInfoCardHeight({
  required BuildContext context,
  required double cardOuterWidth,
  required ShiftSchedule? schedule,
  required DateTime month,
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
  final dateH = measure.text(
    L10n.monthDayWeekday(DateTime(month.year, month.month, 1)),
    AppTokens.sectionTitle,
    maxWidth: contentW,
  ).height;

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
  final shiftRowH = [shiftLineH, noShiftH, blankH, _shiftDot]
      .reduce((a, b) => a > b ? a : b);

  final showChips = schedule != null && schedule.teamCount > 1;

  // ── 逐日取大：节假日徽章、农历行数、色块折行数 ──
  var badgeH = 0.0;
  var lunarH = 0.0;
  var chipsH = 0.0;

  // 「其他班组」那一行是 `Row[标签, 色块]`，高度取两者的大者。标签不折行，
  // 它那份是定值，先算好。
  final otherCrewsLabelH = showChips
      ? measure
              .text(L10n.otherCrews, AppTokens.microText)
              .height +
          _otherCrewsLabelTop
      : 0.0;
  final chipLineH = showChips ? _chipLineH(measure) : 0.0;

  final days = DateTime(month.year, month.month + 1, 0).day;
  for (var d = 1; d <= days; d++) {
    final date = DateTime(month.year, month.month, d);
    final lunar = lunarOf(date);

    if (lunar.isLegalHoliday) {
      // 徽章：图标 16 + 小字「法定节假日」12 + 大字节日名 14，外加 3×2 内边距
      // 与 1×2 描边。两个字号不同的 span 并排，行高由大的那档决定。
      final textH = measure.rich(
        [
          TextSpan(text: L10n.legalHoliday, style: AppTokens.microLabel),
          TextSpan(text: lunar.legalHolidayName, style: AppTokens.labelStrong),
        ],
        maxLines: 1,
        maxWidth: contentW,
      ).height;
      final h = textH + _chipPadV * 2 + _chipBorder * 2;
      if (h > badgeH) badgeH = h;
    }

    final lh = measure.text(
      lunar.fullDescription,
      AppTokens.rowSecondary,
      maxLines: 2,
      maxWidth: contentW,
    ).height;
    if (lh > lunarH) lunarH = lh;

    if (showChips) {
      final rows = _chipRows(measure, contentW, schedule, date);
      final h = math.max(
          otherCrewsLabelH, rows * chipLineH + (rows - 1) * _chipGapY);
      if (h > chipsH) chipsH = h;
    }
  }

  var content = dateH + _gapAfterDate + lunarH + _gapBetweenSections + shiftRowH;
  if (badgeH > 0) content += badgeH + _gapAfterBadge;
  if (showChips) content += _gapBetweenSections + chipsH;

  return content + _cardChromeV;
}

/// 单个色块的高度（`Wrap` 里一行的高度）。
double _chipLineH(_Measure m) =>
    m.text('班', AppTokens.microLabel).height +
    _chipPadV * 2 +
    _chipBorder * 2;

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
