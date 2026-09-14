// app/tool/visual/visual_harness.dart
//
// 视觉渲染工装：把界面在**真字体**下渲染成 PNG，供人工审阅与前后对比。
//
// 为什么需要它：`flutter test` 默认字体把每个字形都画成方块，于是 widget 测试
// 只能断言「节点在不在」「文本是什么」，看不出「第二个字被裁掉」「行盒比格子高
// 出几像素」「这个间距很丑」——只有肉眼能发现的问题。这里把真字体装上、屏幕尺寸
// 钉死，让界面变成一张可看的图。
//
// 这不是像素回归基线：不比对、不失败，只产出渲染物。产物落在 gitignored 的
// `app/build/visual/`，用 `flutter test tool/visual/render_screens_test.dart` 生成。
//
// 字体是**探测**来的，不是写死的路径——换台机器跑不动时，缺哪一类会在输出里
// 明确写出来，而不是悄悄退回方块字。
//
// 这个文件放在 tool/ 而不是 test/，是为了不被 `flutter test` 默认跑起来（它只出图，
// 不是断言集）。代价是分析器不把它当测试代码看，于是 SharedPreferences 的
// setMockInitialValues 会被误报——实际调用方就是 `flutter test`。
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/core/theme/app_theme.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 渲染画布：6.8" 级别手机的常见逻辑尺寸（K90 Pro Max 一类）。
const Size kVisualSize = Size(420, 900);

/// 出图倍率。2.0 让文字边缘干净，同时 PNG 还不至于大到没法一眼看完。
const double kVisualDpr = 2.0;

/// 产物目录（相对 `app/`，即运行 `flutter test` 时的工作目录）。
///
/// 不是 `const`：宣传图脚本（`tool/promo/`）要在 main() 里把它改成
/// `build/promo`，免得把宣传用的截图混进回归工装的产物里。回归工装自己不碰它。
String kVisualOutDir = 'build/visual';

// ---------------------------------------------------------------------------
// 字体
// ---------------------------------------------------------------------------

/// 装上的字体家族名；CJK 走 fallback，拉丁仍用 Roboto。
const String _cjkFamily = 'HarnessCJK';

bool _fontsReady = false;
bool _latinLoaded = false;
bool _iconsLoaded = false;

/// 实际采用的 CJK 字体路径；null 表示一个都没找到（中文会渲染成方块）。
String? loadedCjkFont;

/// 探 SDK 根目录：`flutter test` 的可执行文件就在 SDK 内部
/// （.../flutter/bin/cache/artifacts/engine/<os>/flutter_tester.exe），
/// 从它逐级向上找带 `bin/cache/artifacts/material_fonts` 的目录即可，
/// 不依赖 FLUTTER_ROOT 环境变量是否被设置。
String? _findFlutterRoot() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    if (Directory('${dir.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Platform.environment['FLUTTER_ROOT'];
}

Future<void> _loadFamily(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(
        bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length)));
  await loader.load();
}

/// 候选 CJK 字体，按「更像正经 UI 字」排序。
///
/// 只用 .ttf：`.ttc` 是字体集合，引擎不保证能解析出里面第几个面，写进去
/// 可能整族加载失败，反而不如退到黑体。
const List<String> _cjkCandidates = [
  r'C:/Windows/Fonts/Deng.ttf', // 等线，最接近现代 UI 字重
  r'C:/Windows/Fonts/simhei.ttf', // 黑体
  r'C:/Windows/Fonts/simsunb.ttf', // 宋体-粗
  r'C:/Windows/Fonts/simfang.ttf', // 仿宋
  '/System/Library/Fonts/PingFang.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
];

