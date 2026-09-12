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
    final settings = ref.watch(appSettingsProvider);
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
