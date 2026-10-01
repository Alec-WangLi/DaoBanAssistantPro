import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../design_tokens.dart';
import 'liquid_lens.dart';

/// 一枚**会提起、会滑动、会形变、会亮起来**的玻璃滴的动画状态机。
///
/// 从底栏（`features/home/glass_nav_bar.dart`）里原样抽出来的：那一段是六轮真机反馈
/// 沉淀下来的，**数值与算式一个都没改**。抽出来的理由只有一个 —— 手感必须只有一处
/// 实现。抄三份的话下次调参要改三处，而三处一定会走样。
///
/// ## 四个量必须分家
///
/// 这是整个档位最容易抄错的地方：**喂同一个量给两处，就只能二选一**，而用户三轮
/// 反馈说的正是这四件事。
///
/// | 量 | 跟什么走 | 表现 |
/// |---|---|---|
/// | [stretch] | **速度**（经形变弹簧） | 拖动时头大尾小 |
/// | [motion] | **有没有在动**（经亮度弹簧） | 彩边 / 光晕的亮度，一动就满、且渐入渐出 |
/// | [lift] | **有没有按住** | 凸出容器、放大、跟不跟手 |
/// | [velocity] | 位置的真实帧间差分 | 上面两条的**输入**，帧率无关 |
///
/// ## 它不做的事
///
/// - **不读档位**（`liquidGlassActive`）—— 判据只在调用点，与本仓既有纪律一致；
/// - **不知道「格子里有什么」** —— 抽屉、图标、文字都归调用点；
/// - **不管页面** —— 翻页由调用点自己拿着 `PageController` 做，这里只管那枚滴。
class LiquidLensController extends ChangeNotifier {
  LiquidLensController({
    required this.slots,
    required this.pad,
    required this.liftWidth,
    required TickerProvider vsync,
    int initialSlot = 0,
    this.followFinger = true,
    this.velocityRef = AppTokens.lensVelocityRef,
  }) {
    _page = initialSlot.toDouble();
    _slotCentre = initialSlot + 0.5;
    _pos = LiquidLensSpring(target: _slotCentre, value: _slotCentre);
    _lastCentre = _slotCentre;
    _ticker = vsync.createTicker(_onTick);
  }

  /// 格数。
  final int slots;

  /// 容器内边距（夹紧用）。
  final double pad;

  /// `LiquidLensMetrics.liftWidth`（夹紧用）：满升程时横向总共外扩多少，
  /// **可以为负**。
  final double liftWidth;

  /// 提起之后**要不要朝手指走**。
  ///
  /// 底栏与分段器是「按住吸附到手上」，要（默认 true）。**开关不要** —— 它不可拖，
  /// 交互只是「点哪儿都拨一下」；跟着手走的症状是在开着的那枚开关左半边按住，
  /// 钮会自己飞到左边去（与「开关的钮不该跑到手指下」是同一件事的两半）。
  final bool followFinger;

  /// 形变饱和的速度门（px/s）。默认取全局那一档，**底栏与分段器一个字都不改**；
  /// 开关一格只有 25px，传一个更低的值才积得起形变（见 `LiquidLensMetrics.velocityRef`）。
  final double velocityRef;

  // ── 弹簧 ────────────────────────────────────────────────────────────────
  /// 「该停在哪一格的中间」。点按 / 松手 / 外部切页都会改写它，`_onTick` 用它作为
  /// 位置弹簧的目标（再按升程掺进手指的位置）。
  ///
  /// ⚠️ **不能拿 `_pos.target` 当它用** —— 那样每帧都会「目标往手指挪一点」，自我
  /// 漂移，透镜会慢慢爬到手指上再也不回来。
  late double _slotCentre;

