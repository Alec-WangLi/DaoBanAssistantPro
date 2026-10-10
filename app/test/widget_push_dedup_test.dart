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
import 'dart:async';

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/schedule_chain.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/widget/widget_service.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

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

/// 落一套真排班，返回（仓库、链、方案 id）。
///
/// 用真库而不是手搓 `ShiftSchedule`：这一组要钉的正是「**改了某一天的班**之后
/// 快照指纹跟不跟得上」，而「哪一天归哪套、那天被改成什么」是链才知道的事。
Future<(AppRepository, ScheduleChain, int)> _seedChain() async {
  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);
  final AppRepository repo = AppRepository(db);
  final ShiftTemplate t =
      shiftTemplates.firstWhere((ShiftTemplate x) => x.id == 'four_crew_three_shift');
  final int id = await repo.saveSchedule(
    name: t.subtitle,
    anchorDate: dateOnly(DateTime.now()),
    classes: t.classes,
    cycle: t.cycle,
    makeCurrent: true,
    teamCount: t.teamCount,
    teamNames: L10n.defaultTeamNames(t.teamCount),
    ourTeamIndex: 0,
    teamOffsets: t.teamOffsets,
  );
  final ScheduleChain chain = (await repo.getActiveSchedules())!.chain;
  return (repo, chain, id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // 快照里有月份标题（`L10n.monthTitle` 走 intl）—— 不初始化 locale，
    // `buildWidgetSnapshot` 会抛 `LocaleDataException`，而它被 `push` 的 catch
    // 吞掉，表现是「一次都没发出去」（排查时先看 `logInfo` 那条痕）。
    await initializeDateFormatting('zh');
  });

  // 去重的「上一份」与「在飞」都是模块级状态，用例之间要清掉。
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

  test('改了某一天的班：必须重推（指纹要跟着**排班**走，不只是「卡片高度」）', () async {
    // ⚠️ 这一条是独立审查抓的：指纹原来复用了 `chain.cacheKey`，而那个是**信息卡
    // 高度**的指纹 —— 它**不含按天改班的覆盖、周期、班组起始日、班组错位**。
    // 于是「调一次班」之后指纹不变 ⇒ 不重推 ⇒ **桌面小组件一直画着旧的班**，
    // 而 App 里日历已经变了（静默、且是相对上一版的回归）。
    final (AppRepository repo, ScheduleChain chain, int id) = await _seedChain();
    final int n = await _pushesOf(() async {
      await WidgetService.push(
          chain: chain, settings: const AppSettings(), todayTodoCount: 3);
      await WidgetService.push(
          chain: chain, settings: const AppSettings(), todayTodoCount: 3);

      // 调班：把今天改成这套方案里的另一个班次
      final domain = await repo.getScheduleDomain(id);
      await repo.setDayOverrides(<DateTime>[dateOnly(DateTime.now())],
          classId: domain!.classes[1].id!);
      final ScheduleChain after = (await repo.getActiveSchedules())!.chain;
      await WidgetService.push(
          chain: after, settings: const AppSettings(), todayTodoCount: 3);
    });
    expect(n, 2, reason: '调过班之后没重推 —— 桌面小组件还停在旧班次上');
  });

  test('换语言：必须重推', () async {
    // 快照里的星期、月份标题、空表提示都取自 `L10n`（它跟着设置走 —— `app.dart`
    // 在 build 里把 `L10n.locale` 设成设置里那个值），所以换语言之后**内容**就变了，
    // 指纹（比内容）跟着变、必须重推。
    //
    // ⚠️ 这里要**照真实时序**来：光传 `AppSettings(language: 'en')` 而 `L10n.locale`
    // 还是 zh，快照内容其实一个字没变（那也是对的 —— 指纹比的是内容，不是「设置里
    // 写了什么」）。
    addTearDown(() => L10n.locale = 'zh');
    final int n = await _pushesOf(() async {
      await WidgetService.push(
          chain: null, settings: const AppSettings(), todayTodoCount: 3);
      L10n.locale = 'en';
      await WidgetService.push(
          chain: null,
          settings: const AppSettings(language: 'en'),
          todayTodoCount: 3);
    });
    expect(n, 2, reason: '换了语言没重推 —— 桌面小组件还停在旧语言');
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

  test('上一次还没回来时，第二次触发不发车；守卫放开之后照样能推', () async {
    // 触发点有五处（首帧 / 回前台 / 排班变 / 外观变 / 勾待办），它们**可能挨在一起**：
    // 保存一次排班会让好几个 provider 连着发。而 `push` 中间要同步构建 224 天 +
    // 编码两份 JSON + 跨一次端 —— 上一次还在飞的时候第二次进来，去重键又不同
    // （内容真的变了），于是两发一起压到原生侧、把所有实例重渲染两遍。
    var pushes = 0;
    final Completer<void> gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
      if (call.method != 'widgetPushSnapshot') return null;
      pushes++;
      if (pushes == 1) await gate.future; // 第一发挂着不返回
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    final Future<void> a = _push(todoCount: 3);
    await Future<void>.delayed(Duration.zero); // 让它跑到跨端那一步、挂住
    await _push(todoCount: 4); // 内容不同 ⇒ 去重拦不住，只能靠 in-flight 守卫
    expect(pushes, 1, reason: '上一次还没回来就发第二发 —— 原生侧会重渲染两遍');

    gate.complete();
    await a;

    await _push(todoCount: 5);
    expect(pushes, 2,
        reason: '守卫把闸门**永久**关死了 —— 那比没有守卫更糟：以后再也推不出去');
  });
}
