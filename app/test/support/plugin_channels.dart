// app/test/support/plugin_channels.dart
//
// 把插件通道挂上空实现。
//
// 测试环境没有原生侧，没人接的 `MethodChannel` 会抛 `MissingPluginException`；
// 而权限请求这类调用多半是在 `initState` 里 fire-and-forget 出去的（主壳就是这样：
// `home_shell.dart` 首帧后调 `AlarmService.requestPermissions()`），异常没有调用者
// 去接，就成了未处理异步错误 —— `flutter_test` 直接判整个用例失败，报的还是
// 「Multiple exceptions were detected」这种与真因隔了三层的消息。
//
// 统一返回 null 等价于「权限一个都没给」，界面落在一个确定的状态上。
//
// 原本长在 `tool/visual/visual_harness.dart` 里。`test/` 下凡是要 pump 主壳的用例
// 都需要它（主壳首帧后必请求权限），所以抽到这里共用 —— 与 `source_scan.dart`
// 同一条理由：抄一份的话，两份迟早走偏，而走偏的表现是「某个用例突然开始报一个
// 与它无关的错」。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 需要挂桩的通道。以后主壳首帧后再调什么原生侧，往这里加。
const List<String> kStubbedChannels = <String>[
  'dexterous.com/flutter/local_notifications',
  'com.daoban.shiftassistantpro/settings',
];

/// 装一次即可，登记在 `TestDefaultBinaryMessengerBinding` 上，整个用例有效。
///
/// **必须在 `testWidgets` 体里调**（要 binding 已初始化）—— 放 `setUpAll` 里
/// 有些顺序下 binding 还没起来。
void stubPluginChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in kStubbedChannels) {
    messenger.setMockMethodCallHandler(
        MethodChannel(name), (call) async => null);
  }
}