  /// 逻辑页（**左缘**，单位「格」，可为小数）：点按落下时是那一整格，拖动中是连续的
  /// 手指位置。**它不由弹簧驱动** —— 弹簧是「画面上的位置」，这个是「该去哪一格」。
  ///
  /// ⚠️ 少了它，[release] 就只能拿弹簧的**当前位置**去算目标格：点一下之后 48ms 弹簧
  /// 才走到一半，松手时就会被吸附到**中间那一格**（实测正是指哪一格都不对）。
  late double _page;

  late final LiquidLensSpring _pos;
  late final LiquidLensSpring _lift = LiquidLensSpring(target: 0);
  late final LiquidLensSpring _stretch = LiquidLensSpring(
    target: 0,
    omega: AppTokens.lensStretchOmega,
    zeta: AppTokens.lensStretchZeta,
  );
  late final LiquidLensSpring _lit = LiquidLensSpring(
    target: 0,
    omega: AppTokens.lensLitOmega,
    zeta: AppTokens.lensLitZeta,
  );

  late final Ticker _ticker;
  Duration? _lastTick;

  bool _pressed = false;
  bool _dragging = false;
  bool _heldLongEnough = false;
  Timer? _holdTimer;
  int? _previewIndex;

  /// 手指在**内层坐标**里的 x，以及拖动起点的抓取偏移（跟手不跳的关键）。
  double _fingerInnerX = 0;
  double _grabOffset = 0;

  /// 每一格多宽（px）。形变要的速度是 px/s，而弹簧的位置以「格」为单位。
  double _itemW = 1;

  /// 上一帧的透镜中心（格），用来算真实速度。
  double _lastCentre = 0.5;

  /// 带低通的速度（px/s）—— 原始帧间差分抖得厉害。
  double _velocityPx = 0;

  // ── 读数 ────────────────────────────────────────────────────────────────

  /// 升程 0..1：凸出容器、放大、跟不跟手，三件事共用它。
  double get lift => _lift.value.clamp(0.0, 1.0);

  /// 透镜**中心**的位置，单位是「格」（静止时 = 格号 + 0.5）。
  ///
  /// ⚠️ **是中心，不是左缘。** 调用点如果拿它当左缘用，会差半个格。
  double get position => _pos.value;

  /// 形变强度 0..1（长边拉伸、短边压扁）。走的是**弹簧**，不是瞬时速度。
  double get stretch => _stretch.value;

  /// 彩边 / 光晕的亮度 0..1。走的是**亮度弹簧**（亮起 / 熄灭两条）。
  double get motion => _lit.value.clamp(0.0, 1.0);

  /// 速度（px/s，带符号）。它只是 [stretch] 与 [motion] 的**输入**，不直接拿去画。
  double get velocity => _velocityPx;

  bool get pressed => _pressed;
  bool get dragging => _dragging;

  /// 按下 / 拖动中预览的功能区（松手才提交）。没在按就是 null。
  int? get previewIndex => _previewIndex;

  /// 逻辑页（左缘，单位「格」）。标准档那棵树用它定位高亮块。
  double get page => _page;

  /// 调用点在布局时告诉它每格多宽。
  void setItemW(double itemW) {
    if (itemW > 0) _itemW = itemW;
  }

  /// 外部程序化切页（例如点通知跳页）时，把中心挪到那一格，并把 ticker 拉起来。
  void snapTo(double slotCentre) {
    _page = slotCentre - 0.5;
    _slotCentre = slotCentre;
    _pos.target = _clampCentre(slotCentre);
    _syncTicker();
    notifyListeners();
  }

  // ── 手势 ────────────────────────────────────────────────────────────────

  /// 点按落下：吸附到手指所在的那一整格，**不提起**。
  ///
  /// [moveToSlot] 为 `false` 时**不挪**，只进入按住态。开关用它 —— **开关的钮不该
  /// 跑到手指按下的那一格去**（那是分段器 / 底栏的语义：点哪一格就去哪一格）；
  /// 开关的交互是「点哪儿都只是拨一下」，钮只该在**值变了**之后才滑过去。
  /// 少了这个参数，在开着的那枚开关左半边按住，钮会先跳到左边再跳回来。
  void press(double localDx, {bool moveToSlot = true}) {
    final int i = _indexFor(localDx);
    _fingerInnerX = localDx;
    _armHoldTimer();
    _pressed = true;
    _previewIndex = i;
    if (moveToSlot) {
      _page = i.toDouble();
      _slotCentre = i + 0.5;
      _pos.target = _slotCentre;
    }
    _syncTicker();
    notifyListeners();
  }

