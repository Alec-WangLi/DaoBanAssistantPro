// app/tool/visual/contrast_audit_test.dart
//
// 对比度审计：用 Flutter 自带的 textContrastGuideline 扫每一屏上的**所有**文字，
// 按 WCAG 算出「这行字压着的实际背景」与字色的对比度，逐条列出来。
//
//   toolchain/flutter/bin/flutter test tool/visual/contrast_audit_test.dart
//
// 为什么要有它：看图只能发现「明显看不见」的低对比。真实翻车的是另一种——
// 深色模式下「同一个色相只差透明度」的底和字，肉眼在缩略图上很容易放过，
// 但算出来只有 2.7:1。这是量出来的，不是看出来的。
//
// 它**不判失败**：存量问题要一条条处理，一上来就红只会让人把这条测试关掉。
// 报告打进日志，修一条少一条。
//
// 读报告要注意：`textContrastGuideline` 是**启发式**的。它取文字节点区域内的
// 颜色直方图，按 HSL 明度分成「亮的众数」和「暗的众数」再算对比度。对 12–13px
// 的小字，字的实心像素常常不是第二多的颜色——排在前面的可能是抗锯齿边缘，或者
// 整片底色/描边，于是它会**高报**（曾把 4.9:1 的班组 chip 报成 1.49:1，因为
// 它取到的是 chip 的淡底和描边，不是字）。
//
// 所以：把它当筛子用，命中一条就去渲染图里采样那个像素，确认了再动手。
// 采样脚本见 `tool/visual/sample_contrast.py`（取区域直方图里最暗的几个实心色）。

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/data/app_repository.dart';

import 'visual_harness.dart';
import 'visual_screens.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    await ensureVisualFonts();
  });

  setUp(setUpVisualPrefs);

  for (final screen in visualScreens) {
    // 对比度与画布尺寸无关：只跑竖屏那三张，横屏/小窗两张跳过，
    // 免得白烧一倍的时间。
    for (final variant
        in visualVariants.where((v) => v.size == kVisualSize)) {
      testWidgets('${screen.title} · ${variant.label}', (tester) async {
        final db = await makeVisualDatabase();
        addTearDown(db.close);

        await pumpScreen(
          tester,
          home: await screen.build(db),
          overrides: <Override>[databaseProvider.overrideWithValue(db)],
          brightness: variant.brightness,
          language: variant.language,
          extraPrefs: screen.needsOnboardingPrefs ? onboardingPrefs : const {},
        );

        // textContrastGuideline 用的是 WCAG AA 阈值（普通文字 4.5:1、大字 3:1）。
        // 它会把大片刻意的「浅灰次要文字」也算成问题——这正是审计而不是断言
        // 的原因：报告拿来挑，判断留给人。
        final result = await textContrastGuideline.evaluate(tester);
        stdout.writeln(
            '\n===== ${screen.slug}_${variant.suffix} ===== ${result.passed ? "达标" : "有低对比"}');
        if (!result.passed) stdout.writeln(result.reason);

        await teardownVisual(tester);
      });
    }
  }
}
