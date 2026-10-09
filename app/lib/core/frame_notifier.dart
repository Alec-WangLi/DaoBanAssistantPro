import 'package:flutter/foundation.dart';

/// 一个**可以静默写**的值通知源。
///
/// 为什么需要它：日历那两层每帧都在变的值，写入点分两类 ——
///
/// · **帧间**（`Ticker` 回调、指针回调、带子的每帧回调）：写完之后通知，
///   `ValueListenableBuilder` 的 `setState` 在那些地方是安全的；
/// · **帧内**（`LayoutBuilder` 的回调跑在**布局阶段**）：在那里通知会当场抛
///   「setState() called during build」。而那里**不需要**通知 ——
///   `ValueListenableBuilder` 自己在 build 时读 `.value`，而它排在写入点之后建。
///
/// `ValueNotifier` 的 `value` setter 只有「记值 + 通知」一条路（`_value` 是私有的，
/// 子类碰不到），所以这里自己实现一个。
///
/// **它不读档位**（`liquidGlassActive`）—— 判据归调用点，与本仓既有纪律一致
/// （`liquid_scope_guard_test.dart` 扫源码守着）。
class FrameNotifier<T> extends ChangeNotifier implements ValueListenable<T> {
  FrameNotifier(this._value);

  T _value;

  @override
  T get value => _value;

  /// 帧间写：值变了就通知。
  void publish(T next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  /// 帧内写：**只记值**，一声不响。
  void publishSilently(T next) {
    if (next == _value) return;
    _value = next;
  }
}