  void dragStart(double localDx) {
    _grabOffset = localDx / _itemW - _page;
    dragUpdate(localDx);
  }

  /// 拖动中：**1:1 跟手**。弹簧不插一脚 —— 让它插就会拖出一条橡皮筋尾巴，
  /// 而「跟手」正是要的那种「吸附在手上」。
  void dragUpdate(double localDx) {
    final double p = _clampPage(localDx / _itemW - _grabOffset);
    _fingerInnerX = localDx;
    _pressed = true;
    _dragging = true;
    _previewIndex = _nearestIndex(p);
    _page = p;
    _pos.value = _clampCentre(p + 0.5);
    _syncTicker();
    notifyListeners();
  }

  /// 松手：吸附到最近一格。**返回落到了哪一格** —— 调用点要用它去翻页
  /// （页面归调用点管，这里只管那枚滴）。
  int release() {
    _endHold();
    // 目标格取**逻辑页**，不是弹簧的当前位置 —— 见 `_page` 的说明。
    final int target = _nearestIndex(_page);
    // **逻辑页也要吸附过来。** 少了这一行，「拖了一点点、又松在同一格上」时
    // `onSelected` 不触发、也没别的东西去纠正它 —— **标准档那块高亮会永远停在
    // 差一点的位置上**（独立审查抓出来的 Critical；抽共享件之前两处都是自己吸附的：
    // 底栏 `_visualPage = target`、分段器 `_visual = target`）。
    _page = target.toDouble();
    _slotCentre = target + 0.5;
    _pos.target = _slotCentre;
    _syncTicker();
    _pressed = false;
    _dragging = false;
    _previewIndex = null;
    notifyListeners();
    return target;
  }

  /// 取消：只有**真正在拖**才回退（点按结束触发的 cancel 不回退）。
  ///
  /// **返回「是否真的取消了」** —— 回退到哪一格是调用点的事（它才知道「已经提交的
  /// 那一格」是哪一格），所以真正取消时调用点要自己再 `snapTo(committed + 0.5)`。
  bool cancel() {
    if (!_dragging) return false;
    _endHold();
    _pressed = false;
    _dragging = false;
    _previewIndex = null;
    _syncTicker();
    notifyListeners();
    return true;
  }

