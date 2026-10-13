import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          fontSize: s.fontSize,
        )));
    L10n.locale = settings.language;
    return MaterialApp(
      title: '倒班助手Pro',
      debugShowCheckedModeBanner: false,
      // 系统栏内边距先过一道体检再用：小米小窗会把 viewPadding.top 报成整个
      // 窗口的高度，SafeArea 会因此把整页吃掉（见 sanitizeSystemInsets）。
      // 放在这里是为了覆盖全应用 —— 每一页的 SafeArea 都读到同一份修好的值。
      //
      // 状态栏图标那一层**必须挂在根部、而且每一帧都在**：`MaterialApp` 自己是
      // **命令式**发那一发的（只在它 rebuild 时发），而某一页挂上来的
      // `AnnotatedRegion`（AppBar、响铃页）会在它离开树之后**没有东西接手** ——
      // `RenderView._updateSystemChrome` 一份声明都找不到就直接早退，于是那一页的
      // 样式留在屏幕上（荣耀那条「进排班管理变白、退回来也不恢复」就是这么来的）。
      // 根部挂一层之后，任何一页的声明离开树，下一帧立刻被这一层顶回来。
      // `SystemChrome.setSystemUIOverlayStyle` 按值去重，同值不会重复跨端。
      // 字号**整个换掉平台报上来的那一份**（设计 §3）：Android 14 起系统字号最高
      // 200%，而且是非线性的（≤12sp 吃满倍率、≥30sp 不放大）—— 而本 App 的界面
      // 几乎全建在 12–15sp 上，正好是吃满的那一档。系统调到 200% 时版式会被撑垮
      // （实拍过：卡片吃掉半个屏、网格只剩三行）。
      //
      // 所以字号只由「我的 → 外观 → 字体大小」这四档决定，天花板是我们自己选的：
      // 每一档都设计过、量过。**代价是有意的** —— 把系统调到 150%~200% 的人拿不到
      // 那个大小。这条取舍由 `app_font_size_test.dart` 的「系统调到 2.0 也不变」钉着。
      builder: (context, child) => MediaQuery(
        data: sanitizeSystemInsets(MediaQuery.of(context))
            .copyWith(textScaler: TextScaler.linear(settings.fontSize.scale)),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: statusBarStyleFor(Theme.of(context).brightness),
          child: child!,
        ),
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
