import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import 'app_colors.dart';

/// 状态栏图标该用深色还是浅色 —— **全 app 只有这一处判据**，而且**跟着主题档走**。
///
/// 起因（用户 2026-10-13 报的，荣耀 MagicOS 11）：浅色档下进「排班管理」，状态栏图标
/// 反色成白的，退回来也不恢复；深色档正常。同一版在 HyperOS 4 上看不出来。
///
/// 机制（在 `flutter test` 里量出来的，不是推的）：`MaterialApp` 每次 build 都会
/// **命令式**地发一次 `SystemChrome.setSystemUIOverlayStyle`（`material/app.dart`
/// 的 `_themeBuilder`），值按主题深浅取 —— 所以四个 tab 页一直是对的。而 `AppBar`
/// 会往树上挂一层 `AnnotatedRegion<SystemUiOverlayStyle>`，它的值由 **AppBar 的底色**
/// 推出来；我们三个带 AppBar 的页面底色是 `Colors.transparent`，亮度为 0，被 Flutter
/// 判成「深色背景」→ 推出**白图标**。`RenderView._updateSystemChrome` 每合成一帧都会
/// 拿「最上面那一层声明」去**覆盖**掉 `MaterialApp` 那发，于是进排班管理就变白；退回来
/// 时那层声明没了、而 `_updateSystemChrome` **一份都没找到就直接早退**（`MaterialApp`
/// 那发只在它 rebuild 时才有），白图标于是留在屏幕上 —— 那就是「返回后也不恢复」。
///
/// 只带状态栏那几位、**不碰导航栏**：与 Flutter 自己 `_systemOverlayStyleForBrightness`
/// 同一个理由 —— `SystemUiOverlayStyle.dark` 那类预置常量还带一条不透明的黑色导航栏，
/// 在 Android 14 及以下会把导航栏涂黑。
SystemUiOverlayStyle statusBarStyleFor(Brightness brightness) =>
    brightness == Brightness.dark ? kStatusBarOnDark : kStatusBarOnLight;

/// 浅色主题用：深图标。
const SystemUiOverlayStyle kStatusBarOnLight = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark, // Android：图标画深色
  statusBarBrightness: Brightness.light, // iOS：状态栏底色浅 ⇒ 图标深
  systemStatusBarContrastEnforced: false,
);

/// 深色主题用：浅（白）图标。
const SystemUiOverlayStyle kStatusBarOnDark = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemStatusBarContrastEnforced: false,
);

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
    // 图标三档的基准：没包 AppIcon 的图标也停在 iconLg(24)，而不是裸默认值。
    iconTheme: const IconThemeData(size: AppTokens.iconLg),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppTokens.inkLight,
      // **这一行不能省**：AppBar 底色是透明的，Flutter 会据此判成「深色背景」、
      // 自己推出一份**白图标**的样式挂在树上 —— 它比根部那层更靠上，会把它盖掉
      // （详见 `statusBarStyleFor` 的注释）。
      systemOverlayStyle: kStatusBarOnLight,
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
    // 图标三档的基准：没包 AppIcon 的图标也停在 iconLg(24)，而不是裸默认值。
    iconTheme: const IconThemeData(size: AppTokens.iconLg),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppTokens.inkDark,
      systemOverlayStyle: kStatusBarOnDark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusL)),
    ),
  );
}
