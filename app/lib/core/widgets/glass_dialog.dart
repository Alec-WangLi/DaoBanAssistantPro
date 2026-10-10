import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'app_icon.dart';

/// 抓一个「关掉本弹窗」的回调，给弹窗里的动作在 `await` 之后用。
///
/// **只有在弹窗还是最上层、且还没开始退场时才真的 pop**（`Route.isCurrent`）。
/// 理由是弹窗里的动作大多是异步的（写库、重排提醒要过原生通道），这段窗口里
/// 用户还能点别的东西：点两次「保存」、或点完「保存」立刻点「取消」/ 点遮罩 ——
/// 每条路径都会 pop 一次，第二次 pop 关掉的已经不是弹窗，而是 App 唯一剩下的
/// 那层路由：Navigator 一条路由不剩 = **整屏纯黑**，而 release 包剥掉了断言，
/// 所以既不报错也不崩，看着就是「屏幕黑了但 App 还活着」。v0.9.0 用户反馈的
/// 「添加待办事项，快速点击添加的时候，APP 直接全部黑屏，但是没有卡死」正是它
/// （2026-09-21 真机复现，两条路径都验过）。`GlassActionButton` 上的那把
/// 「一次动作只许触发一次」的锁只挡得住同一颗按钮被连点，挡不住这种两条路径
/// 各 pop 一次的情况，所以这里还得有一道。
///
/// navigator 与 route **都在 `await` 之前取好**：await 之后弹窗可能已经卸载，
/// 那时再 `Navigator.of(context)` 就是「查一个已失活 element 的祖先」，会抛。
VoidCallback dialogCloser(BuildContext context) {
  final navigator = Navigator.of(context);
  final route = ModalRoute.of(context);
  return () {
    // route 为 null = 没挂在任何路由上（理论上不会），那时按老行为直接 pop。
    if (route == null || route.isCurrent) navigator.pop();
  };
}

/// 通用玻璃弹窗：玻璃容器 + 主色标题条 + 内容 + 底部操作按钮。
///
/// 用于统一各处的弹窗风格（待办、闹钟、确认、日志等）。
/// [showClose] 为 true 时，标题栏右上角显示玻璃 ✕ 关闭按钮（适合单操作弹窗）。
class GlassDialog extends StatefulWidget {
  const GlassDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.showClose = false,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final bool showClose;

  @override
  State<GlassDialog> createState() => _GlassDialogState();
}

class _GlassDialogState extends State<GlassDialog> {
  /// 标题与内容之间、以及正文与动作行之间的间距。
  static const double _gap = 16;

  /// 动作行的高度 —— **量出来的**，首帧先用这个估值顶上。
  ///
  /// 为什么不写成常量：窄窗里三颗按钮会**折行**（`Wrap`），行高因此是 40 或 88
  /// 两档，而正文的底部留白必须正好等于它 —— 猜错就是「滑到底最后一行还压在
  /// 按钮下面」。量一次、之后每次布局都对。
  double _actionsH = 40;

