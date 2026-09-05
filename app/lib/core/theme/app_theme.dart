import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'app_colors.dart';

/// 全局页面切换动画：右滑淡入（返回时反向）。
class _FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

const _pageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _FadeSlidePageTransitionsBuilder(),
    TargetPlatform.iOS: _FadeSlidePageTransitionsBuilder(),
    TargetPlatform.windows: _FadeSlidePageTransitionsBuilder(),
    TargetPlatform.linux: _FadeSlidePageTransitionsBuilder(),
    TargetPlatform.macOS: _FadeSlidePageTransitionsBuilder(),
  },
);

ThemeData buildLightTheme({Color seed = AppColors.primary}) {
  // 中性 seed：让 M3 surface 按灰派生，不随主色相染色。
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9AA0B4),
    brightness: Brightness.light,
  ).copyWith(
    primary: seed,
    onPrimary: Colors.white,
    secondary: seed, // 次强调也跟主色，消除蓝紫固定色
    surface: AppTokens.surfaceLight,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTokens.bgLight,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: _pageTransitions,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppTokens.inkLight,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusL)),
    ),
  );
}

ThemeData buildDarkTheme({Color seed = AppColors.primary}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9AA0B4),
    brightness: Brightness.dark,
  ).copyWith(
    primary: seed,
    onPrimary: Colors.white,
    secondary: seed,
    surface: AppTokens.surfaceDark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTokens.bgDark,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: _pageTransitions,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppTokens.inkDark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusL)),
    ),
  );
}