/// 幂等。**必须在 `setUpAll` 里调用**，不能在用例体内。
///
/// 读字体文件是真 I/O，而 `testWidgets` 的用例体跑在 fake_async 的伪造时钟区里
/// ——那里的真 I/O future 不会完成，用例会静默挂死。`setUpAll` 不在那个区里。
Future<void> ensureVisualFonts() async {
  if (_fontsReady) return;
  _fontsReady = true;

  final root = _findFlutterRoot();
  if (root != null) {
    final dir = '$root/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final path = '$dir/${entry.value}';
      if (!File(path).existsSync()) continue;
      await _loadFamily(entry.key, path);
      if (entry.key == 'Roboto') {
        _latinLoaded = true;
      } else {
        _iconsLoaded = true;
      }
    }
  }

  final override = Platform.environment['VISUAL_CJK_FONT'];
  final candidates = override != null ? [override] : _cjkCandidates;
  for (final path in candidates) {
    if (!File(path).existsSync()) continue;
    try {
      await _loadFamily(_cjkFamily, path);
      loadedCjkFont = path;
      break;
    } catch (_) {
      // 这个面加载不了就试下一个，别让整轮渲染挂掉
    }
  }

  // 报告一次装载结果——少装了哪一类要一眼能看出来，否则会误以为
  // 「图里是方块」是界面本身的问题。
  final missing = [
    if (!_latinLoaded) '拉丁(Roboto)',
    if (!_iconsLoaded) '图标(MaterialIcons)',
    if (loadedCjkFont == null) '中文',
  ];
  stdout.writeln(missing.isEmpty
      ? '[visual] 字体就绪：Roboto + MaterialIcons + ${loadedCjkFont!}'
      : '[visual] 字体缺 ${missing.join(" / ")}，缺的部分会渲染成方块');

  // 「高级材质」若被关掉，玻璃退化成不透明填充，看不出真实观感。
  advancedMaterialDisabled = false;
  lowEndDevice = false;
  recomputeGlassBlur();

  // 每个用例各建一个内存库是有意为之（互不污染），drift 的「重复建库」告警
  // 在这个用法下纯属噪音。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
}

/// 把 CJK 挂到文本样式后面：拉丁仍走 Roboto，缺字时回落到中文字体。
///
/// 用 [TextTheme.apply] 而不是 `ThemeData(fontFamily:)`，是因为前者能同时设
/// fallback 列表；而控件里那些显式写的 `TextStyle(fontSize: 16)` 会 merge 到
/// 环境样式上，把这个 family 列表一并继承过去。
ThemeData _applyVisualFonts(ThemeData theme) {
  final cjk = loadedCjkFont == null ? const <String>[] : const [_cjkFamily];
  final latin = _latinLoaded ? 'Roboto' : null;
  return theme.copyWith(
    textTheme: theme.textTheme
        .apply(fontFamily: latin, fontFamilyFallback: cjk),
    primaryTextTheme: theme.primaryTextTheme
        .apply(fontFamily: latin, fontFamilyFallback: cjk),
  );
}


// ---------------------------------------------------------------------------
// 测试桩
// ---------------------------------------------------------------------------

/// 把插件通道挂上空实现。
///
/// 测试环境没有原生侧，没人接的 MethodChannel 会抛 MissingPluginException；
/// 而权限请求这类调用多半是在 `initState` 里 fire-and-forget 出去的，异常
/// 没有调用者去接，就成了未处理异步错误 —— flutter_test 直接判整个用例失败。
///
/// 统一返回 null 等价于「权限一个都没给」，界面落在一个确定的状态上。
void stubPluginChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'dexterous.com/flutter/local_notifications',
    'com.daoban.shiftassistantpro/settings',
  ]) {
    messenger.setMockMethodCallHandler(
        MethodChannel(name), (call) async => null);
  }
}

// ---------------------------------------------------------------------------
// 外壳
// ---------------------------------------------------------------------------

/// 与 `ShiftAssistantApp` 同构的最小外壳：同样的主题构造函数、同样的本地化
/// 委托、同样的语言开关。不直接用真的 App，是为了让每个用例能指定 home，
/// 从而单独渲染某一个屏。
class VisualApp extends StatelessWidget {
  const VisualApp({
    super.key,
    required this.home,
    this.brightness = Brightness.light,
    this.language = 'zh',
  });