  final GlobalKey _actionsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final hasActions = widget.actions.isNotEmpty;
    if (hasActions) _scheduleMeasure();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        // 给测试一个抓手：断言「操作按钮在面板里」（见 todo_dialog_test.dart
        // 的键盘用例 —— 按钮被挤出面板时，点它只会点到遮罩）。
        key: const Key('glass-dialog-panel'),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusXL),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppTokens.radiusS),
                  ),
                ),
                const SizedBox(width: AppTokens.gapIconTextLg),
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppTokens.dialogTitle,
                  ),
                ),
                if (widget.showClose) const _GlassCloseButton(),
              ],
            ),
            const SizedBox(height: _gap),
            // 内容过长时**卡内滚动**，而不是把弹窗撑到屏幕外。
            //
            // 这里曾经是 `LayoutBuilder` + `ConstrainedBox(maxHeight - 100)`：
            // 想给内容留个上限，但 Column 给子组件的是**无界高度** ——
            // `constraints.maxHeight` 是无穷，那个上限根本不生效。于是键盘弹起、
            // 可用高度变小时，内容把底部的操作按钮**挤出面板**：按钮还画在屏幕上，
            // 却已经不在弹窗的可点区域内，手指点下去穿到遮罩上 ——
            // **弹窗关闭、什么都没存**。v0.7.2 真机实测到的「待办填好了点添加 /
            // 点保存没反应、待办也没出现」就是这个（像素采样：面板底边 y≈1486，
            // 而按钮画在 1458~1595）。
            //
            // `Flexible` 让内容只吃「标题行之外剩下多少」，不够就在卡内滚动，
            // 底部按钮因此**永远在面板里、永远点得到**。
            Flexible(child: _body(hasActions)),
          ],
        ),
        ),
      ),
    );
  }

  /// 内容区 + **浮在它上面**的动作行。
  ///
  /// 2026-10-01 真机反馈：「版本更新和使用帮助这两个界面……它底下有个类似蒙版的
  /// 东西，我们要的是让它悬浮在上边」。此前动作行是 `Column` 里的一个兄弟，内容区的
  /// 视口**到它的上沿就结束了** —— 滚动时正文被齐刷刷切断、下面是一片空面板，
  /// 读起来就像有块板子压着正文。走这个件的每个弹窗都中招（版本更新 / 使用帮助 /
  /// 检查更新 / 重复待办管理 / 我的模板 / 日志），内容越长越明显。
  ///
  /// 现在：内容区的视口铺满整块面板（标题以下到底边），动作行用 `Positioned` 浮在
  /// 它上面；内容自己留一段 `_actionsH + _gap` 的底部空白，于是
  /// **滑到底时最后一行整个在按钮之上**，中途滚动的正文则从胶囊底下穿过去
  /// （按钮是玻璃的，压在上面的字会被磨一下，正是要的「悬浮」观感）。
  ///
  /// 短弹窗（删除确认、添加时段那种）表现与从前一模一样：内容没长到那儿，
  /// 那段留白正好就是动作行原来的位置。
  Widget _body(bool hasActions) {
    // **留白要加在滚动视图「里面」**（`padding:`），不能拿 `Padding` 包在外面 ——
    // 包在外面等于把视口本身截短 56，正文照样在按钮上沿被切断（第一版就是这么写的，
    // 量出来和改之前一模一样）。加在里面只是**滚动内容多出一截**，
    // 视口仍是整个面板的高度。
    // 宽度同样要显式撑满：`SingleChildScrollView` 在松宽度约束下会收缩到内容宽度
    // （短正文只有 200 宽），视口也就跟着窄 —— 那样**只有左边那一条能拖动**
    // （上下滑动要靠视口接收手势），面板右边一大片滑不动。
    final scroll = SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: hasActions ? _actionsH + _gap : 0),
        child: widget.content,
      ),
    );
    if (!hasActions) return scroll;

    // **宽度要显式撑满**：`Stack` 的宽度取自「非定位孩子里最宽的那个」，而
    // `SingleChildScrollView` 在松宽度约束下会**收缩到内容宽度** —— 短正文
    // （「删掉之后这几天就没有排班了。」）只有 200 宽，于是整块正文连同浮在
    // 上面的动作行一起被挤成 200，按钮被迫折成三行、还靠不了右。
    // `double.infinity` 在 Column 的松约束下解析成可用宽度，正好。
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          scroll,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // `Align` + `Wrap` **两个都不能少**（2026-10-01 用户真机反馈「好多按钮
            // 都跑到左边去了」，一查就是这个位置）：
            //
            // · 外层 `Align` 负责**靠右** —— 它没有 sizeFactor 时会撑满可用宽度，
            //   里面那块才有富余可以对齐。`Wrap` 自己**收缩到内容宽度**，而外层
            //   Column 是 `crossAxisAlignment.start`，光有 `Wrap` 的话它连同
            //   `WrapAlignment.end` 一起被贴到左边（`end` 在「自己就是内容那么宽」
            //   时不起任何作用），全 app 二十来个弹窗会一起靠左。
            // · 内层 `Wrap` 负责**窄窗不溢出** —— `Row(mainAxisAlignment: end)` 在
            //   200×400 那档直接横向溢出 23px（弹层内宽只剩约 112dp），`Wrap`
            //   排不下时折到第二行，折完每行同样贴右。
            //
            // **别为了靠右退回 `Row`**，也别为了别的便利把它挪出 `Align`；
            // 两条都有几何用例钉着（`test/glass_dialog_test.dart`）。
            child: KeyedSubtree(
              key: _actionsKey,
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  runSpacing: 8,
                  children: widget.actions,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 量一次动作行的高度，变了就重排。
  ///
  /// 放在帧后而不是 `LayoutBuilder` 里：动作行与正文是两个孩子，**各自布局一次**
  /// 就能拿到自己的高度，不需要互相约束；量到之后下一帧把留白对齐即可（首帧用
  /// 估值 40，弹窗这时候还在入场动画里，看不出来）。
  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _actionsKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if ((h - _actionsH).abs() > 0.5) setState(() => _actionsH = h);
    });
  }
}