  /// 点按被取消（在容器上按下之后竖直滑走之类）→ **当作没点过**。
  ///
  /// **返回「是否真的取消掉了什么」** —— 调用点据此把位置交还给「已提交的那一格」
  /// （只有调用点知道那是哪一格）。这条不能省：`press(moveToSlot: true)` 已经把滴
  /// 滑到手指那一格了，不回退的话它会留在那儿，而页面并没有切 —— 那正是用户
  /// 2026-10-01 说的「滑块定格」（「需要再次点击一下滑块，才会恢复正常」）。
  ///
  /// 不能复用 [cancel]：那个有个「没在拖就早退」的闸门（它是给「拖动取消」用的）。
  ///
  /// **这是一个既有缺陷的修复**：`onTapCancel` 原来是个空回调，`_pressed` 会永远卡在
  /// true —— 标准档下只是容器一直大 6%，液态档下就是透镜永远提着。
  bool tapCancel() {
    final bool wasActive = _pressed || _dragging;
    _endHold();
    if (!_dragging) {
      _pressed = false;
      // ⚠️ **preview 也要清。** 不清的话分段器的内容高亮会停在手指按下那一格
      // （`selectedIdx = previewIndex ?? committed`），而选中项根本没有变。
      _previewIndex = null;
      notifyListeners();
    } else {
      cancel();
    }
    _syncTicker();
    return wasActive;
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  double get _liftTarget => (_dragging || _heldLongEnough) ? 1.0 : 0.0;

  /// 按**当前意图**刷新升程弹簧的目标。
  ///
  /// ⚠️ **`_lift.target` 不许只在 `_onTick` 里写。** [_syncTicker] 要用
  /// `_lift.isAtRest` 判「还要不要推帧」，而那个判据比的是 `value` 与 `target` ——
  /// 意图在两次 tick 之间翻掉时（[tapCancel] / [release] / [cancel] 都会），
  /// `target` 还是旧的「1」，于是 `value == target` 成立、被判成静止、
  /// **ticker 被停掉**，[_onTick] 再也不跑、`target` 也就永远停在 1：
  /// **升程冻死在满档**。用户 2026-10-01 报的正是它 ——「长按这些滑块，手指快速
  /// 上下滑动页面时，滑块会定格在放大的那个瞬间，需要再次点击一下滑块，才会恢复
  /// 正常」（再点一下会好，是因为 `press()` 把 `_pressed` 翻回 true、ticker 被重新
  /// 拉起来，`target` 于是一帧后就被重算成 0）。
  ///
  /// 抽成一处是为了让 `_onTick` 与 [_syncTicker] **共用** —— 两处各写一遍迟早走偏。
  void _retarget() {
    _lift.target = _liftTarget;
  }

  void _armHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = Timer(AppTokens.lensHoldDelay, () {
      _heldLongEnough = true;
      _syncTicker();
    });
  }

