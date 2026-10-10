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
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/state/app_settings.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/motion.dart';
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

  /// 按给定的液态档设置 pump 一次主壳，返回包着它那个 `RepaintBoundary` 的 key。
  ///
  /// **液态档必须走 prefs、不能只拨模块级标志**：屏幕一 `ref.watch(appSettingsProvider)`
  /// 就会建 notifier、`_load()` 读 prefs，把标志覆盖回去 —— v0.10.1 那两张
  /// 「液态档」基线图与标准档逐字节相同，就是这么来的。
  Future<GlobalKey> pumpShell(
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
    return key;
  }

  /// 拆树并推一下时钟：drift 取消查询流时用 `Timer.run` 排了个零时长定时器，
  /// 不推它跑掉，框架会在测试体结束时报「A Timer is still pending」。
  Future<void> disposeShell(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  }

  /// 把某个 key 那层 `RepaintBoundary` 光栅化成原始 RGBA。
  ///
  /// 单独抽出来，是因为有几条用例要在 [`disposeShell`] **之前**先量一次几何
  /// （`tester.getRect` 在树拆掉之后就找不到了）。
  ///
  /// ⚠️ 它**必须声明在 `shotShell` 前面** —— Dart 的局部函数不像字段那样可以
  /// 先用后声明（写了会报 `referenced_before_declaration`）。
  Future<List<int>> rasterize(WidgetTester tester, GlobalKey key) async {
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
    return bytes;
  }

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
    final GlobalKey key = await pumpShell(tester, liquid: liquid, size: size);
    final List<int> bytes = await rasterize(tester, key);
    await disposeShell(tester);
    return bytes;
  }

  /// 从底栏 `.85` 处（第 3 格）按下要用的位置。
  Offset lastTab(WidgetTester tester) {
    final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
    return Offset(nav.left + nav.width * 0.85, nav.center.dy);
  }

  /// 取**底栏那一枚**透镜。
  ///
  /// ⚠️ **必须限定在底栏里**：`GlassSegment` 接上液态档之后，「我的」页那个分段器
  /// 也有一枚 `LiquidLens`，`find.byType(LiquidLens)` 会撞上「Too many elements」。
  LiquidLens lensOf(WidgetTester tester) => tester.widget<LiquidLens>(
      find.descendant(
          of: find.byKey(const Key('glass-nav-bar')),
          matching: find.byType(LiquidLens)));

  testWidgets('交互契约两档一致：按住期间页面不动、松手才提交', (tester) async {
    // 这一条钉的是用户 2026-10-01 那句话的可断言形式：「点一下滑块自动过来、然后
    // 切页；长按滑块自动吸附，**松开滑块时**才切到它最终所在的那个区域」。
    //
    // 视觉可以不同，**提交时机不许不同**。
    Future<(List<int>, int)> run({required bool liquid}) async {
      await pumpShell(tester, liquid: liquid);
      final PageController c =
          tester.widget<PageView>(find.byType(PageView)).controller!;
      final TestGesture g = await tester.startGesture(lastTab(tester));
      final List<int> during = <int>[];
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40)); // 共 400ms
        during.add(c.page!.round());
      }
      await g.up();
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      final int after = c.page!.round();
      await disposeShell(tester);
      return (during, after);
    }

    final (List<int> stdDuring, int stdAfter) = await run(liquid: false);
    final (List<int> liqDuring, int liqAfter) = await run(liquid: true);

    expect(stdDuring, everyElement(0), reason: '按住期间页面就不该动');
    expect(liqDuring, stdDuring, reason: '两档按住期间的页面位置不一样');
    expect(stdAfter, 3, reason: '松手要落在滑块最终所在的那一格');
    expect(liqAfter, stdAfter, reason: '两档的提交终值不一样 —— 液态档换的应该只有视觉');
  });

  testWidgets('标准档的底栏树里没有透镜', (tester) async {
    await pumpShell(tester, liquid: false);
    expect(find.byType(LiquidLens), findsNothing, reason: '标准档里混进了液态档的元素');
    await disposeShell(tester);
  });

  testWidgets('液态档的底栏树里有透镜', (tester) async {
    await pumpShell(tester, liquid: true);
    // ⚠️ **必须限定在底栏里**：v0.10.15 起日历那一页也有一枚透镜，全页数会数到两枚。
    expect(
        find.descendant(
            of: find.byKey(const Key('glass-nav-bar')),
            matching: find.byType(LiquidLens)),
        findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('静止时透镜正对着选中那一格的中心', (tester) async {
    // **量纲的护栏。** 弹簧存的是透镜**中心**（格号 + 0.5），而 `_visualPage` 是
    // **左缘** —— 两套混了一个 0.5 的话，弹簧会把透镜一路拽到胶囊最左边，观感是
    // 「透镜整枚偏出胶囊左端」。第一版就是这么错的，而且当时那几条手感用例**全都
    // 照过**（它们只比较相对位移），所以必须有这一条直接量绝对位置的。
    await pumpShell(tester, liquid: true);
    final LiquidLens lens = lensOf(tester);
    const double pad = AppTokens.gapIconText;
    final double itemW = (lens.size.width - 2 * pad) / 4;
    expect(lens.shape.centerX, closeTo(pad + 0.5 * itemW, 1),
        reason: '透镜没坐在第 0 格的中心 —— 多半是「中心 / 左缘」两套量纲混了');
    await disposeShell(tester);
  });

  testWidgets('点按换页：透镜是滑过去的，不是瞬移过去的', (tester) async {
    await pumpShell(tester, liquid: true);
    final double startX = lensOf(tester).shape.centerX;
    final TestGesture g = await tester.startGesture(lastTab(tester));
    // **必须先把 `kPressTimeout` 等过去**（100ms）：这个 GestureDetector 同时挂着
    // tap 与横向拖动两个识别器，`onTapDown` 要等竞技场裁决才触发 —— 只泵 30ms 的话
    // 手势压根还没开始，量到的当然是「没动」。110ms 时 `_press` 刚跑、升程的闸门
    // （lensHoldDelay）还没开，正是「开始滑、但还没提起」的那一刻。
    for (int i = 0; i < 11; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    final double midX = lensOf(tester).shape.centerX;
    await g.up();
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final double endX = lensOf(tester).shape.centerX;

    expect(midX, greaterThan(startX + 5), reason: '按下之后透镜没动 —— 那是瞬移');
    expect(midX, lessThan(endX - 5), reason: '按下就到位了 —— 那不叫滑过去');
    await disposeShell(tester);
  });

  testWidgets('点按不提起：全程高度不超过胶囊', (tester) async {
    await pumpShell(tester, liquid: true);
    // 用透镜自己的 `size.height`（= 胶囊高），**不要用 `getRect(导航栏)`** ——
    // 底栏外面套着 `QScale`，按下时整棵被放大 6%，`getRect` 量到的不是胶囊高。
    final double capsuleH = lensOf(tester).size.height;
    final TestGesture g = await tester.startGesture(lastTab(tester));
    for (int i = 0; i < 3; i++) {
      // 3 × 30ms = 90ms < lensHoldDelay(110ms)
      await tester.pump(const Duration(milliseconds: 30));
      expect(lensOf(tester).shape.height, lessThanOrEqualTo(capsuleH + 0.5),
          reason: '快速点按不该把透镜提起来 —— 凸出胶囊是「按住」的专属信号');
    }
    await g.up();
    await disposeShell(tester);
  });

  testWidgets('按住才提起：超过 lensHoldDelay 之后高度必须超过胶囊', (tester) async {
    await pumpShell(tester, liquid: true);
    final double capsuleH = lensOf(tester).size.height;
    final TestGesture g = await tester.startGesture(lastTab(tester));
    for (int i = 0; i < 20; i++) {
      // 600ms
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(lensOf(tester).shape.height, greaterThan(capsuleH + 2),
        reason: '按住 600ms 了还没凸出胶囊');
    await g.up();
    await disposeShell(tester);
  });

  testWidgets('短屏：几何按矮胶囊（52）算，凸出仍然成立', (tester) async {
    await pumpShell(tester, liquid: true, size: const Size(900, 420));
    final double capsuleH = lensOf(tester).size.height;
    expect(capsuleH, closeTo(52, 1), reason: '这一档的胶囊该是 52 高');
    final TestGesture g = await tester.startGesture(lastTab(tester));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(lensOf(tester).shape.height, greaterThan(capsuleH + 2),
        reason: '矮屏下没凸出 —— 几何多半照抄了 64 的结论');
    await g.up();
    await disposeShell(tester);
  });

  testWidgets('点按被取消（竖直滑走）：透镜落回，不许卡在提起状态', (tester) async {
    await pumpShell(tester, liquid: true);
    final double capsuleH = lensOf(tester).size.height;
    final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
    final TestGesture g = await tester.startGesture(nav.center);
    // 600ms：先等 `kPressTimeout`（100ms）让 onTapDown 触发，再等
    // `lensHoldDelay`（110ms）让升程的闸门开，剩下才是升程真正爬起来的时间。
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(lensOf(tester).shape.height, greaterThan(capsuleH),
        reason: '这一步该是提起的');

    await g.moveBy(const Offset(0, -80)); // 竖直滑走 → 点按被取消
    await g.up();
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(lensOf(tester).shape.height, closeTo(capsuleH - 12, 1),
        reason: '_pressed 卡在 true —— 透镜永远提着凸在外面');
    await disposeShell(tester);
  });

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

  /// 主壳光栅化图里某个像素的红通道（[shotShell] 是 420×900、DPR 1.0）。
  ///
  /// 只取红通道：参与比较的几个值都是中性灰（白 / 黑 / 底色），三通道一起看是噪音。
  int redAt(List<int> px, int x, int y, {required Size size}) =>
      px[(y * size.width.toInt() + x) * 4];

  testWidgets('浅色档：胶囊左右两条边必须是同一个值（边光是**竖直**的，不是对角）',
      (tester) async {
    // 用户 2026-10-01：「浅色模式下底部胶囊的边缘镜片效果左边很浅，几乎看不清
    // 胶囊，右边有镜片效果。……要不要去掉我们背景的渐变色？」
    //
    // 先排除背景：胶囊**外侧**左右两边实测都是 `rgb(254,247,255)`，一模一样 ——
    // 光晕没在左右制造任何亮度差（而且 `FlowingBackground` 只在日历页与响铃页，
    // 底栏四个 tab 里另外三个根本没有它）。差全在边光自己身上，所以**不该去动背景**。
    //
    // 根因：`AppTokens.glassRimProbe()` 配的是 `topLeft → bottomRight` 的**对角**
    // 线性渐变。这套配方是照**近方形卡片**量的（在卡片上读作「左上高光 + 右下收边」），
    // 可底栏胶囊是 372×64（约 6:1），渐变轴几乎就是水平的 —— 于是退化成
    // **左端纯白、右端 10% 黑**。左边那圈 α=1.0 的纯白既压在近白的底上看不见，
    // 又把胶囊自己那条 14% 的深色轮廓线整个盖掉，所以「几乎看不清胶囊」。
    //
    // 改成竖直轴之后 t 只跟 **y** 有关：左右两个端头在同一个 y 上拿到的是**同一个
    // 颜色**，与宽高比无关。取样点取胶囊竖直中点（两端都落在 t = 0.5，那一段是
    // 透明的），于是两边必须同值。
    //
    // **反向验证**：把轴改回 `topLeft → bottomRight`，这条立刻红（实测 251 vs 203）。
    const Size size = Size(420, 900);
    final GlobalKey key = await pumpShell(tester, liquid: true, size: size);
    final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
    final List<int> px = await rasterize(tester, key);
    // 胶囊比 nav 那条边内缩 `_outerPad`（24）。取「最暗的那一个像素」当这条边的读数
    // —— 描边与边光都只有 1px 上下，钉死某一个 x 会被抗锯齿的相位差骗到。
    final int capL = (nav.left + 24).round();
    final int capR = (nav.right - 24).round() - 1;
    final int y = (nav.bottom - 32).round();
    int darkest(int from, int to) {
      int v = 255;
      for (int x = from; x <= to; x++) {
        v = v < redAt(px, x, y, size: size) ? v : redAt(px, x, y, size: size);
      }
      return v;
    }

    // 左边只取胶囊内缩 6px 以内：那里是 `_innerPad`，透镜（在选中那一格里）够不到。
    final int left = darkest(capL, capL + 5);
    final int right = darkest(capR - 5, capR);
    final int outside = redAt(px, capL - 6, y, size: size); // 胶囊外的页面底色

    expect((left - right).abs(), lessThanOrEqualTo(4),
        reason: '左右两条边差 $left vs $right —— 边光又在按对角走了（胶囊是 6:1，'
            '对角轴会退化成「左白右黑」）');
    expect(outside - left, greaterThanOrEqualTo(20),
        reason: '左缘比底色只暗 ${outside - left} 级，几乎看不见 —— '
            '浅色档的白色端又盖过胶囊自己的轮廓线了');
    await disposeShell(tester);
  });

  testWidgets('外部程序化切页：透镜也跟着走（不是只改了高亮）', (tester) async {
    // 待办提醒的通知被点开时会 `jumpToPage` 到待办页。标准档那条路有
    // `AnimatedPositioned` 替它演，液态档**没有** —— 透镜的位置是弹簧算的，
    // 而 `_syncFromController` 只写了 `_visualPage`、既没改弹簧的目标、也没把
    // Ticker 拉起来（那时它多半已经停了）→ **透镜会永远停在原来那一格**。
    //
    // 这条与 `home_shell_nav_test` 那条互补：那条量的是**高亮**，这条量的是**透镜**。
    addTearDown(() => AlarmService.openTodoRequested.value = false);
    await pumpShell(tester, liquid: true);
    final double before = lensOf(tester).shape.centerX;

    AlarmService.openTodoRequested.value = true;
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(lensOf(tester).shape.centerX, greaterThan(before + 20),
        reason: '页面翻过去了、透镜还停在原处');
    await disposeShell(tester);
  });

  testWidgets('标准档：点按被取消（竖直滑走）之后不再算按住', (tester) async {
    // 与液态档那条同源：`onTapCancel` 原来是个**空回调**，`_pressed` 会永远卡在
    // true —— 标准档下只是胶囊一直大 6%（大概没人注意过）。
    //
    // 两棵树接的是**同一个** `_onTapCancel`，但此前只有液态档那条用例 ——
    // 把标准档那一处改回 `() {}`，不会有任何用例变红。
    await pumpShell(tester, liquid: false);
    bool pressed() => tester
        .widget<QScale>(find.descendant(
            of: find.byKey(const Key('glass-nav-bar')),
            matching: find.byType(QScale)))
        .pressed;

    final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
    final TestGesture g = await tester.startGesture(nav.center);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 30)); // 过 kPressTimeout
    }
    expect(pressed(), isTrue, reason: '按下了却没进入按住态');

    // **竖直滑走不会取消点按** —— 这个 detector 只挂了 tap 与**横向**拖动两个
    // 识别器，竖直方向没人跟它抢竞技场，于是松手时 onTapUp 照样触发、onTapCancel
    // 压根不来（第一版这么写，把 onTapCancel 改回空回调也照样绿，等于没有鉴别力）。
    //
    // 真正能让 onTapCancel 落地的路径是**指针被系统取消**：按住之后被别的 App /
    // 来电 / 系统手势接管。那时拖动识别器还没赢（没超过 slop），
    // `onHorizontalDragCancel` 不会来，只有 onTapCancel —— 空回调的话
    // `_pressed` 就永远卡在 true。
    await g.cancel();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressed(), isFalse, reason: '_pressed 卡在 true —— 胶囊会一直大 6%');
    await disposeShell(tester);
  });

  testWidgets('彩边是渐入渐出的：不会一帧亮起、也不会一帧熄灭', (tester) async {
    // 用户 2026-10-01：「彩边出现得太突然了。我的手不动它时没有，一动它就突然出来
    // 了。能不能给它加个过渡动画，或者让它渐变出来？以及咱们手停下来的时候，也得
    // 有点过渡，不要突然就没了。」
    //
    // 「突然」有**两个**来源，第二个才是主要的：
    //   ① 亮度直接挂在瞬时速度上，60px/s 的阈一两帧就跨过去了；
    //   ② 光晕那两层与外溢那层**根本没乘 `motion`** —— 它们只在 `motion > 0.05`
    //      那道门上被一刀切开，一过门就是满亮度。
    // 现在四层都跟着同一条亮度走，而那条亮度本身走一条弹簧（亮起 / 熄灭两条）。
    //
    // ⚠️ **pump 的步长必须是 16ms**：`LiquidLensSpring.step` 把每帧积分封顶在
    // `lensMaxStep`（16ms），喂 55ms 一帧整段动画会慢 3.4 倍 —— 第一版用的就是
    // 55ms，量出来「渐入要 440ms」，与真机完全不是一回事（那版动图也因此拍错了）。
    await pumpShell(tester, liquid: true);
    final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
    final TestGesture g = await tester.startGesture(
        Offset(nav.left + nav.width * 0.18, nav.center.dy));
    double m() => lensOf(tester).shape.motion;

    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // 按住 400ms
    }
    expect(m(), lessThan(0.1), reason: '还没动就亮着');

    for (int i = 0; i < 7; i++) {
      await g.moveBy(const Offset(3, 0)); // 187px/s
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(m(), lessThan(0.4),
        reason: '动起来才 110ms 就快满了 —— 那是「啪」地出现，不是渐入');

    for (int i = 0; i < 15; i++) {
      await g.moveBy(const Offset(3, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(m(), greaterThan(0.95),
        reason: '一直拖着、350ms 了还没亮到满 —— 太拖沓');

    // 手指停住、**不松手**：速度归零 → 应该渐出
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // 160ms
    }
    expect(m(), greaterThan(0.4),
        reason: '停手 160ms 就基本没了 —— 那是「突然就没了」');

    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // 共 480ms
    }
    expect(m(), lessThan(0.1), reason: '停手 480ms 了还亮着 —— 淡不干净');

    await g.up();
    await disposeShell(tester);
  });
}

// ── 临时诊断（跑完即删）：把彩边亮度随时间的变化打出来 ──