/// 标题栏右上角的玻璃圆形 ✕ 关闭按钮。
class _GlassCloseButton extends StatelessWidget {
  const _GlassCloseButton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: dialogCloser(context),
        child: Ink(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTokens.glassTint(isDark, true),
            ),
            border: Border.all(color: AppTokens.glassBorder(isDark)),
          ),
          child: AppIcon(Icons.close_outlined,
              size: AppTokens.iconMd, color: onSurface),
        ),
      ),
    );
  }
}

/// 玻璃浮层的**凝聚**入场 / **消散**退场。
///
/// 玻璃该有的样子是「从模糊里凝出来」：起点小一圈、糊一层，过程中一起收敛到清晰锐利 ——
/// 而不是一张不透明卡片被点亮（`showDialog` 自带的 150ms 淡入就是那样）。
///
/// **动画由外面传进来**，本件自己**不读路由** —— 驱动它的是 `showGlassDialog` 里那条
/// `PopupRoute` 的转场。路由那条同时管入场与退场（`animation` 正向走 / 反向走），
/// 所以退场不用另写一份，正是「消散」。
///
/// 两条曲线分开：入场 `easeOutCubic`（一开始就冲、尾巴缓缓落定），退场 `easeInCubic`
/// （先慢慢化开、最后迅速散掉）。只喂一条的话，退场会一直保持满尺寸、到最后几帧才
/// 「啪」地不见。
///
/// **安定之后直接返回原样的子树**（`t >= 1`）：否则弹窗常驻期间每一帧都要为一块
/// 420 宽的面板付一层 `saveLayer`。`glass_overlay_test` 有一条钉着这件事。
class GlassMaterialize extends StatelessWidget {
  const GlassMaterialize({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  /// 起点缩到多小、起点糊多厚。
  static const double minScale = 0.92;
  static const double blurSigma = 9;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? inner) {
        final double raw = animation.value.clamp(0.0, 1.0);
        if (raw >= 1) return inner!;
        final bool leaving = animation.status == AnimationStatus.reverse;
        final double t =
            (leaving ? Curves.easeInCubic : Curves.easeOutCubic).transform(raw);
        final double blur = blurSigma * (1 - t);
        Widget out =
            Transform.scale(scale: minScale + (1 - minScale) * t, child: inner);
        if (blur > 0.05) {
          out = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: out,
          );
        }
        return Opacity(opacity: t, child: out);
      },
      child: child,
    );
  }
}

/// 玻璃浮层的路由。
///
/// **为什么不直接用 `showGeneralDialog`**：它只有一个 `transitionDuration`，
/// 进场与退场只能同速 —— 而分开的那条是 `TransitionRoute.reverseTransitionDuration`，
/// 要分开就得自己写一条路由。进场 300ms 才读得出「凝聚」，退场 200ms 免得挡路。
class _GlassOverlayRoute<T> extends PopupRoute<T> {
  _GlassOverlayRoute({
    required this.builder,
    required this.barrierLabel,
    this.dismissible = true,
  });