  void _endHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _heldLongEnough = false;
  }

  /// 只在**真的还在动**的时候推帧。
  ///
  /// 这是硬要求、不是优化：常驻的 Ticker 会让帧队列永远非空，整个 widget 测试套件
  /// 都会在 `pumpAndSettle` 上超时（v0.9.8 的日历背景光晕就是这么一次红 46 条）。
  ///
  /// 四个弹簧**每一个都要带上** —— 漏掉亮度那条的症状是「手停下来时淡出到一半，
  /// ticker 就停了、彩边被冻在屏幕上」。
  void _syncTicker() {
    // **先按当前意图刷新目标，再判静止。** 顺序反了的话，意图刚翻掉的那一帧会被
    // 判成「已经静止」（`value == 旧的 target`），ticker 当场停掉、`target` 再也
    // 没机会被重算 —— 升程冻死在满档。详见 [_retarget]。
    _retarget();
    final bool needed = _pressed ||
        !_pos.isAtRest ||
        !_lift.isAtRest ||
        !_stretch.isAtRest ||
        !_lit.isAtRest;
    if (needed) {
      if (!_ticker.isActive) {
        _lastTick = null;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    // 第一帧没有上一帧可比 —— 按「一步」算，用 `lensMaxStep` 而不是另写字面量。
    final bool first = _lastTick == null;
    final Duration dt = first ? AppTokens.lensMaxStep : elapsed - _lastTick!;
    _lastTick = elapsed;

    // **提起与落下用两条不同的弹簧**（Apple 自己的数字：Lift 快、Unlift 从容）。
    // 弹簧自己不会「换档」，所以在这里按目标显式切 —— 只改加速度，速度连续。
    final bool lifting = _liftTarget > 0.5;
    _lift.omega = lifting ? AppTokens.lensLiftOmega : AppTokens.lensDropOmega;
    _lift.zeta = lifting ? AppTokens.lensLiftZeta : AppTokens.lensDropZeta;
    _retarget();
    _lift.step(dt);

    if (!_dragging) {
      // 位置的目标 = **该去的那一格**，只有升程起来之后才掺进手指的位置。于是点按
      // 换页时透镜照样「滑过去」，只是不提起。
      final double fingerCentre = _fingerInnerX / _itemW;
      final double t = followFinger ? _lift.value.clamp(0.0, 1.0) : 0.0;
      _pos.target =
          _clampCentre(_slotCentre + (fingerCentre - _slotCentre) * t);
      _pos.step(dt);
    }

    // 速度取**位置的真实帧间差分**，不是弹簧自己的 `velocity`：拖动时弹簧压根没
    // 参与（位置是 1:1 给的），它自己的速度恒为 0，形变就永远不会发生。
    //
    // **分母不许设地板** —— 算式在 `lensVelocityStep` 里，帧率无关性由用例钉着。
    // 第一帧跳过：那时上一帧的位置还是初值，差值不是「位移」。
    if (!first) {
      _velocityPx = lensVelocityStep(
        deltaPage: _pos.value - _lastCentre,
        itemW: _itemW,
        dt: dt,
        previous: _velocityPx,
      );
    }
    _lastCentre = _pos.value;

    _stretch.target =
        (_velocityPx.abs() / velocityRef).clamp(0.0, 1.0);
    _stretch.step(dt);

    // 亮度也走它自己的弹簧，**亮起与熄灭用两条**。目标仍是「动不动」。
    final bool lighting = _velocityPx.abs() > AppTokens.lensRingFullSpeed / 2;
    _lit.omega = lighting ? AppTokens.lensLitOmega : AppTokens.lensUnlitOmega;
    _lit.zeta = lighting ? AppTokens.lensLitZeta : AppTokens.lensUnlitZeta;
    _lit.target = (_velocityPx.abs() / AppTokens.lensRingFullSpeed).clamp(0.0, 1.0);
    _lit.step(dt);

    // **全部静止就自己停下。** 漏了这一段，ticker 就只会被手势停掉 —— 而手势停下
    // 那一刻四个弹簧都还没静止，于是它会**一直跑下去**：帧队列永远非空
    // （`pumpAndSettle` 等不到停），测试结束时报「An animation is still running
    // even after the widget tree was disposed」。
    if (!_pressed &&
        _pos.isAtRest &&
        _lift.isAtRest &&
        _stretch.isAtRest &&
        _lit.isAtRest) {
      _ticker.stop();
      _velocityPx = 0;
    }
    notifyListeners();
  }

  int _indexFor(double dx) {
    var i = (dx / _itemW).floor();
    if (i < 0) i = 0;
    if (i > slots - 1) i = slots - 1;
    return i;
  }

  int _nearestIndex(double p) {
    var i = p.round();
    if (i < 0) i = 0;
    if (i > slots - 1) i = slots - 1;
    return i;
  }

  double _clampPage(double p) {
    if (p < 0) p = 0;
    if (p > slots - 1) p = (slots - 1).toDouble();
    return p;
  }

  /// 把透镜的**中心**夹在容器内。
  ///
  /// 纵向凸出是设计（那是「提起」的信号），**横向不是** —— 按在靠左/靠右时透镜会顶
  /// 出容器两端、被屏幕切掉一截，读起来像 bug 而不像液体。
  ///
  /// 夹紧量用**满升程**的宽度算：跟着当前升程算的话，按下的过程中夹紧量自己会变，
  /// 观感像被谁推了一下。
  double _clampCentre(double v) {
    final double half = (_itemW + liftWidth) / 2;
    final double capsuleW = _itemW * slots + 2 * pad;
    final double minV = (half - pad) / _itemW;
    final double maxV = (capsuleW - half - pad) / _itemW;
    if (minV > maxV) return v; // 容器太窄，夹不了 —— 那就别夹
    if (v < minV) return minV;
    if (v > maxV) return maxV;
    return v;
  }

  @override
  void dispose() {
    // `Timer` 与 `Ticker` 都**必须**收掉：前者留着会让 widget 测试报
    // 「A Timer is still pending even after the widget tree was disposed」，
    // 后者留着会一直调度下一帧（`pumpAndSettle` 永远等不到停）。
    _holdTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }
}
