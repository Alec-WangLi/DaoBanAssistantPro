// app/test/glass_pill_height_test.dart
//
// 两处**唯一入口**的胶囊命中高度（v0.12.0 Task 5）。
//
// 背景：这两处原来各是一颗裸 `TextButton`，M3 默认 `minimumSize` 40 +
// `MaterialTapTargetSize.padded` ⇒ **48dp 命中区**。换成 `GlassPill` 之后命中区
// 就等于它自己那个 `Container(height:)`，**没有任何额外扩展**。第一版我写了 32
// —— 那是**整整 32** 的命中区，而这两处都是唯一入口（「管理模板」是模板管理的
// 唯一入口；「去开启」是那几项权限的唯一引导），不能缩。改回仓库既有的
// 「紧凑入口」那一档 **36**（与待办页的「重复待办」「已完成 N 条」同档）。
//
// 这个用例钉的是**实际渲染出来的尺寸**，不是源码里的常量 —— 改常量不核等于没改。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/widgets/glass_pill.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/schedule_template.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';

import 'support/plugin_channels.dart';

/// 紧凑入口那一档（`GlassPill` 文档注释里写的「紧凑入口用 36」）。
const double _compactEntryHeight = 36;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.locale = 'zh';
  });
  tearDown(() => L10n.locale = 'zh');

  /// 量一个 `GlassPill` 的渲染尺寸。找不到时给一条带标签的失败。
  Size pillSize(WidgetTester tester, Finder pill) {
    expect(pill, findsWidgets, reason: '没找到胶囊：$pill');
    return tester.getSize(pill.first);
  }

  testWidgets('倒班方式选择：分组标题旁的「管理」胶囊命中高 36、且按内容定宽', (tester) async {
    // 窄屏：命中区与内容宽都要在最容易出问题的那一档成立。
    tester.view.physicalSize = const Size(200, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = AppRepository(db);
    // 「我的模板」那一组只在库里有模板时才出现 —— 那正是「管理」入口所在的分组。
    await repo.saveTemplate(ScheduleTemplate.fromSchedule(
      ShiftSchedule(
        name: '白夜休',
        anchorDate: DateTime.utc(2026, 1, 1),
        classes: const [
          ShiftClass(name: '白班', abbr: '白'),
          ShiftClass(name: '休班', abbr: '休'),
        ],
        cycle: const [0, 0, 1],
      ),
      name: '我的模板',
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ShiftTemplatePickerScreen()),
    ));
    await tester.pumpAndSettle();

    final pill = find.ancestor(
      of: find.text(L10n.manageTemplates),
      matching: find.byType(GlassPill),
    );
    final size = pillSize(tester, pill);
    expect(size.height, _compactEntryHeight,
        reason: '「管理」是模板管理的唯一入口，命中高掉到 ${size.height} 就是缩水');
    expect(size.width, lessThan(120),
        reason: '要按内容定宽，别铺满整行（铺满会读成一条行）');
  });

  testWidgets('「我的」页权限卡：「去开启」胶囊命中高 36、且按内容定宽', (tester) async {
    stubPluginChannels();
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await AppRepository(db).ensureSeeded();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ProfileScreen()),
    ));
    // **不能 `pumpAndSettle`**：权限卡 `initState` 会去调一串在测试里永不 resolve
    // 的原生方法（同 `section_heading_test` / `snooze_duration_test`）。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    // 权限卡在页面**下半屏**，`ListView` 懒构建 —— 不滚下去它根本不在树上
    // （工装那张 `07_profile_*_scrolled` 也是这么滚的）。
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    // 「我的」页唯一的 `GlassPill` 就是权限卡里那些入口（去开启 / 去查看），
    // 所以直接量全部，逐个数都必须是 36 高、且按内容定宽。
    final pills = find.byType(GlassPill);
    final count = tester.widgetList(pills).length;
    expect(count, greaterThan(0), reason: '权限卡本该渲染出「去开启 / 去查看」入口');
    for (var i = 0; i < count; i++) {
      final size = tester.getSize(pills.at(i));
      expect(size.height, _compactEntryHeight,
          reason: '第 $i 个权限入口命中高掉到 ${size.height}');
      // 铺满整行会读成一条行（`ListTile.trailing` 是有限宽，不套 `IntrinsicWidth`
      // 就会铺满 —— 见调用点的注释）。屏宽 360，给一个明显小于整行的上界。
      expect(size.width, lessThan(160),
          reason: '第 $i 个权限入口铺满了整行（${size.width}）');
    }
  });
}