  final Widget home;
  final Brightness brightness;
  final String language;

  @override
  Widget build(BuildContext context) {
    L10n.locale = language;
    final base = brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(language),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _applyVisualFonts(base),
      home: home,
    );
  }
}

// ---------------------------------------------------------------------------
// 数据
// ---------------------------------------------------------------------------

/// 一套贴近真实使用的数据：一条当前方案（四班三倒 + 跨午夜夜班）+ 一条备用
/// 方案（12 天长周期）。造两条是为了图片上看得到「排班管理」的多行形态、
/// 以及周期条在不同长度下的样子。
///
/// 返回当前方案的 id。
Future<int> seedVisualDatabase(AppDatabase db) async {
  final repo = AppRepository(db);

  // 班组名是要**落库**的数据（`saveSchedule` 用 L10n.defaultTeamNames 生成），
  // 而 L10n.locale 是个全局：不在这里钉死，这堆图的名字就取决于上一个用例
  // 把语言留成了什么，同一个界面两次渲染会不一样。
  L10n.locale = 'zh';

  final today = dateOnly(DateTime.now());

  // 六天一轮的四班三倒：白 / 白 / 中 / 中 / 夜 / 休。
  // 夜班跨午夜（20:30 → 08:00），专门让「跨午夜」那段展示逻辑有东西可画。
  final triShift = [
    const ShiftClass(name: '白班', abbr: '白', startMinute: 480, endMinute: 1080, color: 0xFF4C8DFF, alarmEnabled: true, alarmMinute: 420),
    const ShiftClass(name: '中班', abbr: '中', startMinute: 1080, endMinute: 1320, color: 0xFFFF9F0A),
    const ShiftClass(name: '夜班', abbr: '夜', startMinute: 1230, endMinute: 1920, color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 1170),
    const ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
  ];
  final currentId = await repo.saveSchedule(
    name: '炼油三部 · 四班三倒',
    anchorDate: today,
    classes: triShift,
    cycle: const [0, 0, 1, 1, 2, 3],
    makeCurrent: true,
    teamCount: 4,
    teamNames: L10n.defaultTeamNames(4),
    ourTeamIndex: 1,
    teamOffsets: const [0, 2, 4, 3],
  );

  // 12 天长周期，班次名长一点，用来检验名称/简称在窄列里的排布。
  final longCycle = [
    const ShiftClass(name: '白班', abbr: '白', startMinute: 480, endMinute: 1200, color: 0xFF4C8DFF),
    const ShiftClass(name: '上夜班', abbr: '上夜', startMinute: 1200, endMinute: 1920, color: 0xFF7A5CFF, alarmEnabled: true, alarmMinute: 1140),
    const ShiftClass(name: '下夜班', abbr: '下夜', startMinute: 0, endMinute: 480, color: 0xFF5A5F73),
    const ShiftClass(name: '大休', abbr: '休', isRest: true, color: 0xFF34C759),
  ];
  await repo.saveSchedule(
    name: '备选 · 12 天长周期',
    anchorDate: today.subtract(const Duration(days: 3)),
    classes: longCycle,
    cycle: const [0, 0, 0, 0, 3, 3, 1, 1, 1, 1, 2, 3],
    makeCurrent: false,
    teamCount: 2,
    teamNames: L10n.defaultTeamNames(2),
    ourTeamIndex: 0,
    teamOffsets: const [0, 6],
  );

  // 待办：信息卡日期行上那个「N 项待办」提示只在**选中那天**有待办时才画得出来，
  // 所以至少要在今天放一条。另外两条各有各的用：一条带提前提醒（列表副标题上
  // 那句提醒文案要有东西可显示）、一条已完成（已完成是另一套颜色 + 划线）。
  await repo.addEvent(
    title: '交体检报告',
    date: today,
    timeMinute: 14 * 60 + 30,
    advanceRemindMinutes: 15,
  );
  await repo.addEvent(title: '还备用钥匙', date: today);
  await repo.addEvent(
    title: '季度考核面谈',
    date: today.add(const Duration(days: 3)),
    timeMinute: 9 * 60,
    advanceRemindMinutes: 1440,
  );
  await db.into(db.scheduleEvents).insert(ScheduleEventsCompanion.insert(
        title: '领劳保用品',
        date: today,
        createdAt: DateTime.now(),
        isCompleted: const Value(true),
      ));

  return currentId;
}

