import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/glass/glass.dart';
import '../core/l10n.dart';
import '../core/theme/app_colors.dart';

enum AppThemeMode { system, light, dark }

/// 外观设置（主题模式 + 主色调 + 语言），持久化到 SharedPreferences。
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.accentIndex = 0,
    this.language = 'zh',
    this.advancedMaterial = true,
  });

  final AppThemeMode themeMode;

  /// 指向 AppColors.accentPalette 的下标。
  final int accentIndex;

  /// 'zh' 或 'en'。
  final String language;

  /// 高级材质：true=真实背景模糊（默认），false=模拟低端机（去模糊）。
  final bool advancedMaterial;

  Color get accentColor => AppColors.accentPalette[accentIndex];

  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? accentIndex,
    String? language,
    bool? advancedMaterial,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accentIndex: accentIndex ?? this.accentIndex,
      language: language ?? this.language,
      advancedMaterial: advancedMaterial ?? this.advancedMaterial,
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
      final advancedMaterial = sp.getBool('advancedMaterial') ?? true;
      L10n.locale = language;
      advancedMaterialDisabled = !advancedMaterial;
      recomputeGlassBlur();
      state = AppSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => AppThemeMode.system,
        ),
        accentIndex: accentIndex ?? 0,
        language: language,
        advancedMaterial: advancedMaterial,
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

  Future<void> setAdvancedMaterial(bool value) async {
    advancedMaterialDisabled = !value;
    recomputeGlassBlur();
    state = state.copyWith(advancedMaterial: value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('advancedMaterial', value);
  }
}
