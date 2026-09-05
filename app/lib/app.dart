import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n.dart';
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
