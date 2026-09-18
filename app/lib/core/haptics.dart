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
// **除本文件外，任何地方不许直接调 `HapticFeedback.*`** —— 由
// `test/haptics_guard_test.dart` 扫源码盯着。
import 'dart:async';

import 'package:flutter/services.dart';

/// 用户是否关掉了触觉反馈（由「外观」设置反灌）。
///
/// 走模块级标志，而不是让每个调用点自己去查设置 —— 与 `advancedMaterialDisabled`
/// （`core/glass/glass.dart`）同一条路：一处赋值全 app 生效，没人会漏查。
bool hapticsDisabled = false;

/// 触觉词汇表。**只有三档**，且只在下面三种语义下调用。
abstract final class Haptics {
  /// **选中变了**：开关翻转、胶囊段切换、选项胶囊选中、选择器提交、拖到新格。
  static void select() => _fire(HapticFeedback.selectionClick);

  /// **动作落实**：删除类确认、应用改班 / 恢复轮转、切换排班方案。
  ///
  /// 待办勾选**不在**此列：它的载体是 `GlassSwitch`，已经自震一次
  /// `select()`（§4.1），再补一记 `commit()` 就是每拨一下震两下 —— 两下比
  /// 一下信息量更少。`schedule_screen.dart` 那行 `onChanged` 里写着同样的
  /// 理由，别照旧把 `commit()` 加回去。
  static void commit() => _fire(HapticFeedback.lightImpact);

  /// **进入一个模式**：长按进入日历的多选态。
  static void modeEnter() => _fire(HapticFeedback.mediumImpact);

  /// 统一出口：尊重开关，且 fire-and-forget。
  ///
  /// **收的是「怎么发」，不是「发什么」**（`Future<void> Function()` 而非
  /// `Future<void>`）：`HapticFeedback.selectionClick()` 一被求值就把消息发到
  /// 平台通道了，若把结果当参数传进来，关掉开关时这发消息已经上路 —— 放在
  /// `_fire` 里的开关判定根本来不及拦。传一个惰性调用，判定先跑、真发在后，
  /// 开关才真的「一处生效」。
  ///
  /// **不 await、异常不上抛**：震不震不该影响功能，更不该让一个触觉调用的失败
  /// 冒到业务逻辑里。平台侧拒绝（没有振动器、被系统策略拦掉）静默忽略即可。
  static void _fire(Future<void> Function() call) {
    if (hapticsDisabled) return;
    unawaited(call().catchError((Object _) {}));
  }
}