/// 造库 + 造数据。调用方负责 `addTearDown(db.close)`。
Future<AppDatabase> makeVisualDatabase() async {
  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  await seedVisualDatabase(db);
  return db;
}

/// 所有屏都可能读 SharedPreferences（设置、引导、更新检查），给一份空的。
void setUpVisualPrefs() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
}

/// 让首启引导与「版本更新」弹窗都不弹。
///
/// 主壳（HomeShell）在首帧后会弹「使用帮助」，`lastSeenVersion` 与当前版本
/// 不一致时还会弹「更新简介」——两个都会盖住整个界面。
Map<String, Object> get onboardingPrefs => {
      'onboarded': true,
      'lastSeenVersion': appVersion,
    };

// ---------------------------------------------------------------------------
// 渲染
// ---------------------------------------------------------------------------

/// 有界推进若干帧。
///
/// 不用 `pumpAndSettle`：它要等到「没有待调度的帧」才返回，而加载中的
/// `CircularProgressIndicator`、`FlowingBackground` 这类无限动画永远在调度下一帧，
/// 一旦首帧就是加载态就会挂死。逐帧推进既不会挂，出图也是确定性的。
///
/// 帧数给足 1 秒：drift 的流查询要走几轮事件循环才会把数据送上来，前几帧
/// 屏幕上还是转圈。
Future<void> settleVisual(WidgetTester tester, {int frames = 60}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 装配一个界面、推进到稳定态，返回根 RepaintBoundary 的 key。
///
/// 出图（[renderScreen]）与对比度审计（`contrast_audit_test.dart`）都要先做这
/// 一步，差别只在装配完之后拿它干什么，所以拆出来共用。
///
/// [overrides] 换掉数据库等 provider；[beforeCapture] 可在稳定后做交互
/// （点开某天、展开某张卡），用来拍/量「操作之后」的状态。
///
/// 配对使用 [teardownVisual]。
Future<GlobalKey> pumpScreen(
  WidgetTester tester, {
  required Widget home,
  required List<Override> overrides,
  Brightness brightness = Brightness.light,
  String language = 'zh',
  Map<String, Object> extraPrefs = const {},
  Size size = kVisualSize,
  Future<void> Function(WidgetTester tester)? beforeCapture,
}) async {
  // 字体得在 setUpAll 里装好（见 ensureVisualFonts 的说明）。这里只做体检：
  // 忘了调用时给一句明确的话，而不是让图片出来全是方块再回头猜。
  if (!_fontsReady) {
    throw StateError(
        'ensureVisualFonts() 必须在 setUpAll 里 await 一次，否则中英文都渲染成方块。');
  }

  // 语言不能只靠 VisualApp 设 L10n.locale：各屏在 build 里 `ref.watch(appSettingsProvider)`
  // 重建，而那个 notifier 会从 SharedPreferences 读语言、反过来把 L10n.locale 覆盖
  // 回默认值——不写进 prefs 的话，「英文界面」渲染出来的其实还是中文。
  SharedPreferences.setMockInitialValues(
      <String, Object>{'language': language, ...extraPrefs});
  stubPluginChannels();

  tester.view.physicalSize = Size(
    size.width * kVisualDpr,
    size.height * kVisualDpr,
  );
  tester.view.devicePixelRatio = kVisualDpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // 测试环境默认关掉阴影，玻璃的立体感会整个塌掉；渲染期间打开。
  // 这是框架的调试变量，用例结束时框架会校验它必须是原值，所以归还点在
  // teardownVisual 的 finally 里，放 addTearDown 就太晚了（那跑在校验之后）。
  debugDisableShadows = false;

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: overrides,
        child: VisualApp(
          home: home,
          brightness: brightness,
          language: language,
        ),
      ),
    ),
  );
  await settleVisual(tester);

  if (beforeCapture != null) {
    await beforeCapture(tester);
    await settleVisual(tester);
  }
  return boundaryKey;
}

