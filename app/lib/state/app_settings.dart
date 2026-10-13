import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/glass/glass.dart';
import '../core/haptics.dart';
import '../core/l10n.dart';
import '../core/theme/app_colors.dart';

enum AppThemeMode { system, light, dark }

/// 字号档位 —— **只由 App 自己决定，系统那一维被挡在门外**（设计 §3）。
///
/// 为什么不让系统说了算：Android 14 起系统字号最高 **200%**，而且是**非线性**的
/// —— ≤12sp 吃满倍率、≥30sp 根本不放大，而本 App 的界面几乎全建在 12–15sp 上，
/// 正好是吃满的那一档。用户 2026-10-13 在真机上验过：主流第三方 App（微信、酷安）
/// 都不跟系统字号，各自给一个自己的「字体大小」。
///
/// 于是天花板回到我们手里：**每一档都是设计过、量过的**，不存在「系统调到 2.0
/// 之后卡片吃掉半个屏、网格只剩三行」那种形态。
///
/// **代价（有意付出）**：把系统调到 150%~200% 的人拿不到那个大小，最多到「特大」。
enum AppFontSize {
  small,
  standard,
  large,
  extraLarge;

  /// 相对标准档的倍率。
  ///
  /// ⚠️ **「特大」最终取哪一档由出图与断言共同决定**（设计 §5）：收不住就降到
  /// 1.25 或 1.2 —— 宁可档位小，也不许在任何一屏留一处省略号。
  double get scale => switch (this) {
        AppFontSize.small => 0.9,
        AppFontSize.standard => 1.0,
        AppFontSize.large => 1.15,
        AppFontSize.extraLarge => 1.3,
      };
}

/// 外观设置（主题模式 + 主色调 + 语言），持久化到 SharedPreferences。
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.accentIndex = 0,
    this.language = 'zh',
    this.liquidGlass = false,
    this.hapticsEnabled = true,
    this.fontSize = AppFontSize.standard,
  });

  final AppThemeMode themeMode;

  /// 指向 AppColors.accentPalette 的下标。
  final int accentIndex;

  /// 'zh' 或 'en'。
  final String language;

  /// 液态玻璃：true=边缘光 + 跟随滑块的透镜（默认关，且低内存机器一律不给）。
  ///
  /// **默认为关是有意的**：这个档会增加合成开销，不能让从没选过它的人静默吃上。
  /// 旧名「高级材质」（true=真实背景模糊）的键留在 prefs 里不管 ——
  /// 换新键天然就是「一次性重置」，不必另加标记（加标记才容易踩到「每次启动都重置」）。
  final bool liquidGlass;

  /// 触觉反馈：true=状态改变与不可逆动作时轻微震动（默认），false=完全不震。
  final bool hapticsEnabled;

  /// 字号档位（见 [AppFontSize]）。**系统字号不参与换算。**
  final AppFontSize fontSize;

  Color get accentColor => AppColors.accentPalette[accentIndex];

  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? accentIndex,
    String? language,
    bool? liquidGlass,
    bool? hapticsEnabled,
    AppFontSize? fontSize,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accentIndex: accentIndex ?? this.accentIndex,
      language: language ?? this.language,
      liquidGlass: liquidGlass ?? this.liquidGlass,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final modeName = sp.getString('themeMode');
      final accentIndex = sp.getInt('accentIndex');
      final language = sp.getString('language') ?? 'zh';
      final liquidGlass = sp.getBool('liquidGlass') ?? false;
      final hapticsEnabled = sp.getBool('hapticsEnabled') ?? true;
      final fontSizeName = sp.getString('fontSize');
      L10n.locale = language;
      liquidGlassEnabled.value = liquidGlass;
      hapticsDisabled = !hapticsEnabled;
      recomputeGlassTiers();
      state = AppSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => AppThemeMode.system,
        ),
        accentIndex: accentIndex ?? 0,
        language: language,
        liquidGlass: liquidGlass,
        hapticsEnabled: hapticsEnabled,
        fontSize: AppFontSize.values.firstWhere(
          (f) => f.name == fontSizeName,
          orElse: () => AppFontSize.standard,
        ),
      );
    } catch (_) {
      // 忽略读取失败，使用默认值
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('themeMode', mode.name);
  }

  Future<void> setAccentIndex(int index) async {
    if (index < 0 || index >= AppColors.accentPalette.length) return;
    state = state.copyWith(accentIndex: index);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('accentIndex', index);
  }

  Future<void> setLanguage(String language) async {
    L10n.locale = language;
    state = state.copyWith(language: language);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('language', language);
  }

  Future<void> setLiquidGlass(bool value) async {
    liquidGlassEnabled.value = value;
    recomputeGlassTiers();
    state = state.copyWith(liquidGlass: value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('liquidGlass', value);
  }

  Future<void> setHapticsEnabled(bool value) async {
    // **先落标志，再震动。** 打开时：`GlassSwitch.onTap` 发的那一记 `select()`
    // 跑在这一行**之前**，此刻 `hapticsDisabled` 还是 true，于是它被自己要打开的
    // 那个标志吞掉了 —— 用户测试这个新开关的那一刻反而什么也摸不到。所以标志先
    // 翻成 false，再补发一记确认震。
    //
    // 关闭时**不补**：开关自己那记 `select()` 在标志翻成 true 之前就落了地，
    // 用户感到的正是「最后一下」—— 那是对的，不必也不该再响一次。
    hapticsDisabled = !value;
    if (value) Haptics.select();
    state = state.copyWith(hapticsEnabled: value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('hapticsEnabled', value);
  }

  Future<void> setFontSize(AppFontSize size) async {
    state = state.copyWith(fontSize: size);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('fontSize', size.name);
  }

  /// 把外观这一组**在内存里**拨回默认（跟随系统 / 首个主色调 / 中文 / 液态玻璃关 /
  /// 触觉开 / 标准字号），并同步那几个模块级标志。
  ///
  /// 仅供「清空重置 = 回到第一次安装」用（`profile_screen.dart` 的 `_confirmReset`）。
  /// **它不写 SharedPreferences**：那条链路紧接着就 `prefs.clear()` 把这一组连同
  /// 铃声、首启标记、小组件快照一起抹掉 —— 在两边各写一份键名，迟早会漏掉一个。
  void resetToDefaults() {
    L10n.locale = 'zh';
    liquidGlassEnabled.value = false;
    hapticsDisabled = false;
    recomputeGlassTiers();
    state = const AppSettings();
  }
}
