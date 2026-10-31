import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 玻璃容器的**边缘折射**：把背景按一笔位移重采样，让容器看起来是一块有厚度的玻璃。
///
/// 这件事 `BackdropFilter` 自己做不到 —— `ImageFilter.blur` 只把背景推开，不会让它弯。
/// 这里挂一个 `FragmentProgram` 在滤镜链的**最后**（模糊之后），逐像素算：
///
/// ```
/// 圆角矩形距离场 → 边缘一圈「厚度」→ 沿法线把采样点往外推 → 取色
/// ```
///
/// 与项目里既有的 `LiquidLens`（那枚凸出来的玻璃滴）不是一回事：透镜画的是**不透明
/// 的滴**，没有背景可采；这里处理的才是「透过容器边缘看见外面的东西」。
///
/// ## 闸门
///
/// 三道全过才会真正挂上去，任何一道不过都返回 `null`，调用点照旧走纯模糊：
///
/// 1. **平台** —— 只有 Android（Impeller）与 iOS 有稳定的 runtime effect 滤镜链；
/// 2. **程序** —— `shaders/glass_refraction.frag` 加载成功（桌面/测试环境里没有它时
///    会静默失败，这时整条折射不出现，而不是崩）；
/// 3. **档位** —— 由 [liquidRefractionEnabled] 决定，低端机、省电档、动画降级时关。
///
/// 第 3 道留在调用点（`glass.dart` 是唯一的判据出口），这一层只管前两道。
///
/// ⚠️ **前两道过了也不代表能用**：`ImageFilter.shader` 只有 Impeller 后端给得住，
/// 而 `FragmentProgram` 在 Skia 上照样加载成功。所以 [filter] 自己还有一层
/// try/catch —— 见那里「程序就绪不等于这条链能用」的说明。
class GlassRefraction {
  GlassRefraction._();

  /// 与 `pubspec.yaml` 的 `flutter: shaders:` 段逐字对应。
  static const String assetKey = 'shaders/glass_refraction.frag';

  static ui.FragmentProgram? _program;
  static bool _loading = false;
  static bool _failed = false;

  /// 程序是否已就绪。**就绪之前一律不挂滤镜** —— 首帧宁可少一层折射，也不要等它。
  static bool get available => _program != null;

  /// 加载只做一次。`main()` 里 fire-and-forget 调用即可；重复调用是安全的。
  ///
  /// 失败会**粘住**（[_failed] 置位后不再重试）：加载不出来多半是这台设备/这个构建
  /// 根本没有这个 asset，重试只会每帧白跑一次 `fromAsset`。
  static Future<void> warmUp() async {
    if (_program != null || _loading || _failed) return;
    if (!isPlatformCapable) {
      _failed = true;
      return;
    }
    _loading = true;
    try {
      _program = await ui.FragmentProgram.fromAsset(assetKey);
    } catch (e, s) {
      _failed = true;
      _program = null;
      // 不抛：折射是锦上添花，缺了它 App 必须照常跑。
      debugPrint('GlassRefraction: 加载 $assetKey 失败，折射层关闭。$e\n$s');
    } finally {
      _loading = false;
    }
  }

