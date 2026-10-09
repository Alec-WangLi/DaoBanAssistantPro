// app/test/widget_push_dedup_test.dart
//
// 小组件快照的去重：**同一份内容不许推第二次**。
//
// 为什么要它：`push` 在首帧、**每次回前台**、排班变、外观变（含换主色）、勾一条待办
// 时都会跑，而它同步构建 224 天、编码约 48KB JSON 再跨一次端；原生侧收到还会把所有
// 实例重渲染一遍。内容没变的那几次（最常见的是「回前台」）纯属白付。
//
// ⚠️ **推失败不许记「已推」**：那条「装完新版先打开一次 App」的兜底重试，靠的正是
// 回前台那一次；记错了它就永远不再试，桌面小组件会一直挂着升级前那一次的渲染。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/features/widget/widget_service.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

const MethodChannel _channel =
    MethodChannel('com.daoban.shiftassistantpro/settings');

/// 装一个只会数 `widgetPushSnapshot` 的假通道，跑 [body]，返回它发了几次。
/// [failFirst] 让前 N 次抛 —— 用来验「失败不许记成已推」。
Future<int> _pushesOf(Future<void> Function() body, {int failFirst = 0}) async {
  var pushes = 0;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    if (call.method != 'widgetPushSnapshot') return null;
    pushes++;
    if (pushes <= failFirst) throw PlatformException(code: 'boom');
    return true;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));
  await body();
  return pushes;
}

Future<void> _push({int todoCount = 3}) => WidgetService.push(
      chain: null,
      settings: const AppSettings(),
      todayTodoCount: todoCount,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 快照里有月份标题（`L10n.monthTitle` 走 intl）—— 不初始化 locale，
    // `buildWidgetSnapshot` 会抛 `LocaleDataException`，而它被 `push` 的 catch
    // 吞掉，表现是「一次都没发出去」（排查时先看 `logInfo` 那条痕）。
    await initializeDateFormatting('zh');
  });

  // 去重的「上一份」是模块级状态，用例之间要清掉。
  setUp(WidgetService.resetPushCache);

  test('同一份内容连推两次，只发一次', () async {
    final int n = await _pushesOf(() async {
      await _push();
      await _push();
    });
    expect(n, 1, reason: '内容一模一样还推第二遍 —— 白付一次跨端 + 原生全量重渲染');
  });

  test('内容变了（今日待办数变了）就再推一次', () async {
    final int n = await _pushesOf(() async {
      await _push(todoCount: 3);
      await _push(todoCount: 4);
    });
    expect(n, 2, reason: '待办数变了，桌面那张卡上的徽章要跟着变 —— 这不算重复');
  });

  test('推失败时不记「已推」，下一次照样重试', () async {
    // 反向验证过：把「成功之后才记」改成「发之前就记」，这条立刻红（1 != 2）。
    final int n = await _pushesOf(() async {
      await _push();
      await _push();
    }, failFirst: 1);
    expect(n, 2,
        reason: '第一次失败了就不能记「已推」—— 否则「装完新版先打开一次 App」'
            '那条兜底重试永远不再试，桌面停在升级前那一次渲染');
  });
}
