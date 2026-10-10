import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n.dart';
import 'core/layout.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_shell.dart';
import 'state/app_settings.dart';

class ShiftAssistantApp extends ConsumerWidget {
  const ShiftAssistantApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **只订阅真正参与渲染的三项**（主题档 / 主色 / 语言）。
    //
    // 全量 `watch` 的话，拨一下触觉或液态玻璃开关也会把**整个 App** 重建一遍 ——
    // 那两项不参与主题、不参与语言，什么都不影响渲染。
    // 用具名记录：`==` 是逐字段的，且 `settings.themeMode` 这类读法一字不用改。
    // `settings_select_test.dart` 钉着这条（反向验证过：换回全量 watch 立刻红）。
    final settings = ref.watch(appSettingsProvider.select((s) => (
          themeMode: s.themeMode,
          accentColor: s.accentColor,
          language: s.language,
        )));
    L10n.locale = settings.language;
    return MaterialApp(
      title: '倒班助手Pro',
      debugShowCheckedModeBanner: false,
      // 系统栏内边距先过一道体检再用：小米小窗会把 viewPadding.top 报成整个
      // 窗口的高度，SafeArea 会因此把整页吃掉（见 sanitizeSystemInsets）。
      // 放在这里是为了覆盖全应用 —— 每一页的 SafeArea 都读到同一份修好的值。
      builder: (context, child) => MediaQuery(
        data: sanitizeSystemInsets(MediaQuery.of(context)),
        child: child!,
      ),
      locale: Locale(settings.language),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildLightTheme(seed: settings.accentColor),
      darkTheme: buildDarkTheme(seed: settings.accentColor),
      themeMode: switch (settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      home: const HomeShell(),
    );
  }
}
