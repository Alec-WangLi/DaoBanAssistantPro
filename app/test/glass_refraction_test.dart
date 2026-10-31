// app/test/glass_refraction_test.dart
//
// 守门：**液态玻璃的边缘折射**（`GlassRefraction` / `GlassRefract` / `LiquidLens.spectral`）。
//
// 这一版最容易悄悄坏掉的地方，恰好是**像素用例看不见的那一层**：折射要 Impeller
// 后端才挂得上，而 `flutter test` 的渲染后端是 Skia —— 程序加载得出来、滤镜却抛
// `UnsupportedError`，于是 `GlassRefract` 在测试里永远退化成 `GlassBlur`，
// 「逐像素不变」那批用例照样全绿，而真机上底栏可能已经不弯了、或者分段器与开关
// 被顺手一起换掉了。
//
// 所以这里守的是**结构**与**判据**，不是像素：
//   1. 参数不漂移（带 / 位移 / 三波长）；
//   2. 闸门的派生规则只有一处，且是「液态档 ∧ 程序就绪」，省电档一律关；
//   3. 「程序就绪」不等于「这条链能用」—— 非 Impeller 后端必须**返回 null 而不是抛**，
//      且失败要粘住（Android 上 Impeller 回落到 Skia 的机器走的就是这条路）；
//   4. 闸门全不过时 `GlassRefract` 构造出的滤镜与 `GlassBlur` **逐字节相同**
//      —— 这是「换与不换只差真机上那一层」的唯一证据；
//   5. `LiquidTrack` 的默认值仍是「画彩虹 + 纯模糊」，且**全 app 只有底栏那一处**
//      传 `refract: true` / `spectral: false`（扫源码，剥过注释与字符串）；
//   6. `LiquidLens.spectral = false` 真的关掉了那圈彩色，**但没有**关掉玻璃本身
//      （凸出、白芯、折边都还在）。
//
// 第 5 条是本轮最值钱的一条：`LiquidTrack` 是三处共用的（底栏 / 分段器 / 开关），
// 而折射的参数是按底栏那枚 64 高的胶囊量的 —— 46 宽的开关上带会被夹到 14、
// 位移 8 相当于钮高的 29%，那不是「边缘弯一点」，是整颗钮在抖。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/glass/glass_refraction.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens.dart';
import 'package:shiftassistantpro/core/glass/liquid_lens_controller.dart';
import 'package:shiftassistantpro/core/widgets/liquid_track.dart';

import 'support/source_scan.dart';

/// 底栏那枚胶囊的高度。折射的三个参数都是按它量的，所以单独摆出来。
const double _navCapsuleH = 64;

