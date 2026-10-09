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
import 'package:flutter/material.dart';
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

  // ── FrameBuilder：每帧**现读**的那一层 ──────────────────────────────────
  //
  // **别退回 `ValueListenableBuilder`**：它把值缓存在 State 里、只靠 listener 刷新
  // （Flutter 3.47 的 `value_listenable_builder.dart`：`late T value;` 只在
  // `_valueChanged` 里更新），于是**静默写进去的值它看不到** —— 而帧内（布局阶段）
  // 那一处只能静默写。这两条就是那个差别的现场。
  testWidgets('FrameBuilder：publish 之后重建（帧间那一类）', (tester) async {
    final FrameNotifier<int> n = FrameNotifier<int>(0);
    addTearDown(n.dispose);
    await tester.pumpWidget(MaterialApp(
        home: FrameBuilder<int>(
            listenable: n, builder: (_, int v, __) => Text('$v'))));
    expect(find.text('0'), findsOneWidget);

    n.publish(3);
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('FrameBuilder：publishSilently 之后再 build，读到的是新值',
      (tester) async {
    final FrameNotifier<int> n = FrameNotifier<int>(0);
    addTearDown(n.dispose);
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (_, StateSetter setSt) {
      rebuild = setSt;
      return FrameBuilder<int>(
          listenable: n, builder: (_, int v, __) => Text('$v'));
    })));
    expect(find.text('0'), findsOneWidget);

    n.publishSilently(9);
    expect(find.text('0'), findsOneWidget,
        reason: '静默写不触发重建 —— 此刻树上还是老样子');

    rebuild(() {});
    await tester.pump();
    expect(find.text('9'), findsOneWidget,
        reason: '重建时必须读到静默写进去的值（`ValueListenableBuilder` 在这里会'
            '读到缓存的旧值 —— 那正是不能退回它的理由）');
  });

  testWidgets('FrameBuilder：`child` 是同一个实例时不重建', (tester) async {
    final FrameNotifier<int> n = FrameNotifier<int>(0);
    addTearDown(n.dispose);
    var childBuilds = 0;
    await tester.pumpWidget(MaterialApp(
        home: FrameBuilder<int>(
            listenable: n,
            child: Builder(builder: (_) {
              childBuilds++;
              return const SizedBox();
            }),
            builder: (_, int v, Widget? child) => Column(
                children: <Widget>[Text('$v'), child!]))));

    n.publish(1);
    await tester.pump();
    n.publish(2);
    await tester.pump();

    expect(childBuilds, 1, reason: 'child 是同一个实例，不该跟着每帧重建');
  });
}
