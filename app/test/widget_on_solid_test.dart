// app/test/widget_on_solid_test.dart
//
// 实心块上的字色：**必须按对比度二选一**，不能拿亮度卡一个阈值。
//
// 为什么单独立一条：这是本轮唯一「字压在用户自选的颜色上」的地方（今天那块块用
// 主色、格内实心胶囊用班次色），而纯白 / 纯黑这两个候选之所以够用，**全靠「取两者
// 里对比更高的那个」这条判据**。第一版把它写成了「相对亮度 > 0.55 取黑、否则取白」，
// 于是 teal 那档（亮度 0.549，刚好压在阈值下面）选了**白字**：实测 2.63:1 ——
// 而 `AGENTS.md` 里记着「用户自己用的就是 teal」。
//
// Kotlin 那侧没有可跑的测试目标，所以这里分两半：
//   1. **候选够不够**（纯白 / 纯黑）—— 用 Dart 把每一种可达的块底色算一遍（真算）；
//   2. **判据对不对**（按对比度比、不是按亮度卡）—— 扫 Kotlin 源码的形状。
// 第 2 条才是能抓住第一版那个错的那条：第一版的函数体里根本没有对比度。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/shift_palette.dart';
import 'package:shiftassistantpro/core/theme/app_colors.dart';

String _read(String rel) {
  final f = File(rel);
  expect(f.existsSync(), true, reason: '$rel 不存在');
  return f.readAsStringSync();
}

/// 可能当「实心块底色」的颜色：五种主色调 + 十六颗班次盘色。
List<Color> _reachableBlockColors() => [
      ...AppColors.accentPalette,
      for (final v in kShiftPalette) Color(v),
    ];

/// 与 App 的 `AppTokens.onSolid` 逐字同一条判据。
Color _onSolid(Color background) =>
    AppTokens.contrastRatio(Colors.white, background) >=
            AppTokens.contrastRatio(Colors.black, background)
        ? Colors.white
        : Colors.black;

void main() {
  test('每一种可达的块底色，黑/白里更高的那一个都过 AA', () {
    final worst = _reachableBlockColors()
        .map((c) => (c,
            AppTokens.contrastRatio(_onSolid(c), c)))
        .reduce((a, b) => a.$2 <= b.$2 ? a : b);
    // 自证：颜色表要是被清空了，这条护栏就是句空话。
    expect(_reachableBlockColors().length, greaterThanOrEqualTo(20),
        reason: '只扫到 ${_reachableBlockColors().length} 种颜色 —— 表被清空或改了名字');
    expect(worst.$2, greaterThanOrEqualTo(4.5),
        reason: '最差的一档是 #${worst.$1.toARGB32().toRadixString(16)}：'
            '${worst.$2.toStringAsFixed(2)}:1 —— 低于 AA 4.5');
  });

  test('teal 那档必须判成**黑字**（第一版就是在这颗上判错的）', () {
    const teal = Color(0xFF00B3A6);
    final white = AppTokens.contrastRatio(Colors.white, teal);
    final black = AppTokens.contrastRatio(Colors.black, teal);
    expect(white, lessThan(4.5),
        reason: '白字压 teal 只有 ${white.toStringAsFixed(2)}:1 —— 这正是第一版的错，'
            '把它钉在这儿：哪天有人把判据退回「亮度卡阈值」，这条会跟着变色');
    expect(black, greaterThanOrEqualTo(4.5));
    expect(_onSolid(teal), Colors.black, reason: 'teal 上该用黑字');
  });

  test('Kotlin 的 onSolidInk 按**对比度**二选一，不是拿亮度卡阈值', () {
    final kt = _read(
        'android/app/src/main/kotlin/com/daoban/shiftassistantpro/WidgetRenderer.kt');
    final i = kt.indexOf('private fun onSolidInk');
    expect(i, greaterThanOrEqualTo(0), reason: 'onSolidInk 不见了');
    final body = kt.substring(i, kt.indexOf('\n    }', i));
    // 判据是「两次对比度比较之后取更大」——第一版那个函数体里一次对比度都没有。
    final compares = RegExp(r'contrastRatio\(').allMatches(body).length;
    expect(compares, greaterThanOrEqualTo(2),
        reason: 'onSolidInk 的函数体里只有 $compares 次 contrastRatio —— '
            '它必须是「比较两个对比度、取更大的那个」（与 App 的 AppTokens.onSolid 同一件事），'
            '不是拿相对亮度卡一个阈值（第一版写 0.55，teal 那档因此选了白字）');
    expect(body.contains('0.2126'), false,
        reason: 'onSolidInk 里出现了亮度算式 —— 亮度只该出现在 contrastRatio 的 helper 里');
    // 两个候选必须是**纯白 / 纯黑**：那条「恒 ≥ 4.58」的保证就是按这两个极值推的，
    // 换成近黑（例如 #111818）之后最坏一档会掉到约 4.1。
    expect(kt.contains('private fun contrastRatio('), true,
        reason: 'contrastRatio helper 不见了');
  });

  test('两个候选就是纯白与纯黑', () {
    final src = _read('android/app/src/main/res/values/widget_colors.xml');
    expect(src.contains('<color name="wg_on_solid_light">#FFFFFFFF</color>'), true,
        reason: '块上字的浅色候选必须正好是纯白');
    expect(src.contains('<color name="wg_on_solid_dark">#FF000000</color>'), true,
        reason: '块上字的深色候选必须正好是纯黑 —— 与 App 的 AppTokens.onSolid 一致；'
            '换成近黑之后「恒 ≥ 4.58」那条保证就不成立了');
  });
}