/// 走一遍 `lib/`，返回「代码里（不含注释 / 字符串）出现 [needle]」的文件路径。
///
/// 排序是为了失败信息**确定**：`listSync` 的顺序取决于文件系统。
List<String> _filesMatching(String needle) {
  final hits = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (blankNonCode(entity.readAsStringSync()).contains(needle)) {
      hits.add(entity.path.replaceAll(r'\', '/'));
    }
  }
  hits.sort();
  return hits;
}

void main() {
  // ── 1. 参数 ─────────────────────────────────────────────────────────────

  test('折射参数是按底栏那枚 64 高胶囊量的，改它就得重新量一遍', () {
    // 带 20 = 胶囊高的三分之一（再宽就盖到图标下面，读起来像整块玻璃在抖）；
    // 位移 8 = 看得出弯、又不到「糊成一团」；三波长 0.055 = 极窄的冷暖分离，
    // 不是彩虹环。
    //
    // 这三个数**同时**是「为什么不能无条件换进 LiquidTrack」的依据：46 宽的开关上
    // 带被 `clamp` 到 14、位移 8 是钮高（29）的 27.6%。
    final List<double> p = GlassRefraction.debugParams();
    expect(p[0], 20, reason: '折射带宽度变了 —— 这条是按 64 高胶囊量的');
    expect(p[1], 8, reason: '最大位移变了 —— 大了就糊成一团、小了看不出弯');
    expect(p[2], 0.055, reason: '三波长偏移变了 —— 大了就是彩虹环，不是玻璃');
    expect(
      p[1] / _navCapsuleH,
      lessThan(0.2),
      reason: '位移已经超过底栏胶囊高的 20% —— 那不是「边缘弯一点」',
    );
  });

  // ── 2. 闸门 ─────────────────────────────────────────────────────────────

  setUp(() {
    GlassRefraction.debugReset();
    lowEndDevice = false;
    liquidGlassEnabled.value = false;
    recomputeGlassTiers();
  });
  tearDown(() {
    GlassRefraction.debugReset();
    lowEndDevice = false;
    liquidGlassEnabled.value = false;
    recomputeGlassTiers();
  });

  test('程序没就绪时 filter 返回 null —— 闸门 2 在构造层就挡住了', () {
    expect(GlassRefraction.available, isFalse, reason: '开局就绪了 —— 闸门 2 失效');
    expect(
      GlassRefraction.filter(
        size: const Size(200, _navCapsuleH),
        dpr: 3,
        radius: _navCapsuleH / 2,
        tint: null,
        blur: glassFilter(AppTokens.blurPanel),
      ),
      isNull,
      reason: '程序没就绪却造出了滤镜 —— 闸门 2 没起作用',
    );
  });

  test('「程序就绪」不等于「这条链能用」：非 Impeller 后端返回 null 而不是抛', () async {
    // **这是本轮最重要的一条。** 实测（探针跑在 `flutter test` 里）：
    //   · `FragmentProgram.fromAsset` 在 Skia 上**加载成功**（下面第一个断言就是它）；
    //   · 而 `ui.ImageFilter.shader` 在 Skia 上直接抛
    //     `UnsupportedError: ImageFilter.shader only supported with Impeller`。
    //
    // 于是 `isPlatformCapable` 那道闸门是**必要但不充分**的：Android 上 Impeller
    // 回落到 Skia 的机器（老设备 / Vulkan 不稳的机型 / `--no-enable-impeller` 的
    // 构建）平台判据过得去、程序也加载得出来，只有构造滤镜那一行会炸 —— 而它跑在
    // `GlassRefract.build` 里，每帧一次，底栏直接红屏，且**只在部分机型上**。
    //
    // 这条用例同时钉住三件事：加载得出来、不抛、失败粘住。
    await GlassRefraction.warmUp();
    await GlassRefraction.warmUp(); // 幂等：`main()` 与用例都可能调它
    expect(
      GlassRefraction.available,
      isTrue,
      reason: 'asset 没被打进 test bundle —— 「像素用例看不见折射」这个前提变了，'
          '这条用例与文件头那段说明都得重写',
    );

    final ui.ImageFilter? built = GlassRefraction.filter(
      size: const Size(200, _navCapsuleH),
      dpr: 3,
      radius: _navCapsuleH / 2,
      tint: null,
      blur: glassFilter(AppTokens.blurPanel),
    );
    expect(built, isNull, reason: 'Skia 上造出了滤镜 —— 要么后端换了，要么没接住');
    expect(
      GlassRefraction.available,
      isFalse,
      reason: '失败没粘住 —— 每帧都会再抛一次',
    );
  });

  test('闸门派生规则：折射 = 液态档 ∧ 程序就绪；省电档一律关', () {
    // 判据只许有一处出口（`recomputeGlassTiers`）。别处再写一遍的话，
    // 「程序加载完成后再调一次」那条路就会漏掉一半。
    expect(
      liquidRefractionEnabled.value,
      isFalse,
      reason: '液态档关着，折射位却是 true',
    );

    liquidGlassEnabled.value = true;
    recomputeGlassTiers();
    expect(liquidGlassActive.value, isTrue, reason: '液态档没生效 —— 前提就不成立');
    expect(
      liquidRefractionEnabled.value,
      GlassRefraction.available,
      reason: '折射位必须等于「液态档 ∧ 程序就绪」—— 它不是第二个人说了算',
    );

    lowEndDevice = true;
    recomputeGlassTiers();
    expect(liquidGlassActive.value, isFalse);
    expect(
      liquidRefractionEnabled.value,
      isFalse,
      reason: '省电档下折射还开着 —— 这一档是给低端机留的，不该多付一次 backdrop',
    );
  });

  // ── 3. 退化路径与 GlassBlur 逐字节相同 ──────────────────────────────────

  testWidgets('闸门不过时 GlassRefract 挂的滤镜与 GlassBlur 完全一样', (tester) async {
    // 这是「调用点可以无条件换成 GlassRefract」的全部依据。滤镜差一点点，
    // 底栏在真机上就会比标准档糊得不一样 —— 而像素用例照样全绿。
    glassBlurDisabled.value = false;
    liquidRefractionEnabled.value = false;
    addTearDown(() => liquidRefractionEnabled.value = false);

    Future<ui.ImageFilter?> filterOf(Widget child) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 200, height: _navCapsuleH, child: child),
            ),
          ),
        ),
      );
      final Finder f = find.byType(BackdropFilter);
      expect(f, findsOneWidget, reason: '这一档应该恰好挂一层 backdrop');
      return tester.widget<BackdropFilter>(f).filter;
    }

    final ui.ImageFilter? blur = await filterOf(
      const GlassBlur(sigma: AppTokens.blurPanel, child: SizedBox.expand()),
    );
    final ui.ImageFilter? refract = await filterOf(
      const GlassRefract(
        sigma: AppTokens.blurPanel,
        size: Size(200, _navCapsuleH),
        radius: _navCapsuleH / 2,
        child: SizedBox.expand(),
      ),
    );

    expect(refract, equals(blur), reason: '退化路径与 GlassBlur 不是同一个滤镜');
    expect(
      refract,
      equals(glassFilter(AppTokens.blurPanel)),
      reason: '滤镜不是 glassFilter(sigma) —— 那会把饱和度矩阵也一起换掉',
    );
  });

  testWidgets('省电档下 GlassRefract 连 backdrop 都不挂（与 GlassBlur 同一条路）', (tester) async {
    glassBlurDisabled.value = true;
    addTearDown(() => glassBlurDisabled.value = false);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: _navCapsuleH,
              child: GlassRefract(
                sigma: AppTokens.blurPanel,
                size: Size(200, _navCapsuleH),
                radius: _navCapsuleH / 2,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing,
        reason: '省电档还挂着 backdrop —— 低端机上那是最贵的一笔');
  });

  // ── 4. 谁换了、谁没换 ───────────────────────────────────────────────────

  testWidgets('LiquidTrack 的默认值：不传时仍是「画彩虹 + 纯模糊」', (tester) async {
    // 默认值就是那三处的契约：分段器与开关**一个字都没传**，它们必须保持原样。
    final controller = LiquidLensController(
      slots: 3,
      pad: 0,
      liftWidth: AppTokens.lensLiftWidth,
      vsync: tester,
    );
    addTearDown(controller.dispose);
    final track = LiquidTrack(
      slots: 3,
      capsuleH: _navCapsuleH,
      pad: 0,
      controller: controller,
      contentBuilder: (BuildContext context, double itemW) =>
          const SizedBox.shrink(),
    );
    expect(track.spectral, isTrue, reason: '默认关掉了彩虹 —— 分段器与开关跟着一起没了');
    expect(track.refract, isFalse, reason: '默认开了折射 —— 46 宽的开关会被整颗弯掉');
  });

  test('全 app 只有底栏那一处同时传 refract: true 与 spectral: false', () {
    // 扫的是**剥过注释与字符串**的副本：否则注释里提一句就会把构建打红。
    const String navBar = 'lib/features/home/glass_nav_bar.dart';

    final refractOn = _filesMatching('refract: true');
    expect(
      refractOn,
      <String>[navBar],
      reason: '折射被开到了底栏之外。`GlassRefraction` 的三个参数是按底栏那枚 '
          '64 高胶囊量的，换到别的尺寸上就不是「边缘弯一点」了。',
    );

    final spectralOff = _filesMatching('spectral: false');
    expect(
      spectralOff,
      <String>[navBar],
      reason: '画出来的那圈彩虹被关到了底栏之外 —— 分段器 / 开关没有真折射接手'
          '那圈光，关掉之后它们拖动时就变成「一枚没有边缘光的玻璃滴」。',
    );

    // 自证：`GlassRefract` 的调用点只有一处（`glass.dart` 是定义，不算调用）。
    final refractUses = _filesMatching('GlassRefract(')
      ..remove('lib/core/glass/glass.dart');
    expect(
      refractUses,
      <String>['lib/core/widgets/liquid_track.dart'],
      reason: 'GlassRefract 在别处被直接用了 —— 那会绕过 `refract` 那个开关，'
          '把「谁换了」这件事散到调用点上去。',
    );
  });

  // ── 5. spectral 真的关掉了什么、又没关掉什么 ───────────────────────────

  const Size canvas = Size(200, 120);
  const Size capsule = Size(120, _navCapsuleH);

  Widget capsuleStage(Widget lens) {
    final double top = (canvas.height - capsule.height) / 2;
    return SizedBox.fromSize(
      size: canvas,
      child: Stack(clipBehavior: Clip.none, children: <Widget>[
        Positioned(
          left: 0,
          top: top,
          width: capsule.width,
          height: capsule.height,
          child: const ColoredBox(color: Color(0xFFF5F6FA)),
        ),
        Positioned(
          left: 0,
          top: top,
          width: capsule.width,
          height: capsule.height,
          child: lens,
        ),
      ]),
    );
  }

  Future<List<int>> shot(WidgetTester tester, {required bool spectral}) async {
    tester.view.physicalSize = canvas;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const Color accent = Color(0xFF12B5A5);
    final LiquidLensShape shape = LiquidLensShape.of(
      itemW: capsule.width,
      capsuleH: capsule.height,
      pad: 0,
      centerPage: 0,
      lift: 1,
      velocity: AppTokens.lensVelocityRef,
      motionAngleDeg: spectralSweepRestAnchor,
    );

    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: capsuleStage(LiquidLens(
            size: capsule,
            outline: shape,
            lift: 1,
            isDark: false,
            accent: accent,
            spectral: spectral,
          )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late List<int> bytes;
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List()
          .toList();
      image.dispose();
    });
    return bytes;
  }

  /// 透镜范围内，色相离 [accent] 最远的那个像素偏了多少度。
  ///
  /// 只算**饱和度 > 0.25 且不透明**的像素：白芯与折边是低饱和的，它们的色相
  /// 是数值噪声，算进来会让断言变成抽奖。
  double maxHueDelta(List<int> px, Color accent) {
    final double base = HSLColor.fromColor(accent).hue;
    double worst = 0;
    for (int i = 0; i < px.length; i += 4) {
      if (px[i + 3] < 128) continue;
      final HSLColor c = HSLColor.fromColor(
          Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]));
      if (c.saturation < 0.25) continue;
      double d = (c.hue - base).abs() % 360;
      if (d > 180) d = 360 - d;
      if (d > worst) worst = d;
    }
    return worst;
  }

  int alphaAt(List<int> px, int x, int y) =>
      px[(y * canvas.width.toInt() + x) * 4 + 3];

  testWidgets('spectral: false 真的关掉了那圈彩色（对照组：默认开着时它亮）', (tester) async {
    const Color accent = Color(0xFF12B5A5);
    final List<int> off = await shot(tester, spectral: false);
    final List<int> on = await shot(tester, spectral: true);

    expect(
      maxHueDelta(on, accent),
      greaterThan(30),
      reason: '对照组不亮 —— 这条用例失去鉴别力（透镜自己的光谱环没画出来）',
    );
    expect(
      maxHueDelta(off, accent),
      lessThan(12),
      reason: 'spectral: false 却还有走色相的像素 —— 底栏那圈彩虹没被关掉',
    );
  });

  testWidgets('关掉彩虹不等于关掉玻璃：凸出与白芯照旧', (tester) async {
    // `showRingCore` / 折边那两层在 spectral 门控**之外**，是有意的：
    // 底栏关掉的只是「画出来的虹彩」，玻璃本身必须还在。
    final List<int> px = await shot(tester, spectral: false);
    final int top = ((canvas.height - capsule.height) / 2).round();

    expect(alphaAt(px, 60, top - 2), greaterThan(0),
        reason: 'spectral: false 之后透镜不再凸出胶囊 —— 那等于把玻璃也关了');
    expect(alphaAt(px, 60, top - 2), lessThan(255),
        reason: '凸出来的应该是玻璃，不是实心块');
    expect(alphaAt(px, 60, top + capsule.height.toInt() + 1), greaterThan(0),
        reason: '下沿没凸出 —— 同上');
  });
}
