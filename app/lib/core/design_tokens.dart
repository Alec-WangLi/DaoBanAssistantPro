// app/lib/core/design_tokens.dart
import 'package:flutter/material.dart';

/// 设计令牌单一事实来源。所有组件的颜色/圆角/间距/动效/玻璃配方/排版一律引用这里，
/// 禁止在 feature 层内联 magic number。
class AppTokens {
  AppTokens._();

  // ── 颜色：中性背景 + 文字（明/暗各一套） ──
  static const Color bgLight = Color(0xFFF5F6FA);
  static const Color bgDark = Color(0xFF0B0B10);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF16161E);
  static const Color inkLight = Color(0xFF111118);
  static const Color inkDark = Color(0xFFF2F2F7);
  static const Color inkMutedLight = Color(0xFF6E6E82);
  static const Color inkMutedDark = Color(0xFF9A9AB0);

  // ── 语义色 ──
  static const Color danger = Color(0xFFE53935);
  static const Color success = Color(0xFF4ADE80);
  static const Color holiday = Color(0xFFE53935);

  // ── 圆角 ──
  static const double radiusS = 12;
  static const double radiusM = 16;
  static const double radiusL = 22;
  static const double radiusXL = 28;

  /// 胶囊圆角：高度的一半。用于导航胶囊、开关轨道、分段滑块，以及
  /// 信息卡左侧那根 6dp 色条这类「细长条」。
  static BorderRadius pillOf(double height) =>
      BorderRadius.all(Radius.circular(height / 2));

  // ── 间距：两套刻度 ──
  //
  // 「节奏」用于分隔两个**板块**：页面留白、区块间距、卡片内边距、列表行。
  // 4px 栅格。判据是「这个间距在分隔板块，还是在贴合一个控件内部的两个元素」。
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double space2xl = 24;
  static const double space3xl = 32;

  // 「光学」用于**一个控件内部**两个元素的贴合：图标与文字之间、小胶囊的
  // 上下内边距。硬套 4px 会让图标显得脱开、胶囊显得臃肿，所以单独留四档。
  static const double gapHair = 2;
  static const double padChipV = 3;
  static const double gapIconText = 6;
  static const double gapIconTextLg = 10;

  // ── 玻璃模糊 sigma ──
  static const double blurCard = 18;
  static const double blurPanel = 24;

  // ── 时长（非弹簧过渡） ──
  static const Duration durFast = Duration(milliseconds: 120);
  static const Duration durMed = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 340);

  /// 响铃界面的**入场动画**时长：一次性控制器（`alarm_ringing_screen.dart` 里
  /// `_enter.forward()`），驱动 FadeTransition / ScaleTransition 的淡入与放大。
  ///
  /// 注意它**不是**背景光晕的循环周期 —— 真正的光晕循环是
  /// `core/theme/animated_background.dart` 里另一个 26s 的 `repeat()`，
  /// 本轮未纳入令牌（范围外）。
  static const Duration durRingEnter = Duration(milliseconds: 650);

  // ── Q 弹弹簧 + 缩放 ──
  static const SpringDescription qSpring =
      SpringDescription(mass: 1, stiffness: 400, damping: 16);
  static const double pressScale = 0.96;
  static const double pillGrow = 1.06;

  /// 液态档透镜的弹簧：**三条分开**，因为它们各自要的手感不同。
  ///
  /// 提起与落下用的是 **Apple 自己的数字**（UIKitCore 逆向出来的：Lift ζ=0.625 /
  /// response 0.27s，Unlift ζ=0.7 / response 0.5s；`ω = 2π / response`）。
  /// **两条方向不同是有意的** —— 提起要跟手、落下要从容，苹果自己也是这么分的。
  /// 用户 2026-10-01 的原话是「点按吸附过去太快、不够优雅」，而在此之前我用的是
  /// 一条 ω=38（≈快一倍）的弹簧。
  ///
  /// 位置那条（点按换页时滑过去）取 ω=26 / ζ=0.68：落回约 200ms，是用户挑的档。
  ///
  /// ⚠️ **别拿连续解的理论公式去调**：按 16ms 一帧的半隐式欧拉跑出来阻尼比理论重
  /// 得多（照公式填的 ζ=0.72 过冲实测是 0.00%）。这几个数是在**与实现同一套离散
  /// 格式**上扫出来的，护栏在 `test/liquid_lens_test.dart`。
  static const double lensLiftOmega = 23.3; // 2π / 0.27s（Apple Lift）
  static const double lensLiftZeta = 0.625;
  static const double lensDropOmega = 12.6; // 2π / 0.50s（Apple Unlift）
  static const double lensDropZeta = 0.70;
  static const double lensSlideOmega = 26.0;
  static const double lensSlideZeta = 0.68;

  /// 形变强度那条弹簧。
  ///
  /// **形变不能直接用瞬时速度。** 瞬时速度是一根毛刺，直接拿它当形变，观感就是
  /// 「起步啪一下到满、停下啪一下归零」—— 机械感的全部来源。过一条弹簧，形变就有
  /// 惯性和回弹：起步时冲一点、停下时拖一条尾巴，那才读作「Q 弹」。
  ///
  /// ω=30 / ζ=0.62：过冲约 9.5%，包络衰减到 2% 约 210ms —— 尾够长但不拖沓。
  /// ζ 取 0.62 而不是临界阻尼 1.0，正是为了留下那点过冲。
  static const double lensStretchOmega = 30.0;
  static const double lensStretchZeta = 0.62;

  /// 图标的「被透镜边缘挤过去」有多少：横向压扁 / 纵向拉长各这么多（峰在边缘）。
  static const double lensIconPinch = 0.20;

  /// 图标被朝远离透镜中心的方向推多少（逻辑 px，峰在边缘）。
  static const double lensIconPush = 5.0;

  /// 边缘权重的高斯宽度（以「到透镜边缘的距离 ÷ 半宽」为单位）。
  ///
  /// **峰值在边缘、不在中心** —— 厚透镜中间是平的、只有边缘那圈曲率在折光，
  /// 所以图标躺在透镜正中时几乎不变形（用户 2026-10-01 指出的）。
  /// 0.45 让「有值」的范围落在 t ∈ [0.55, 1.45]，也就是透镜边缘那一圈。
  static const double lensIconRingSigma = 0.45;

  /// 光谱环的线宽（与压在它上面的白芯）。
  ///
  /// **4.5 → 2.4**（2026-10-01）：它原来是一条**等宽**的彩色描边，而用户的原话是
  /// 「现在给我的感觉就像在这个滑块的边缘加了一层彩带一样。我们想要的是加一层
  /// 折射的光晕」。等宽 + 硬边正是「彩带」读感的来源，所以这条收细、让位给
  /// 底下那两层光晕（见 [lensHaloWidth]）。
  static const double lensRingWidth = 2.4;
  static const double lensRingCoreWidth = 1.0;

  /// **折射光晕**：同一条扫掠渐变，画得又宽又糊。
  ///
  /// 这一层是消掉「彩带」读感的关键 —— 一条等宽、带硬边的彩色描边读作「贴在表面
  /// 的彩带」；**从边缘往里化开、没有硬边**的一层才读作「光在玻璃里」。
  ///
  /// 它挂在本体那层 `ClipPath` 底下（`LiquidLens` 的 `body`），所以外半边被裁掉，
  /// **只往轮廓里面散**；往外那一份由 [lensGlowWidth] 那层单独负责。
  ///
  /// 两层、色相各偏一点（−30° 与 +22°）：真色散会把光谱**摊开**，同一处边缘能
  /// 看到相邻的两个色调。一层的话仍然只是「一个颜色一个位置」。
  static const double lensHaloWidth = 10;
  static const double lensHaloBlur = 3;
  static const double lensHaloInnerWidth = 6;
  static const double lensHaloInnerBlur = 2;

  /// **外溢光晕**：画在裁剪**之外**那一层，往外也散一点。
  ///
  /// 本体画不到轮廓外面（那正是「只往内散」的实现方式），所以要单开一层 ——
  /// 与浮起阴影同一层位。用户 2026-10-01：「往外也散一点」。
  ///
  /// 代价是那枚水滴的轮廓会被一圈很淡的颜色裹住 —— 那是**有意**的，真的折射也会
  /// 在玻璃边外侧留下一条亮边。
  static const double lensGlowWidth = 8;
  static const double lensGlowBlur = 3;

  /// 彩边与光晕「**亮起来**」那条弹簧。
  ///
  /// 用户 2026-10-01：「彩边出现得太突然了。我的手不动它时没有，一动它就突然
  /// 出来了。能不能给它加个过渡动画，或者让它渐变出来？以及咱们手停下来的时候，
  /// 也得有点过渡，不要突然就没了。」
  ///
  /// 所以亮度也**不能直接跟瞬时速度走** —— 那是个「在不在动」的开关，一两帧就
  /// 跨过去了。过一条弹簧才有渐入渐出。
  ///
  /// **亮起与熄灭是两条**（和「提起 / 落下」同一条老规矩，Apple 也是这么分的）：
  ///   亮起 ω=26 / ζ=0.72 —— 上升约 90ms（跟手，不拖沓）；
  ///   熄灭 ω=12 / ζ=0.85 —— 包络 τ ≈ 100ms，约 320ms 淡尽（从容，不「啪」地断）。
  static const double lensLitOmega = 26.0;
  static const double lensLitZeta = 0.72;
  static const double lensUnlitOmega = 12.0;
  static const double lensUnlitZeta = 0.85;

  /// 光谱环「一动就满」的速度阈值（px/s）。
  ///
  /// 用户 2026-10-01：「彩色边缘不明显，还是恢复成一动就直接达到满效果吧。现在是
  /// 跟随速度越快效果才越明显，但这样几乎看不出来。本来它这个效果范围就不大。」
  ///
  /// 在此之前环的亮度是 `× clamp(|v| / lensVelocityRef)` —— 要甩到 700px/s 才满，
  /// 而常态拖动就在那个数上下，于是它长期停在半亮，等于一直是淡的。
  ///
  /// **这个数说的是「动不动」，不是「多快」**：60px/s（约合一格滑 1.5 秒）就封顶。
  /// 门因此从「速度表」换成了「开关」；留一小段斜坡只是不让慢速收尾时眨一下，
  /// 不是「越慢越淡」。
  static const double lensRingFullSpeed = 60;

  /// 弹簧一步积分允许的最大时间跨度。
  ///
  /// **它住在令牌表里不是因为它是个「时长」** —— 它是数值积分的步长上限，
  /// 与 durFast / durMed 那种过渡时长毫无关系。搬进来的唯一理由是
  /// `design_tokens_test` 会扫 `lib/core/glass/`，而它扫的是**写法**
  /// （`Duration(milliseconds: …)`），不是语义。
  ///
  /// **16ms** —— 也就是「一步最多积分一帧」。
  ///
  /// ⚠️ **别按「半隐式欧拉的失稳门槛」去定它。** 那个门槛（`dt > 2 / ω`，ω = 38
  /// 时是 53ms）只是**临界**，实际可用的步长要严得多。第一版按它取了 48ms，结果
  /// 在 40ms 一帧的测试里**弹簧直接发散**：实测速度冲到 2528 格/s（≈ 22.7 万 px/s），
  /// 透镜被甩到屏幕外几千像素去。生产上 60Hz 是 16.7ms，而**掉帧时 40ms 就会炸** ——
  /// 那正是这个封顶存在的理由。
  ///
  /// 取 16ms 之后：满载掉帧时动画走得慢一点（那正是想要的），120Hz 下完全不受影响。
  static const Duration lensMaxStep = Duration(milliseconds: 16);

  /// 透镜按住时比静止宽多少（逻辑 px）。
  ///
  /// 与 [navLensProtrude]（10，纵向）**同量级是有意的**：透镜是一枚「鼓起来的
  /// 水滴」，不是一张「被拉长成条」的贴纸 —— 纵横两个方向一起长，才读得出体积。
  static const double lensLiftWidth = 10;

  /// 拖动时形状拉伸的**归一化速度**（px/s）。
  ///
  /// 速度到这个值时拉伸达到满档（宽 +[lensStretch]、高 −[lensSquash]）；再快也不更多
  /// —— 甩得越猛形状越夸张并不是更真，只是更闹。
  ///
  /// **1500 → 700 → 900**（2026-10-01）。中间那一次 700 其实**从来没生效过**：
  /// `_onTick` 里那个 `max(dt, 16ms)` 的地板在 120Hz 上把速度算成了真实值的一半，
  /// 于是 700 在这台机器上表现为 1400。地板撤掉之后 700 才会真正落到手上，
  /// 那比用户见过的任何一版都强一倍，所以取 900 —— 约合「一格在 100ms 内划过」，
  /// 常态拖动就到得了。**这是这一版唯一一个凭手感定的数**，一改就见效。
  static const double lensVelocityRef = 900;

  /// 形变：沿运动方向拉长多少、垂直方向压扁多少（比例）。
  ///
  /// 压扁这一档 **0.12 → 0.08**（2026-10-01），因为原来的乘法顺序有个几何缺陷：
  /// 凸出被乘在压扁里面，于是速度一上来透镜就沉回胶囊（见 [navLensProtrude]）。
  /// 顺序修好之后 0.12 仍然会在满速时把凸出吃到只剩 0.88px，所以一并收小。
  static const double lensStretch = 0.20;
  static const double lensSquash = 0.08;

  /// 按住多久才算「提起」。
  ///
  /// 这一条是**交互契约的闸门**（用户 2026-10-01）：「点一下滑块自动过来、然后切页；
  /// 长按滑块自动吸附、松手才切到它最终所在的区域」。110ms 落在一次干脆的点按
  /// （约 60–90ms）与一次有意的按住之间 —— 短于它，透镜只是**滑过去**、不提起；
  /// 长于它，才吸附到手上、放大、凸出胶囊。
  ///
  /// **「凸出胶囊」因此是「按住」的专属信号** —— 这正是用户那句「应该是按住的
  /// 时候，它比胶囊大」的可执行形式。
  static const Duration lensHoldDelay = Duration(milliseconds: 110);

  // ── 排版：角色令牌 ──
  //
  // 令牌即完整样式（字号 + 字重 + 行高）。界面层只写角色名，不写 fontSize /
  // fontWeight；颜色由调用处 `copyWith(color:)` 覆盖 —— 同一个角色在不同底色上
  // （尤其班次色块）要取不同的可读色，所以颜色不进令牌。
  //
  // 名字说的是「什么时候用它」，不是「它多大」。这也是为什么不再按
  // fontLead / fontBody 那样按尺寸命名：按尺寸命名会让人挑「最像的那个大小」，
  // 12.5 / 13.5 / 14.5 / 15 / 22 就是这么来的。
  //
  // 一个角色内的个别变化走 `copyWith`，不另立令牌（格子里的「今天」加粗、
  // 选择器选中项加粗、导航标签选中态、调休日「班」标记转主色）。
  static const TextStyle ringClock =
      TextStyle(fontSize: 84, fontWeight: FontWeight.w800, height: 1.0);
  static const TextStyle pageTitle =
      TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
  static const TextStyle bigNumber =
      TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
  static const TextStyle dialogTitle =
      TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
  static const TextStyle sectionTitle =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
  static const TextStyle cellDate =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.15);

  /// 日历格子上「有班次」那套排布用的日期字号。
  ///
  /// 有班次时日期不再是格子里的主角 —— 班次胶囊才是，所以日期降成左上角的
  /// 定位标记，比无班次排布里的 [cellDate] 小一档。字号差别也是这排布的
  /// 一部分：日期一缩小、胶囊一放大，「这格是什么班」一眼就出来了。
  static const TextStyle cellDateSm =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.15);

  /// 日历格子里班次胶囊的文字。整格内容会按格子高度等比缩放，这是基准值。
  ///
  /// 用 w700 而不是更重的字重：设计规格把 w800 留给响铃大时钟与「今天」徽章，
  /// 胶囊靠**字号 + 底色**取得分量，不靠再压一档字重。
  ///
  /// 13 是 v0.7.2 从 15 调下来的；12 是 v0.7.3 再收一档 —— 两个字时胶囊仍会
  /// 顶到格子邊（左右只剩 1.5px），连滑块一起看很挤。
  static const TextStyle cellShift =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.15);

  static const TextStyle titleStrong =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  static const TextStyle labelStrong =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  static const TextStyle rowPrimary =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const TextStyle rowSecondary =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const TextStyle labelSecondary =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const TextStyle microStrong =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.15);
  static const TextStyle microLabel =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const TextStyle microText =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const TextStyle tinyLabel =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.15);

  /// 按比例放大/缩小一个角色令牌，其余属性（字重、行高）原样保留。
  ///
  /// 给**日历格子**用：格子的高度是按剩余空间算出来的，同一台设备上会随月份
  /// 行数、信息卡高度浮动，而字号是写死的 —— 格子长高、字不跟着长，格子里就
  /// 空出一大块，字看着就小。所以格子里的字要按格子尺寸等比缩放。
  ///
  /// 缩放系数由调用方按格子高度算好并夹住上下限，这里只做派生。字号走
  /// `t.fontSize! * s` 而不是字面量，是守门测试要求的（`fontSize:` 后跟数字
  /// 直接报红，见 `design_tokens_test.dart`）。
  static TextStyle scaled(TextStyle t, double s) =>
      t.copyWith(fontSize: t.fontSize! * s);

  // ── 图标尺寸：三档 ──
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;

  /// 强调色渐变（按钮/导航选中/填充条用）：顶 0.85 → 底 0.50。
  static LinearGradient accentGradient(Color accent) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.85),
          accent.withValues(alpha: 0.50),
        ],
      );

  // ── 真实饱和度：玻璃后面那层背景的处理 ──
  /// Rec.709 保亮度饱和度矩阵，s = 1.2。中性灰保持不动（三行各自加和为 1）。
  ///
  /// 玻璃**被看穿的背景**不只是变糊，还更浓、更艳 —— 这是真实液态玻璃最可辨识的
  /// 特征之一（除折射外）。以前这条是用 [glassTint] / [glassSurface] 那层白渐变
  /// **近似**的（见 `glass.dart` 的效果构成注释），现在是真的。
  ///
  /// ⚠️ **别去动 [glassTint] / [glassSurface] 的 alpha。** 一度以为「白渐变会把饱和度
  /// 抵消掉、该把 `blurOn` 那一支的 alpha 收一收」，实测**否掉了**：真正的限制因素是
  /// 背景本身近中性（本 App 的底色是刻意的极简黑白），把白收掉救不回来 ——
  /// 连 s=3.0 的对照实验也只有 6/255。而且那两个函数里 `blurOn == false` 那一支
  /// 是**省电档的观感**，动它会破坏「低内存机器行为一字不变」。
  ///
  /// 走 SDK 的 [ColorFilter.saturation] 而不是手抄那 20 个数：它的算式
  /// （`invSat * luminance + saturation`）与手抄那份**逐位相同**，但不会抄错。
  /// 不是 `const`（那是个 factory），所以只能是 `static final`。
  static final ColorFilter glassSaturation = ColorFilter.saturation(1.2);

  // ── 玻璃配方（统一，两档：glassTint 胶囊/按钮、glassSurface 卡片/面板） ──
  // 顶层 alpha 更高；blurOn=false（低端机/关高级材质）时整体更实。
  static List<Color> glassTint(bool isDark, bool blurOn) => isDark
      ? [
          Colors.white.withValues(alpha: blurOn ? 0.16 : 0.22),
          Colors.white.withValues(alpha: blurOn ? 0.07 : 0.12),
        ]
      : [
          Colors.white.withValues(alpha: blurOn ? 0.80 : 0.90),
          Colors.white.withValues(alpha: blurOn ? 0.45 : 0.72),
        ];

  static List<Color> glassSurface(bool isDark, bool blurOn) => isDark
      ? [
          Colors.white.withValues(alpha: blurOn ? 0.11 : 0.16),
          Colors.white.withValues(alpha: blurOn ? 0.04 : 0.08),
        ]
      : [
          Colors.white.withValues(alpha: blurOn ? 0.70 : 0.82),
          Colors.white.withValues(alpha: blurOn ? 0.34 : 0.60),
        ];

  static Color glassBorder(bool isDark) =>
      Colors.white.withValues(alpha: isDark ? 0.16 : 0.90);

  /// **探针专用**：方向性边缘光的配色（顶部高光 → 底部收边）。
  ///
  /// 与 `CapsuleRimPainter` 配套，**不是产品代码**。
  ///
  /// 深浅两档**有意不同配方**，这是第一轮探针量出来的：
  /// 深色下背景暗，白色一端看得见 → 一圈「被点亮的玻璃边」，成立；
  /// 浅色下背景近白，**白的看不见、只有更暗的才看得见** —— 而更暗的用多了就变成
  /// 「一个灰框」（第一轮就是这么变差的）。所以浅色这一档只在底部轻收。
  ///
  /// ⚠️ **这两套配色的方向从 2026-10-01 起是「竖直」的，调用点必须配
  /// `Alignment.topCenter → bottomCenter`**（原来是 `topLeft → bottomRight`）。
  /// 对角线那版在**近方形的卡片**上读作「左上高光 + 右下收边」—— 它本来就是照卡片
  /// 量的；但底栏胶囊是 372×64（约 6:1），渐变轴几乎就是水平的，于是退化成
  /// **左端纯白、右端 10% 黑**。用户 2026-10-01 报的「浅色下胶囊左边很浅、几乎看
  /// 不清胶囊，右边有镜片效果」就是它：实测左缘 `rgb(251,250,251)`、右缘
  /// `rgb(203,199,204)`。左边那圈 **α=1.0 的纯白**既压在近白的底上看不见，
  /// 又把胶囊自己那条 14% 的深色轮廓线（[navBorder]）整个盖掉。
  ///
  /// 改成竖直之后 t 只跟 **y** 有关 → **左右结构性地完全一致**，且与宽高比无关
  /// （不是给 6:1 打补丁，是换掉那个依赖宽高比的模型）。浅色的白色峰值同时
  /// 从 1.0 压到 0.48：它不再盖掉轮廓线，左端轮廓因此回来。
  ///
  /// 不再掺主色：第一轮实测主色着色会把卡片洗成一块平色板，且 HIG 明确说
  /// 「实心填充会破坏液态玻璃的性格」。
  static List<Color> glassRimProbe(bool isDark) => isDark
      ? <Color>[
          Colors.white.withValues(alpha: 0.62),
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.02),
        ]
      : <Color>[
          // 0.48 是「还读得出是一道高光」与「不把底下那条 14% 的轮廓线抹掉」的
          // 交点：0.48 白压在 14% 深的边上剩下约 `rgb(234)`，比底色（254）仍低 20 级，
          // 轮廓看得见；而原来是 1.0，压上去正好等于底色 255 —— 整条边消失。
          Colors.white.withValues(alpha: 0.48),
          // 中段**透明**：这一段让轮廓线原样透出，于是左右两个端头的中点
          // （t = 0.5，正落在这一段里）读到的值完全相同。
          Colors.white.withValues(alpha: 0.0),
          // 底部那条暗线给出「厚度」，接替原来靠右侧黑线提供的镜片读感。
          Colors.black.withValues(alpha: 0.12),
        ];

  /// 探针：边缘光的宽度。
  ///
  /// 深色那档稍宽（暗底上要看得出）。**底栏胶囊走 [compact]**：同一个宽度在小控件上
  /// 相对更显眼，第二轮出图时它那一圈明显比别处重，所以单独收窄。
  static double glassRimProbeWidth(bool isDark, {bool compact = false}) {
    if (compact) return isDark ? 1.1 : 0.9;
    return isDark ? 1.6 : 1.2;
  }

  /// 探针：凸出的透镜探出胶囊多少（逻辑 px）。
  ///
  /// 滑块原来只有 `capsuleH - 2 * _innerPad`（64 − 12 = 52）高，整个躺在胶囊里 ——
  /// 它的边是**玻璃对玻璃**，而折射只发生在「玻璃 ↔ 背景」的边界上（Apple 那条
  /// 「玻璃不能采样玻璃」说的就是这件事）。凸出来才有那条边界。
  /// 10 让透镜高 72（胶囊 64），上下各探出 4。
  ///
  /// ⚠️ **它必须加在「压扁之后」的基准上，不许乘进形变里**（2026-10-01）。
  /// 原式是 `(基准 + 2·凸出·lift) × (1 − 0.12·s)`：压扁乘在凸出上，于是
  /// lift=1 / 700px/s 时透镜高只有 63.4，而胶囊高 64 —— **透镜整个沉回胶囊里面**，
  /// 按住拖动时「一枚浮起来的玻璃滴」直接掉回「一枚躺着药丸」。
  /// 实测扫出来的（见 `test/liquid_lens_test.dart` 的折边参数扫描）。
  static const double navLensProtrude = 10;

  /// 透镜外扩 / 凸出相对胶囊高度的比例（10 ÷ 64）。
  ///
  /// **只有 `LiquidLensMetrics.forCapsule` 用它。** 底栏那两个数（`navLensProtrude` /
  /// `lensLiftWidth`）是**冻住的** —— 矮屏那一档胶囊只有 52 高，跟着比例取会变成 8.1，
  /// 横屏与小窗两档的画面就变了，而「底栏逐像素不变」是抽共享件这一路的验收。
  static const double lensLiftRatio = 0.15625;

  /// 「胶囊那条边被折进去」淡入所需的凸出量（逻辑 px）。
  ///
  /// 这条折线的早退条件原来写的是「**两个端头半径都**大于胶囊半高」，而速度一上来
  /// 后缘半径（`×(1 − 0.35·stretch)`）必然先掉下去 —— 于是**整条折边被一票否决**。
  /// 实测：lift=1 时只要超过约 150px/s 它就完全消失，而常态拖动是 300~1000px/s。
  /// 也就是说这个效果**只在「按住而且手指不动」时存在**，恰好是唯一不会去拖的状态。
  ///
  /// 现在门开在「至少一端够到」，并且**按凸出量连续淡入**：凸出 0 → 3px 走 0 → 满。
  /// 于是它既不会在高速下开天窗，也不会「啪」地出现或消失。
  static const double lensEdgeFade = 3;

  /// 探针：**滑块附近那一段边缘光**的配色（滑块滑过时玻璃边被点亮）。
  ///
  /// 这不是折射 —— 折射是逐像素扭曲背景，需要 shader，且在平背景上看不见。
  /// 这是「光的响应」：光源（滑块）靠近玻璃边时，那边的边亮起来。平背景上能被
  /// 看见的只有这一类。
  static Color glassRimProbeGlow(bool isDark) =>
      Colors.white.withValues(alpha: isDark ? 0.95 : 0.85);

  static List<Color> glassHighlight(bool isDark) => [
        Colors.white.withValues(alpha: isDark ? 0.18 : 0.55),
        Colors.white.withValues(alpha: 0.0),
      ];

  static double glassHighlightStop(bool isDark) => isDark ? 0.28 : 0.30;

  static BoxShadow glassShadow(bool isDark) => BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
        blurRadius: 28,
        offset: const Offset(0, 10),
      );

  // ── 底部悬浮导航胶囊（半透明磨砂玻璃：真实模糊 + 通透白 tint，内容滑过若隐若现） ──
  static List<Color> navFill(bool isDark) => isDark
      ? [
          Colors.white.withValues(alpha: 0.09),
          Colors.white.withValues(alpha: 0.035),
        ]
      : [
          Colors.white.withValues(alpha: 0.56),
          Colors.white.withValues(alpha: 0.24),
        ];

  /// 胶囊描边：亮色转深色细线勾勒轮廓（白底上白描边会隐身），暗色保持白描边。
  static Color navBorder(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.16)
      : inkLight.withValues(alpha: 0.14);

  /// 胶囊滑块选中项前景（图标/文字）：浅色模式滑块被白底冲淡，恒用深字；
  /// 暗色模式按明度选黑/白——当前 5 个主题色均低于 0.45 阈值，走白字。
  static Color navForeground(bool isDark, Color accent) {
    if (!isDark) return inkLight;
    return accent.computeLuminance() > 0.45 ? inkLight : inkDark;
  }

  /// 导航胶囊上**未选中**项的前景（图标与文字）。
  ///
  /// 与 [navForeground] 同一族的「前景色已定」情形：胶囊是磨砂玻璃、压在任意
  /// 内容之上，对比度要求与页面正文不同，所以不并入 inkMuted / inkFaint 那两档
  /// （规格 §3.3 已为这类情形留了口子）。暗色下底更透，故取值比亮色更实。
  static Color navInactiveForeground(BuildContext context,
          {required bool isDark}) =>
      Theme.of(context)
          .colorScheme
          .onSurface
          .withValues(alpha: isDark ? 0.72 : 0.55);

  // ── 文字明度：两档 ──
  //
  // 「层级只靠字号、字重、明度」里的明度就是这一层。此前它没有令牌，于是
  // 次要文字散着 0.45 / 0.5 / 0.55 / 0.6 四种 alpha —— 同一个角色被调了不同值。
  // 压在主色胶囊上的次要白字不归这两档（那是「前景色已定」的情形）。

  /// 次要文字的透明度。0.62 在浅色底上过 WCAG AA 4.5:1 —— 页面底 `#F5F6FA`
  ///（最坏浅底）**4.70:1**，卡片 `#FFFFFF` 4.83:1，连最悲观的略暗玻璃卡
  /// `#EEF0F4` 也有 4.59:1。0.55 与 0.60 都不够（最坏 3.72:1 / 4.33:1），
  /// 所以本轮从 0.55 一路提到 0.62。暗色底上 0.55 起就已过。
  ///
  /// 数字按主题**真实的** `onSurface` 算：浅色走 `ColorScheme.fromSeed` 得到
  /// **`#1A1B20`**（不是 `inkLight` `#111118`）。早前照 `#111118` 估的
  /// 「0.55=4.06 / 0.60=4.78」对本 App 不成立 —— onSurface 更亮，整条曲线下移。
  static const double inkMutedAlpha = 0.62;

  /// 更淡那档的透明度。用于**禁用态 / 占位 / 待办已完成** —— 低对比正是它的
  /// 用途（已完成的删除线承载语义），因此**有意低于 AA**（0.35 → 页面底 2.16:1），
  /// 是明确豁免而不是漏网。
  static const double inkFaintAlpha = 0.35;

  static Color inkMuted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface
          .withValues(alpha: inkMutedAlpha);

  static Color inkFaint(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface
          .withValues(alpha: inkFaintAlpha);

  // ── 文字可读性 ──

  /// WCAG 对比度（1:1 ~ 21:1）。要求两个颜色都是不透明的，才等于屏幕上的观感。
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 把「班次色」调成当**文字**用可读的版本：只动明度，不动色相。
  ///
  /// 班次色是给色块和圆点用的强色，直接拿来当小号文字色会明显不够看——
  /// 模板里的橙 `#FF9F0A` 压在白底上只有 2.06:1、灰 `#9AA0B4` 只有 2.60:1，
  /// 12px 的字基本读不出来（WCAG AA 对普通文字要求 4.5:1）。这两个颜色
  /// 在日历格子里就是「中」「休」两个字，等于每天都少看一档信息。
  ///
  /// 做法：在浅色底上朝黑压、在深色底上朝白提，够到 [target] 就停。所以压在
  /// 底上的字读得清，同时因为色相没动，还认得出是哪个班次。
  static Color inkFor(Color color, Color background, {double target = 4.5}) {
    // 每个格子每次 build 都算一遍的话，一屏 42 格 × 十几轮 pow 是白白烧 CPU
    // （拖动时每帧都要重算），班次色又是有限的几种，缓存掉。
    return _inkCache.putIfAbsent(
      Object.hash(color.toARGB32(), background.toARGB32(), target),
      () => _computeInk(color, background, target),
    );
  }

  static final Map<int, Color> _inkCache = {};

  static Color _computeInk(Color color, Color background, double target) {
    if (contrastRatio(color, background) >= target) return color;
    final toward =
        background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    // 一档 4%，最多到 72%：再深就基本等于纯黑/纯白，色相也留不住了。
    for (var t = 0.08; t < 0.72; t += 0.04) {
      final candidate = Color.lerp(color, toward, t)!;
      if (contrastRatio(candidate, background) >= target) return candidate;
    }
    return Color.lerp(color, toward, 0.72)!;
  }

  /// 实心色块上的可读文字色：白或黑，取对比度更高的一侧。
  ///
  /// 恒有 max(白, 黑) ≥ 4.58:1 —— 两条曲线在亮度 0.179 处交叉，交叉点上
  /// 各是 4.58。所以这个二选一对**任何**底色都能过 WCAG AA，不需要像
  /// [inkFor] 那样逐档逼近。
  ///
  /// 不能拿 [inkFor] 代劳：那个是「把一个前景色调到在给定背景上可读」，
  /// 朝黑还是朝白由**背景**明暗决定；这里是「底色已定，白黑二选一」，
  /// 方向必须由底色与黑白两色的对比度决定。拿 `inkFor(白, 橙)` 会得到
  /// 白色本身（它朝白逼近），而橙底白字只有 2.23:1。
  static Color onSolid(Color background) =>
      contrastRatio(Colors.white, background) >=
              contrastRatio(Colors.black, background)
          ? Colors.white
          : Colors.black;
}