// app/lib/core/shift_palette.dart
//
// 班次可选颜色的**预设盘**（16 颗），以及它在「四处卡底」上的可读性门槛。
//
// ## 为什么这个盘要单独一个文件
//
// 它原来是 `schedule_editor_screen.dart` 里一个 **private** `static const _palette`
// —— 界面读得到、测试读不到。而这一版的主要护栏是一条**纯函数**用例（遍历 16 颗
// × 四处卡底逐颗算对比度），它必须能引用到这个盘。所以搬出来。
//
// ## 为什么卡底存 `int` 而不是 `Color`
//
// `design_tokens_test.dart` 不许 `lib/` 里出现 `Color(0x…)` 字面量（配色层
// `app_colors.dart` / `app_theme.dart` 除外）。这里只有**数据**，存 `int` 既躲开
// 那道守门、又让纯函数用例读得到同一份值。要 `Color` 的时候现造：`Color(int)`。
//
// ## 那四处卡底是怎么来的（规格 §4）
//
// 班次色在日历格子与桌面小组件上都不是直接铺上去的，是「**14% 淡染 + 45% 描边 +
// 中性字**」。淡染只有 14%，所以**真正让那颗胶囊读得出来的是那道 45% 的描边** ——
// 判据只压在描边上，淡染那一列只是记录。
//
// 描边要贴着的「底」有四处，**桌面小组件那两处是半透明的卡压在任意壁纸上的两个
// 极端**（`android/.../res/values/widget_colors.xml` 顶部那段注释把这件事讲透了：
// 它已经为此把不透明度提到 94~97%，但壁纸仍透进来 3~6%）：
//
//   · App 浅色      #FFFFFF  页面 #F5F6FA 上压 92% 的白卡
//   · App 深色      #16161E  AppTokens.surfaceDark
//   · 小组件 浅色    #F5F5F5  wg_card_to_light(96% 白) 压**纯黑壁纸** —— 它最暗的一档
//   · 小组件 深色    #24242B  wg_card_to_dark(94% #16161E) 压**纯白壁纸** —— 它最亮的一档
//
// **门槛 `kShiftColorBar` 是「现有那八颗在这四处上的下界」**，不是拍一个 WCAG 数字：
// 这套配方本身就刻意很轻，换成 3:1 那种门槛等于要重做整张日历与三张卡片的观感。
// 实际落在 `#FF9F0A` 压小组件浅色卡上。
//
// ⚠️ **那两个数都改过一轮，原因值得记**：规格里先写过 1.39472（只算了 App 两处卡底），
// 四处一起算之后落到 1.34906 —— 但 **1.34906 是拿浮点混合算出来的**，而
// [compoundOver] 每个通道都要**取整到 8 位**（设备真正画出来的就是 8 位）：
// `0.45×255 + 0.55×245 = 249.5`，取整成 250 之后亮度差一点点，最终是 **1.35018838**。
// **以实现算出来的那个数为准**（用例里钉着它），常量取它下面一点。
import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 16 颗预设。
///
/// **前八颗是原来那八个，一颗都没动、顺序也没动** —— `shift_templates.dart` 里的
/// 内置班次原型烘着其中 7 个（唯一没被用的是绿 `#34C759`），换掉哪一颗都会让那些
/// 班次指向一个「取色盘上再也选不到」的颜色。后八颗是这一版新加的（规格 §3）。
///
/// 顺序还有第二个用处：新建班次时按顺序循环取色（`_addClass`），所以**第一颗必须
/// 仍是 `#4C8DFF`**。
const List<int> kShiftPalette = <int>[
  // ── 原来那八个 ──
  0xFF4C8DFF, // 白班蓝
  0xFF7A5CFF, // 夜班紫
  0xFF9AA0B4, // 下夜灰蓝
  0xFF5A5F73, // 大休深灰
  0xFF34C759, // 绿
  0xFFFF9F0A, // 橙
  0xFFFF375F, // 玫红
  0xFF00C7BE, // 青
  // ── 新加那八个 ──
  0xFFE53935, // 红
  0xFFD81B60, // 品红
  0xFFB8860B, // 琥珀（「黄」那一档 —— 正黄在浅色卡上过不了线）
  0xFFE65100, // 深橙
  0xFF2E7D32, // 深绿
  0xFF00796B, // 深青
  0xFF795548, // 棕
  0xFFF06292, // 粉
];

/// 班次胶囊那套配方里的两个比例。**描边那个才是这一版的判据**。
const double kShiftChipTintAlpha = 0.14;
const double kShiftChipStrokeAlpha = 0.45;

/// 四处卡底（ARGB，全部不透明）。推导见文件头。
const int kShiftCardAppLight = 0xFFFFFFFF;
const int kShiftCardAppDark = 0xFF16161E;
const int kShiftCardWidgetLight = 0xFFF5F5F5;
const int kShiftCardWidgetDark = 0xFF24242B;

/// 四处卡底，顺序与文件头那张表一致。
const List<int> kShiftCardSurfaces = <int>[
  kShiftCardAppLight,
  kShiftCardAppDark,
  kShiftCardWidgetLight,
  kShiftCardWidgetDark,
];

/// 16 颗预设在这四处卡底上「描边对卡底」对比度的**下界**（= 现有八个的下界）。
///
/// 实测落在 `#FF9F0A` 压小组件浅色卡上：**1.35018838**。常量取在它**下面一点**，
/// 于是「定这条线的那颗自己也过线」—— 这是刻意的：门槛是「不比现在差」，
/// 现在的那颗当然不许被判成不及格。用例里同时钉住了「这个数」与「它就是现有
/// 八个的下界」两件事（后者才是真正防漂的那条）。
const double kShiftColorBar = 1.3501;

/// 把 [argb] 按 [alpha] 压在 [cardArgb] 上，返回合成后的不透明颜色。
///
/// **按位自己算，不要用 `Color.lerp`** —— 那个会把 alpha 也一起插值，得到的是
/// 「两个颜色的加权平均」而不是「前景压在背景上」，两端 alpha 不同时尤其不对。
int compoundOver(int argb, int cardArgb, double alpha) {
  int mix(int shift) {
    final f = (argb >> shift) & 0xFF;
    final b = (cardArgb >> shift) & 0xFF;
    return (alpha * f + (1 - alpha) * b).round().clamp(0, 255);
  }

  return 0xFF000000 | (mix(16) << 16) | (mix(8) << 8) | mix(0);
}

/// [argb] 那颗色压在 [cardArgb] 上之后，**描边**与卡底的对比度。
///
/// 对比度走现成的 [AppTokens.contrastRatio]，别手搓一份 WCAG。
double shiftChipStrokeContrast(int argb, int cardArgb) =>
    AppTokens.contrastRatio(
      Color(compoundOver(argb, cardArgb, kShiftChipStrokeAlpha)),
      Color(cardArgb),
    );