/// 收尾：拆掉控件树、推一帧、把 [pumpScreen] 借走的框架调试变量还回去。
///
/// 为什么要自己拆树：drift 在「查询流被取消」时会用 `Timer.run` 排一个零延时
/// 定时器去收尾。如果任由测试框架在用例结束时替我们拆，那个定时器是在拆树过程
/// 中才被排上的，没人再推帧 → 框架校验「不留下待处理定时器」直接失败。
Future<void> teardownVisual(WidgetTester tester) async {
  try {
    await tester.pumpWidget(const SizedBox.shrink());
    // 必须带一个**非零**时长：`tester.pump()` 不传参时不会推进 fake 时钟
    // （压根不调 elapse），零延时定时器因此永远不会触发。
    await tester.pump(const Duration(milliseconds: 1));
  } finally {
    debugDisableShadows = true;
  }
}

/// 渲染一个界面并存成 PNG。
Future<void> renderScreen(
  WidgetTester tester, {
  required String name,
  required Widget home,
  required List<Override> overrides,
  Brightness brightness = Brightness.light,
  String language = 'zh',
  Map<String, Object> extraPrefs = const {},
  Size size = kVisualSize,
  Future<void> Function(WidgetTester tester)? beforeCapture,
}) async {
  final boundaryKey = await pumpScreen(
    tester,
    home: home,
    overrides: overrides,
    brightness: brightness,
    language: language,
    extraPrefs: extraPrefs,
    size: size,
    beforeCapture: beforeCapture,
  );

  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // 取像与写盘都必须放进 runAsync。
  //
  // widget 测试跑在伪造的时钟/微任务区里：`toImage` 要把活派给引擎的真实
  // 任务队列再等回来，`File.writeAsBytes` 更是真 I/O —— 在伪造区里这两个
  // future 都不会完成。症状是文件被创建成 0 字节、测试一直不结束且不报错，
  // 极难从现象反推原因。
  final file = File('$kVisualOutDir/$name.png');
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: kVisualDpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
  });

  // 出图同时报一下逻辑尺寸，方便判断「图里挤」是不是因为画布比真机窄。
  stdout.writeln(
      '[visual] ${file.path}  ${size.width.toInt()}x${size.height.toInt()} @${kVisualDpr}x');

  await teardownVisual(tester);
}

/// 渲染时若控件树里出现了布局溢出，Flutter 会在控制台打 "A RenderFlex
/// overflowed"，但测试不会失败。这里主动把溢出抓成断言，让「图看着不对」
/// 变成「测试直接红」。
///
/// 必须在 pump 之前调用（拿 tester 的 FlutterError 钩子）。
void failOnOverflow(WidgetTester tester) {
  final previous = FlutterError.onError;
  final overflows = <String>[];
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first);
    }
    previous?.call(details);
  };
  // 收尾时统一报，**不要**在错误回调里当场 fail()：那会把异常抛进帧管线，
  // flutter_test 处理不了，症状是一条用例卡到超时、后面全部连锁失败 ——
  // 于是每一轮只看得到第一条溢出，修一条要重跑一次。收集后统一报，
  // 一轮就能看到全部。
  addTearDown(() {
    FlutterError.onError = previous;
    if (overflows.isNotEmpty) {
      fail('布局溢出（${overflows.length} 处）：\n${overflows.join('\n')}');
    }
  });
}

/// 当前生效方案的 id，给「打开编辑器」一类需要显式 id 的屏用。
Future<int> currentScheduleId(AppDatabase db) async {
  final row = await (db.select(db.shiftScheduleRows)
        ..where((s) => s.isCurrent.equals(true)))
      .getSingle();
  return row.id;
}