  /// 只有 Impeller 的移动端后端给得住这条链（`ImageFilter.shader` 串 `blur`）。
  ///
  /// 桌面端（Windows/Linux）的 `ImageFilter.shader` 在 embedder 上行为不一致，
  /// web 没有 Impeller —— 这三处一律不挂，回落到纯模糊。
  static bool get isPlatformCapable {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// 把半径与折射带夹进距离场能接受的范围。**纯函数**，所以能在没有渲染后端
  /// （`flutter test` 的 Skia）的情况下被直接量。
  ///
  /// 两条夹取各有各的理由：
  /// 1. 半径不能超过短边的一半，否则距离场退化成胶囊、边缘那一圈会自相交；
  /// 2. 折射带比半径大没有意义（带内缘会跑出容器）。
  ///
  /// ⚠️ **第 2 条的上界必须先兜住**：写成 `band.clamp(1.0, r)` 时，`0 < r < 1`
  /// 会让下界大于上界，Dart 直接抛 `ArgumentError` —— 而这一行在 `filter` 里那个
  /// `try` **之前**，不会被「回落成 null」接住，而是每帧从 `GlassRefract.build`
  /// 抛出去、整页红屏。半径小于 1 不是理论情况：`LiquidTrack` 的半径取的是
  /// `capsuleH / 2`，谁给一条 2px 高的轨道（折叠动画的中间帧、横屏矮条）就命中。
  @visibleForTesting
  static ({double radius, double band}) sanitizeGeometry({
    required Size size,
    required double radius,
    required double band,
  }) {
    final double shortSide = size.width < size.height ? size.width : size.height;
    final double r = radius.clamp(0.0, shortSide / 2);
    final double b = r <= 1.0 ? 1.0 : band.clamp(1.0, r);
    return (radius: r, band: b);
  }

  /// 造一条「先模糊、再折射」的滤镜。
  ///
  /// [blur] 由调用点给（项目里是 [glassFilter]，还带饱和度），这里只是把它套在
  /// 折射**之前** —— 玻璃的读法是「模糊的、被弯过的背景」，顺序反了就成了
  /// 「弯过之后又被模糊」，边缘那道位移会被高斯抹平，等于白做。
  ///
  /// 尺寸一律传**逻辑像素**，内部按 [dpr] 换算成设备像素 —— `FlutterFragCoord()`
  /// 给的是设备像素。
  ///
  /// [origin] 是图层原点到容器左上角的偏移（逻辑像素）。容器正好铺满图层时传
  /// `Offset.zero`。**这一项是探针结果**：Impeller 给 backdrop 的坐标空间是图层局部，
  /// 不是屏幕根坐标，所以只要容器贴住图层左上角就不需要校正。
  ///
  /// ⚠️ **今天所有调用点都传 0**（`GlassRefract` 不传），也就是这条校正通路没有
  /// 任何用例或真机证据在守 —— 它留着是因为「万一某台机器的 backdrop 坐标不是图层
  /// 局部」时它是唯一的旋钮。真机验收时要验的正是这一点：胶囊后面放一张高对比棋盘，
  /// 看边缘那一圈采的是**胶囊外**的内容（正确），还是被 clamp 在容器边缘的糊带。
  ///
  /// 染色不在这一层做（`uTint` 从来没有过），颜色仍由 Dart 侧那层渐变叠上去。
  static ui.ImageFilter? filter({
    required Size size,
    required double dpr,
    required double radius,
    ui.ImageFilter? blur,
    double band = _bandLogic,
    double bend = _bendLogic,
    double spread = _spread,
    Offset origin = Offset.zero,
  }) {
    final ui.FragmentProgram? program = _program;
    if (program == null) return null;
    if (size.width <= 0 || size.height <= 0) return null;

    final ({double radius, double band}) geom =
        sanitizeGeometry(size: size, radius: radius, band: band);
    final double r = geom.radius;
    final double b = geom.band;

    final ui.FragmentShader shader = program.fragmentShader();
    shader
      // floats 0/1 是 `uSize`，**故意不设** —— `ImageFilter.shader` 的文档写明
      // 「The first uniform value must be a vec2, this will be set by the engine to
      // the size of the bound texture」，引擎会用输入快照的纹理尺寸覆写它。而这条
      // 链的输入是上游那层高斯模糊的输出，模糊按 `ceil(√3·σ)` 对称外扩（σ=24 时
      // 每边约 42dp），所以 `uSize` 比容器大一圈。这里设了也是空操作。
      //
      // 容器自己的尺寸走 floats 8/9（`uContainer`，引擎不碰），着色器拿两者之差
      // 反推外扩量，几何才算得对 —— 详见 `glass_refraction.frag` 顶部那段。
      ..setFloat(2, origin.dx * dpr)
      ..setFloat(3, origin.dy * dpr)
      ..setFloat(4, r * dpr)
      ..setFloat(5, b * dpr)
      ..setFloat(6, bend * dpr)
      ..setFloat(7, spread)
      ..setFloat(8, size.width * dpr)
      ..setFloat(9, size.height * dpr);

    final ui.ImageFilter refraction;
    try {
      refraction = ui.ImageFilter.shader(shader);
    } catch (e) {
      // **「程序就绪」不等于「这条链能用」**：`FragmentProgram` 在 Skia 上照样
      // 加载得出来（`flutter test` 里就加载成功了），而 `ImageFilter.shader`
      // 在 Skia 上直接抛 `UnsupportedError: only supported with Impeller`。
      //
      // 于是 `isPlatformCapable` 那道闸门是**必要但不充分**的：Android 上
      // Impeller 回落到 Skia 的机器（老设备 / Vulkan 不稳的机型 / 带
      // `--no-enable-impeller` 的构建）平台判据过得去、程序也加载成功，只有这一
      // 行会炸。若不在这里接住，`GlassRefract.build` 每帧抛一次 —— 底栏直接红屏，
      // 而且是在**部分机型**上，本地怎么跑都看不见。
      //
      // 失败**粘住**（与 `warmUp` 同一条纪律）：后端不会中途换，重试只会每帧白抛。
      _failed = true;
      _program = null;
      debugPrint('GlassRefraction: 当前渲染后端不支持 ImageFilter.shader，'
          '折射层关闭（回落为纯模糊）。$e');
      return null;
    }
    // 采样器（`uTex`）不在这里 set —— `ImageFilter.shader` 会把 shader 的第 0 个
    // sampler 自动绑到它的输入图像，手工再绑一次反而会盖掉引擎那份。
    return blur == null
        ? refraction
        : ui.ImageFilter.compose(outer: refraction, inner: blur);
  }

  /// 折射带宽度（逻辑像素）。底栏那枚胶囊 64 高，这一圈约占总高的三分之一 ——
  /// 再宽就会盖到图标下面，读起来像整块玻璃在抖。
  static const double _bandLogic = 20;

  /// 最大位移（逻辑像素）。超过约 12 就明显「糊成一团」，低于 4 又看不出弯。
  static const double _bendLogic = 8;

  /// 三波长偏移比例。iOS 26 的玻璃在边缘只有极窄的冷暖分离，不是彩虹环 ——
  /// 这个数刻意压在小数点后一位，配合项目里删掉的那圈静态光谱。
  static const double _spread = 0.055;

  /// 仅供测试断言用：把当前参数摊平成可比较的值。
  @visibleForTesting
  static List<double> debugParams() =>
      <double>[_bandLogic, _bendLogic, _spread];

  /// 仅供测试：清掉加载状态（`_failed` 会粘住，用例之间要能复位）。
  @visibleForTesting
  static void debugReset() {
    _program = null;
    _loading = false;
    _failed = false;
  }
}
