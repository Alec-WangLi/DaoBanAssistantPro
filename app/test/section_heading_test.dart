// app/test/section_heading_test.dart
//
// 页面级小节标题全 app 只有一个实现（v0.12.0）。此前有四份私有函数、三种字号：
// 排班管理与使用帮助走 sectionTitle（18/w700）、闹钟走 titleStrong（16/w700）、
// 我的页走 labelSecondary+灰（13/w400）。同一个角色三副面孔，用户一眼就看出
// 「不像一套东西」。标准由用户拍板：titleStrong。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/section_heading.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';

void main() {
  testWidgets('字号与字重就是 titleStrong 那一档', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SectionHeading('外观'))));
    final text = tester.widget<Text>(find.text('外观'));
    expect(text.style?.fontSize, AppTokens.titleStrong.fontSize);
    expect(text.style?.fontWeight, AppTokens.titleStrong.fontWeight);
  });

  testWidgets('左右各留 spaceXs、下留 spaceSm', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SectionHeading('外观'))));
    final padding = tester.widget<Padding>(
        find.ancestor(of: find.text('外观'), matching: find.byType(Padding)).first);
    expect(padding.padding,
        const EdgeInsets.fromLTRB(
            AppTokens.spaceXs, 0, AppTokens.spaceXs, AppTokens.spaceSm));
  });

  // Review Focus 第 3 条：各处字号被统一到 16/w700 之后，「我的」页那一列标题
  // 比从前（13/w400 灰）高一档 —— 要在**最窄 + 最大字号**这一档仍然不炸、第一个
  // 小节标题仍在页面上。
  testWidgets('「我的」页在 320×640 + 特大字号（1.2）下不炸、第一处小节标题仍在',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    L10n.locale = 'zh';
    addTearDown(() => L10n.locale = 'zh');

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await AppRepository(db).ensureSeeded();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        // **用 `MediaQuery.of(context).copyWith(textScaler:)`**，别直接
        // `MediaQueryData(textScaler:)` —— 后者会丢掉 size，整棵树在 0×0 里排版。
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.2)),
            child: const ProfileScreen(),
          ),
        ),
      ),
    ));
    // **不能 `pumpAndSettle`**：权限卡在 `initState` 会去调一串在测试里永不
    // resolve 的原生方法（同 `snooze_duration_test` / `haptics_setting_test`）。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(tester.takeException(), isNull);
    expect(find.text(L10n.sectionAppearance), findsOneWidget);
  });
}
