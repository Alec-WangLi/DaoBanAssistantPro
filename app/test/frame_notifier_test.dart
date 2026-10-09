// app/test/frame_notifier_test.dart
//
// `FrameNotifier`：一个**可以静默写**的值通知源。
//
// 它存在的唯一理由是日历那两层每帧都在变的值，而它们的写入点分两类：
//   · **帧间**（Ticker 回调、指针回调、带子的每帧回调）：写完之后通知，
//     `ValueListenableBuilder` 的 `setState` 在那里是安全的；
//   · **帧内**（`LayoutBuilder` 的回调跑在**布局阶段**）：在那里通知会当场抛
//     「setState() called during build」。而那里**不需要**通知 ——
//     `ValueListenableBuilder` 自己在 build 时读 `.value`，它排在写入点之后建。
//
// `ValueNotifier` 的 `value` setter 只有「记值 + 通知」一条路（`_value` 是私有的，
// 子类碰不到），所以才要有这个件。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/frame_notifier.dart';

void main() {
  test('publish：值变了才通知', () {
    final FrameNotifier<int> n = FrameNotifier<int>(0);
    var hits = 0;
    n.addListener(() => hits++);

    n.publish(1);
    n.publish(1); // 同一个值 —— 不许再通知（每帧都写同一个位置是常态）
    n.publish(2);

    expect(hits, 2);
    expect(n.value, 2);
  });

  test('publishSilently：值变了、但一声不响', () {
    final FrameNotifier<int> n = FrameNotifier<int>(0);
    var hits = 0;
    n.addListener(() => hits++);

    n.publishSilently(7);

    expect(n.value, 7, reason: '值要记下来 —— 帧内写入靠的就是「读的人自己读」');
    expect(hits, 0, reason: '帧内写不许通知（那会变成 setState during build）');
  });

  test('静默写之后再 publish 同一个值也不通知（值没变）', () {
    final FrameNotifier<int> n = FrameNotifier<int>(0);
    var hits = 0;
    n.addListener(() => hits++);

    n.publishSilently(3);
    n.publish(3);

    expect(hits, 0);
  });

  test('它是个 ValueListenable：ValueListenableBuilder 认得', () {
    final FrameNotifier<int> n = FrameNotifier<int>(5);
    final ValueListenable<int> asListenable = n;
    expect(asListenable.value, 5);
  });
}
