// 玻璃档位的结构性护栏。
//
// 阶段 1 管「标准档」：`GlassPanel` / `GlassBlur` 的 filter 必须是
// **「模糊 + 真实饱和度」的复合**，不是裸的一层 blur。
//
// 为什么值得钉：`glass.dart` 顶上那段注释一直写着「2) 半透明渐变着色（近似饱和度
// 提升）」—— 那是拿一层白渐变**假装**饱和度。这一版把它换成真的之后，任何一次
// 「顺手简化回 `ImageFilter.blur(...)`」都会让 App 静默退回那个「近似」的观感，
// 而那种退步**不会报错、也未必一眼看得出来**。

import 'dart:ui' show ImageFilter;

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/plugin_channels.dart';

/// 装配一个 GlassPanel 并取回它那层 `BackdropFilter` 的 filter。
///
/// 返回可空：`BackdropFilter.filter` 本身可空（null = 不过滤）。为 null 时
/// 下面那条 `isNot(blur)` 会过 —— 所以调用点必须先断言它非空，别让空值蒙混过去。
Future<ImageFilter?> _panelFilter(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: GlassPanel(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    ),
  );
  final backdrop =
      tester.widget<BackdropFilter>(find.byType(BackdropFilter));
  return backdrop.filter;
}

void main() {
  setUpAll(() async {
    // 主壳里的日期要 intl 的语言数据，不初始化会抛 `LocaleDataException`
    // （报在 `MaterialApp` 的 Builder 上，与真因隔了好几层）。
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    // `shotShell` 每次开一个内存库；一个用例里开两次会触发 drift 的重复实例告警，
    // 那是开发期的提示，不是问题。
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    // 每个用例从「标准档」起跑：省电关、液态关。这两个都是模块级标志，
    // 前一个用例把它们打开过就会漏到这一个里。
    lowEndDevice = false;
    liquidGlassEnabled.value = false;
    recomputeGlassTiers();
  });

  test('glassSaturation 就是 spec 写的 Rec.709 保亮度矩阵（s = 1.2）', () {
    // 钉的是**公式**：`invSat * L_i`（对角线上再加 s），L 取 Rec.709 的三个亮度系数。
    //
    // 为什么照着公式算一遍、而不是写一组四舍五入的字面量：`ColorFilter` 的 `==`
    // 是按内容**逐位比 double** 的，而 `-0.2 * 0.7152` 是 `-0.14303999999999994`，
    // 不等于手抄的 `-0.14304`。写死字面量只会得到一条假红。
    //
    // 这条钉子守的是：`ColorFilter.saturation(1.2)` 是 SDK 的实现细节、不是契约 ——
    // 哪天它换了亮度系数（Rec.709 → Rec.601）或换了语义，观感会跟着变而没有任何
    // 东西报警。把 spec 的公式钉在这里，那种改变会立刻变红。
    const double s = 1.2;
    const double lr = 0.2126;
    const double lg = 0.7152;
    const double lb = 0.0722;
    const double invSat = 1 - s;
    expect(
      AppTokens.glassSaturation,
      const ColorFilter.matrix(<double>[
        invSat * lr + s, invSat * lg, invSat * lb, 0, 0, // R
        invSat * lr, invSat * lg + s, invSat * lb, 0, 0, // G
        invSat * lr, invSat * lg, invSat * lb + s, 0, 0, // B
        0, 0, 0, 1, 0,
      ]),
    );
  });

  testWidgets('标准档：GlassPanel 的 filter 不只是一层模糊', (tester) async {
    final filter = await _panelFilter(tester);

    expect(filter, isNotNull, reason: 'GlassPanel 根本没挂 filter');
    expect(
      filter,
      isNot(ImageFilter.blur(
          sigmaX: AppTokens.blurPanel, sigmaY: AppTokens.blurPanel)),
      reason: 'filter 还是裸的 blur —— 真实饱和度没有接进去，'
          '观感退回「白渐变近似饱和度」那一版',
    );
  });

  testWidgets('标准档：GlassPanel 的 filter 恰好是「模糊 + 饱和度」的复合',
      (tester) async {
    final filter = await _panelFilter(tester);

    // 精确到 sigma 与内外层顺序 —— `compose` 的语义是 `outer(inner(source))`，
    // 两者写反了照样是个合法 filter，只是「先糊再提饱和」变成了「先提饱和再糊」，
    // 上面那条「不是裸的 blur」**抓不到**这种错。
    expect(
      filter,
      ImageFilter.compose(
        outer: ImageFilter.blur(
            sigmaX: AppTokens.blurPanel, sigmaY: AppTokens.blurPanel),
        inner: AppTokens.glassSaturation,
      ),
      reason: '复合出来的不是「该有的模糊 × 该有的饱和度」',
    );
  });

  testWidgets('标准档：GlassBlur 的 filter 也是「模糊 + 饱和度」的复合',
      (tester) async {
    const sigma = 8.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              ColoredBox(color: Color(0xFF7A8A9A)),
              GlassBlur(
                sigma: sigma,
                child: SizedBox(width: 40, height: 40),
              ),
            ],
          ),
        ),
      ),
    );

    final backdrop =
        tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(
      backdrop.filter,
      ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        inner: AppTokens.glassSaturation,
      ),
    );
  });

  testWidgets('省电档：GlassBlur 直接返回 child，一层 filter 都不套',
      (tester) async {
    // 省电档的地基：`glassBlurDisabled` 时**短路**。改成「照常套一层、
    // 只是内容透明」之类的写法，低内存机器就白付一次 backdrop 抓取 ——
    // 而那正是这一档存在的理由。
    lowEndDevice = true;
    recomputeGlassTiers();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassBlur(
            sigma: 8,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  group('档位判据（标准 / 液态两档可选；省电只由低内存自动进）', () {
    test('默认 = 标准档：两个开关都不动', () {
      recomputeGlassTiers();
      expect(liquidGlassActive.value, isFalse);
      expect(glassBlurDisabled.value, isFalse);
    });

    test('液态玻璃打开 → 液态档', () {
      liquidGlassEnabled.value = true;
      recomputeGlassTiers();
      expect(liquidGlassActive.value, isTrue);
      expect(glassBlurDisabled.value, isFalse);
    });

    test('低内存机器：省电档是**地板**，液态打不开', () {
      // 这一条钉住「省电只由低内存自动进」那句话。判据写成一个「与」，
      // 漏掉 !lowEndDevice 那一项，低内存机器就会同时吃到省电与液态 ——
      // 那是「又糊又贵」的最坏组合。
      lowEndDevice = true;
      liquidGlassEnabled.value = true;
      recomputeGlassTiers();
      expect(glassBlurDisabled.value, isTrue, reason: '低内存机器一律糊');
      expect(liquidGlassActive.value, isFalse, reason: '省电档是地板，液态不该生效');
    });

    test('用户关掉液态玻璃 → 回落**标准**档，不是回落省电档', () {
      liquidGlassEnabled.value = false;
      lowEndDevice = false;
      recomputeGlassTiers();
      expect(liquidGlassActive.value, isFalse);
      expect(glassBlurDisabled.value, isFalse,
          reason: '关掉液态要回磨砂玻璃；回落到省电档是另一回事');
    });
  });

  group('设置的迁移保证', () {
    test('默认关；**旧键不该让液态档静默打开**', () async {
      // 老库里存的键叫 advancedMaterial（旧语义：true = 真实模糊，默认 true）。
      // 若沿用那个键，所有从没碰过它的人升级后都会静默吃上液态档 ——
      // 换新键（liquidGlass，默认 false）就是「一次性重置」，且结构上不会
      // 踩到「每次启动都重置」那个坑。
      SharedPreferences.setMockInitialValues(<String, Object>{
        'advancedMaterial': true,
      });
      final AppSettingsNotifier notifier = AppSettingsNotifier();
      await pumpEventQueue();
      expect(notifier.state.liquidGlass, isFalse);
      expect(liquidGlassEnabled.value, isFalse);
    });

    test('写下去的是新键', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppSettingsNotifier notifier = AppSettingsNotifier();
      await pumpEventQueue();
      await notifier.setLiquidGlass(true);
      final SharedPreferences sp = await SharedPreferences.getInstance();
      expect(sp.getBool('liquidGlass'), isTrue);
    });
  });

  /// 把一整块**主壳**光栅化成原始像素。
  ///
  /// 样本为什么是主壳、不再是某个玻璃件：**2026-10-01 起液态档只作用于底栏**
  /// （规格 §2 决策①），别的玻璃面两档本来就该一模一样 —— 继续拿它们当样本，
  /// 这条守门会变成一句「永远为假」的空话（`GlassPill` 那条就是这么失效的）。
  Future<List<int>> shotShell(
    WidgetTester tester, {
    required bool liquid,
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 主壳首帧后会请求权限；没有桩的话那是个没人接的异步异常，
    // flutter_test 会把整个用例判失败。
    stubPluginChannels();
    // **必须走 prefs，不能只拨模块级标志**：屏幕一 `ref.watch(appSettingsProvider)`
    // 就会建 notifier、`_load()` 读 prefs，把标志覆盖回去 —— v0.10.1 那两张
    // 「液态档」基线图与标准档逐字节相同，就是这么来的。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarded': true,
      'lastSeenVersion': appVersion,
      'liquidGlass': liquid,
    });
    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: RepaintBoundary(key: key, child: const HomeShell()),
      ),
    ));
    // **不能用 pumpAndSettle**：主壳里有一直调度下一帧的动画（背景光晕等），
    // 它会一直等到超时。逐帧推进既不会挂，结果也是确定性的。
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late List<int> bytes;
    // 取像要在真实异步区里（伪造时钟区里的 future 不会完成）。
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      bytes = data!.buffer.asUint8List().toList();
    });

    // 拆树并推一下时钟：drift 取消查询流时用 `Timer.run` 排了个零时长定时器，
    // 不推它跑掉，框架会在测试体结束时报「A Timer is still pending」。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    return bytes;
  }

  testWidgets('液态档**真的画了东西**：关 / 开两态的光栅化像素必须不同',
      (tester) async {
    // 这条守卫的来由，值得完整写下来：
    // v0.10.1 收口时，工装里的 `36_home_shell_liquid_*` / `37_profile_liquid_*`
    // 与各自的标准档图**逐字节相同**（md5 实测）。根因是档位标志被
    // `AppSettingsNotifier._load()` 从 prefs 覆盖了回去 —— 于是**这一档从没被
    // 渲染过一次**，而「出图看差异、差异必须看得见」那道人工验收闸门在差异为 0
    // 时静默通过。没有鉴别的断言，那种失败看起来和成功一模一样。
    final List<int> off = await shotShell(tester, liquid: false);
    final List<int> on = await shotShell(tester, liquid: true);

    int differing = 0;
    for (int i = 0; i < off.length; i++) {
      if (off[i] != on[i]) differing++;
    }
    expect(differing, greaterThan(0),
        reason: '开了液态玻璃却一个像素都没变 —— 这一档没有真的生效');
  });
}
