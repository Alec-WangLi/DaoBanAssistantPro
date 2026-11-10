// app/lib/core/haptics.dart
//
// 触觉反馈的设计系统层 —— 与 `core/motion.dart`（交互反馈的动画层）、
// `core/design_tokens.dart`（视觉令牌）并列。
//
// 词汇表按**语义**命名，不按强度：调用方写 `Haptics.select()` 表达的是「选中
// 变了」，不是「震得轻一点」。这样将来调某一档的强度时，不必回头改所有调用点。
//
// **挂动作，不挂按压。** 普通点击一律不震 —— 震动一旦变成背景噪音，信息量就归零，
// 用户会去系统里把触觉整个关掉，那时你想用震动区分的那件事也一起没了。所以
// `GlassPressable` 故意不挂：它包的是*每一次*按压，包括普通点击。触觉只出现在
// 「状态真的变了」或「这一步不可逆」的时刻。
//
// **为什么走原生通道而不是 Flutter 的 `HapticFeedback.*`**：Flutter 那几条最终落到
// `View.performHapticFeedback`，走的是 AOSP 的「常量 → 预定义效果」映射表。表里
// `selectionClick` 对应的 `CLOCK_TICK` 请求的是 `EFFECT_TEXTURE_TICK`，而小米这台
// 机器的 HAL 不支持它 —— 系统静默回退成 `EFFECT_TICK`（一次 70ms 的长震），手感
// 是「转子嗡嗡」，不是「咔哒」。2026-11-10 用 `dumpsys vibrator_manager` 的
// Recent vibrations 逐条对过：`performHapticFeedback(constant=4)` 记的是
// `original: Prebaked=TEXTURE_TICK` / `played: Prebaked=TICK`。
//
// 原生侧（`android/.../Haptics.kt`）改成直接点播设备**自己调好的**预定义效果：
// 与 MIUI 桌面按图标那一下（`Prebaked=CLICK`）同一道波形，短、脆、跟手。
//
// **除本文件外，任何地方不许直接调 `HapticFeedback.*`** —— 由
// `test/haptics_guard_test.dart` 扫源码盯着。本文件保留它们，是因为原生通道
// 不在时要回落（测试环境、非 Android、用户装着的旧安装包）。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 原生触觉通道（`MainActivity.configureFlutterEngine` 里注册）。
const MethodChannel _nativeChannel =
    MethodChannel('com.daoban.shiftassistantpro/haptics');

/// 用户是否关掉了触觉反馈（由「外观」设置反灌）。
///
/// 走模块级标志，而不是让每个调用点自己去查设置 —— 与 `liquidGlassEnabled`
/// （`core/glass/glass.dart`）同一条路：一处赋值全 app 生效，没人会漏查。
bool hapticsDisabled = false;

/// 触觉词汇表。**只有三档**，且只在下面三种语义下调用。
abstract final class Haptics {
  /// **选中变了**：开关翻转、胶囊段切换、选项胶囊选中、选择器提交、拖到新格。
  static void select() => _fire(_HapticLevel.select);

  /// **动作落实**：删除类确认、应用改班 / 恢复轮转、切换排班方案。
  ///
  /// 待办勾选**不在**此列：它的载体是 `GlassSwitch`，已经自震一次
  /// `select()`（§4.1），再补一记 `commit()` 就是每拨一下震两下 —— 两下比
  /// 一下信息量更少。`schedule_screen.dart` 那行 `onChanged` 里写着同样的
  /// 理由，别照旧把 `commit()` 加回去。
  static void commit() => _fire(_HapticLevel.commit);

  /// **进入一个模式**：长按进入日历的多选态。
  static void modeEnter() => _fire(_HapticLevel.modeEnter);

  /// 统一出口：尊重开关，且 fire-and-forget。
  ///
  /// **开关判定先于发送**：`_fire` 只做判定，真正的通道调用在 `_send` 里——
  /// 若先求值再判定（例如把 `invokeMethod` 的结果当参数传进来），关掉开关时
  /// 这一发已经上路，`_fire` 里的判定根本来不及拦。
  ///
  /// **不 await、异常不上抛**：震不震不该影响功能，更不该让一个触觉调用的失败
  /// 冒到业务逻辑里。平台侧拒绝（没有振动器、被系统策略拦掉）静默忽略即可。
  static void _fire(_HapticLevel level) {
    if (hapticsDisabled) return;
    unawaited(_send(level));
  }

  static Future<void> _send(_HapticLevel level) async {
    // 原生通道只存在于 Android。非 Android（桌面预览、单元测试、将来的
    // Windows 版）直接走 Flutter 自带的三档 —— **不要靠「调用失败再回落」**：
    // 测试环境里没人接的通道，`invokeMethod` 返回的 Future 永远不完成
    // （fake async 下连 `MissingPluginException` 都等不到），回落就成了死代码。
    if (defaultTargetPlatform != TargetPlatform.android) {
      return _flutterFallback(level);
    }
    try {
      await _nativeChannel.invokeMethod<void>('play', level.channelName);
    } on MissingPluginException {
      // 理论上到不了：Dart 与原生侧同一个 APK 一起发。真到了（例如别的平台
      // 打包时带了这段 Dart 代码）就退回 Flutter 自带的三档，别一声不响。
      await _flutterFallback(level);
    } catch (_) {
      // 原生侧报错（个别机型没有振动器、被系统策略拦掉）：静默降级。
    }
  }
}

/// 三档语义 → 原生通道里的字符串。
///
/// **字符串是契约**：`Haptics.kt` 的 `play()` 按这三个值挑波形，改名要两边一起改。
enum _HapticLevel {
  select('select'),
  commit('commit'),
  modeEnter('modeEnter');

  const _HapticLevel(this.channelName);

  final String channelName;
}

/// 原生通道缺席时的回落 —— 与改造前的三档一一对应。
///
/// 手感比原生那条差（见文件头），但至少还有声音；等哪天有了 Windows / iOS 版，
/// 这里就是它们现成的入口。
Future<void> _flutterFallback(_HapticLevel level) => switch (level) {
      _HapticLevel.select => HapticFeedback.selectionClick(),
      _HapticLevel.commit => HapticFeedback.lightImpact(),
      _HapticLevel.modeEnter => HapticFeedback.mediumImpact(),
    };