  final WidgetBuilder builder;

  /// 点遮罩算不算「关掉」。**默认可以**；下载进度那种「做到一半不许点掉」的传 false。
  final bool dismissible;

  @override
  final String barrierLabel;

  @override
  Duration get transitionDuration => AppTokens.durGlassIn;

  @override
  Duration get reverseTransitionDuration => AppTokens.durGlassOut;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Color get barrierColor => Colors.black26;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      // ⚠️ **`SafeArea` 不能省。** SDK 的 `DialogRoute` 默认 `useSafeArea: true`，
      // 在 `dialog.dart` 里把 page 包进 `SafeArea`；`Dialog` 自己**不**避让系统栏
      // （它只处理键盘的 `viewInsets`）。漏了这一层，21 处迁移过去的弹窗就全都不再
      // 避让状态栏 / 手势条 / 横屏挖孔 —— 这是**独立审查抓出来的真 regression**
      // （这条路由第一版没有它）。`glass_overlay_test` 有一条钉住。
      SafeArea(child: builder(context));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      GlassMaterialize(animation: animation, child: child);
}

/// **弹窗的统一入口。** 21 处 `showDialog` 全部走它（由
/// `test/glass_overlay_guard_test.dart` 扫源码守着）。
///
/// 与裸 `showDialog` 的三点差别：进场 300ms / 退场 200ms（不是固定的 150ms）、
/// 面板「从模糊里凝出来」、遮罩色与可点关闭**写在一处**（原来是 21 处各写一遍
/// `barrierColor: Colors.black26`）。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    _GlassOverlayRoute<T>(
      builder: builder,
      dismissible: barrierDismissible,
      // 遮罩要一个语义标签（`barrierDismissible` 为真时必须有）—— 走本地化那一份，
      // 与 SDK 的 `DialogRoute` 同一个来源。
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// **底部弹层的统一入口。** 9 处 `showModalBottomSheet` 全部走它。
///
/// 与弹窗那一支的差别：**弹层保留 Material 自带的「从底下升上来」**（那是弹层该有的
/// 动作），凝聚叠在面板上 —— 所以这里不自己写路由，而是把内容包一层 `GlassMaterialize`
/// 并**用弹层自己的路由动画驱动**（`ModalRoute.of(...).animation`）。
///
/// 遮罩色与「底色透明」写在一处（原来是 9 处各写一遍 `backgroundColor: Colors.transparent`
/// 与 `barrierColor: Colors.black26`）。
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black26,
    isScrollControlled: isScrollControlled,
    builder: (BuildContext sheetContext) =>
        _SheetEntrance(child: builder(sheetContext)),
  );
}

/// 弹层的**入场**凝聚：自己跑一次就停。
///
/// ⚠️ **不能拿弹层路由自己的动画驱动它。** `ModalBottomSheetRoute` 把「下拉关闭」的
/// 手势**直接写进同一个 controller**（SDK 的 `bottom_sheet.dart` 里
/// `animationController.value -= primaryDelta / childHeight`）—— 跟着它走的话，
/// 把弹层往下拖三成，面板就被缩到 0.95、糊 σ6、**只剩三成不透明**：一次正常的下拉
/// 手势把面板弄得半透明。（**独立审查抓出来的**，规格里写的也正是「凝聚叠在面板上
/// 即可」—— 它只要求入场。）
class _SheetEntrance extends StatefulWidget {
  const _SheetEntrance({required this.child});

  final Widget child;

  @override
  State<_SheetEntrance> createState() => _SheetEntranceState();
}

class _SheetEntranceState extends State<_SheetEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppTokens.durGlassIn,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      GlassMaterialize(animation: _c, child: widget.child);
}
