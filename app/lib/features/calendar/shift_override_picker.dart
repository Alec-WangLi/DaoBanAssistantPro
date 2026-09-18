// 「调整班次」底部选择层：给一天或一段日子单独指定班次（或恢复轮转）。
//
// 配方照抄现有的底部弹层（`glass_pickers.dart` 的 `showGlassOptionPicker`）：
// 透明遮罩 + `GlassPanel(solid: true)` + `GlassPressable` 包 `ListTile`。
// 没直接复用它，是因为它只认一个 `labelOf` 字符串 —— 这里每行还要画一个班次色
// 圆点和一行时间，另外底部要挂一条「恢复轮转」。
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/layout.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../domain/shift_rotation.dart';

/// 选择层的结果：改成某个班次，或恢复轮转。
class ShiftOverrideChoice {
  const ShiftOverrideChoice.change(ShiftClass this.shift) : restore = false;
  const ShiftOverrideChoice.restore() : shift = null, restore = true;

  final ShiftClass? shift;
  final bool restore;
}

/// 班次的时间区间文本。
///
/// **不能直接调 `L10n.timeRange`**：它的签名是
/// `timeRange(String start, String end, bool crossesMidnight)` —— 收的是两个
/// 钟面字符串加一个跨午夜标志，不是分钟整数。所以这里自己把分钟换算成钟面，
/// 换算规则与 `calendar_screen.dart` 里那个同名私有函数 `_timeRange(ShiftClass)`
/// 一致（`endMinute > 1440` 时减 1440；`nextDay = e > 1440 || e < s`）。
/// 那边收的也是 `ShiftClass`，但它是日历页的私有函数、且那边不归本轮改，
/// 所以这里是第二份 —— 两份的输入类型本就不同，不值得为去重把它们耦合起来。
String _defaultTimeRange(ShiftClass c) {
  final s = c.startMinute, e = c.endMinute;
  if (s == null || e == null) return '';
  var end = e;
  final nextDay = end > 1440 || end < s;
  if (end > 1440) end -= 1440;
  return L10n.timeRange(formatClock(s), formatClock(end), nextDay);
}

/// 弹出「调整班次」选择层；用户取消返回 null。
///
/// [from] / [to] 是本次要改的日期区间（闭区间，单日时传同一天）。
/// [canRestore] 为真时底部出现「恢复轮转」—— 由调用方判断，只有当区间内至少
/// 有一天已经被覆盖过才有意义。
/// [currentClass] 是当前值，命中的那一项打勾；传 null 则都不打勾。
///
/// **必须传 `schedule.classes` 里的那个实例** —— 也就是 `ShiftSchedule.shiftOn`
/// 之类从同一份 [schedule] 取出来的对象。判等走 `identical` 而不是 `==`：
/// 班次定义的内容允许重复（编辑器里完全可以并存两个同名同时段的班次），用 `==`
/// 会把内容相同的**两行**一起打上勾；这里要表达的是「就是本方案里的这一项」。
Future<ShiftOverrideChoice?> showShiftOverridePicker(
  BuildContext context, {
  required ShiftSchedule schedule,
  required DateTime from,
  required DateTime to,
  ShiftClass? currentClass,
  bool canRestore = false,
  String Function(ShiftClass) timeRangeOf = _defaultTimeRange,
}) {
  final days = daysBetween(from, to) + 1;
  final title = L10n.overrideRangeTitle(
      L10n.monthDay(from), L10n.monthDay(to), days);
  // 提在循环外：它不随班次变，而下面每行都要用（见那里的说明）。
  final narrow = AppLayout.of(context).isNarrow;

  return showModalBottomSheet<ShiftOverrideChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    // 与 `glass_pickers.dart` 里的时间 / 日期 / 年月三个底部弹层同理 —— 就是设了
    // `isScrollControlled: true` 的那三个；同文件的 `showGlassOptionPicker` 没设，
    // 因为它只有一行文字的选项、撑不破 9/16。不开这个开关，弹层高度会被压到屏幕的
    // 9/16（600 高的屏只有 337px），而班次一多（四班两倒就有 4 行、前两行还带时间
    // 副标题）必然放不下 —— 最后几行被裁进滚动区，看得见却点不着。
    isScrollControlled: true,
    barrierColor: Colors.black26,
    builder: (sheetContext) => GlassPanel(
      solid: true,
      margin: const EdgeInsets.all(12),
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // **默认是 center，必须显式改成 stretch。** 居中时标题那个 `Padding`
          // 会按内容宽度收缩、于是标题居中，而底下的行是撑满左对齐的 —— 一个
          // 弹层里两种对齐，看着就是「没排过版」。全 app 的列表内容都左对齐。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                  AppTokens.spaceLg, AppTokens.spaceLg, AppTokens.spaceSm),
              child: Text(title, style: AppTokens.titleStrong),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                // 左右留出与 `GlassPanel` 圆角相称的边距；行自己的内边距另算。
                // 这 4dp 是有来历的：200dp 宽的行总共只有约 160dp，时间副标题
                // 差的就是这么几个字 —— 原来是 8，收掉 4dp 之后才放得下。
                padding:
                    const EdgeInsets.symmetric(horizontal: AppTokens.spaceXs),
                children: [
                  for (final c in schedule.classes)
                    GlassPressable(
                      child: ListTile(
                        // `dense` + 收紧的内边距：`ListTile` 双行的默认高度约 72dp，
                        // 比全 app 的行节奏松散一大截；这个弹层一屏要放四五个班次
                        // 再加一个动作，松了就显得「不像这个 App」。
                        // 用 `ListTile` 而不是手搓行：它是全 app 列表行的做法
                        // （排班管理那页就是），也白拿无障碍语义。
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.spaceMd),
                        // **窄窗能不能读，全在这两个值上。** `ListTile` 的
                        // `minLeadingWidth` 默认 **40**、`horizontalTitleGap` 默认
                        // **16** —— 两者合起来吃掉约 56dp，而 200dp 宽的行总共
                        // 只有约 160dp：留给文字的只剩 ~60dp，于是时间被挤成一个
                        // 字（「18:00 – 22:00」→「1…」），第一行更是在极窄约束下
                        // 整行塌掉（标题 0 宽、副标题占了标题的位置）。
                        // 实测把这两个收掉之后时间才放得下。
                        minLeadingWidth: 12,
                        horizontalTitleGap: AppTokens.gapIconText,
                        leading: _ClassDot(color: Color(c.color)),
                        // 两句都封成一行 + 省略号：200dp 宽的小窗里不封的话，
                        // 班次名会被挤成**一行一个字**（用户真能拖到那个尺寸）。
                        title: Text(c.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        // 窄窗（< 360dp）下**不显示时间**。200dp 的行总共只有约
                        // 160dp，而带打勾那一行还要再让出约 40dp —— 时间必然只剩
                        // 半截（「08:00 …」「20:30 – 次…」），而半截字比没有更糟。
                        // 挑班次靠的是名字；400×640 那档照常显示。
                        subtitle: (narrow || timeRangeOf(c).isEmpty)
                            ? null
                            : Text(timeRangeOf(c),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTokens.labelSecondary),
                        trailing: identical(c, currentClass)
                            ? AppIcon(Icons.check,
                                size: AppTokens.iconMd,
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .primary)
                            : null,
                        onTap: () => Navigator.pop(
                            sheetContext, ShiftOverrideChoice.change(c)),
                      ),
                    ),
                ],
              ),
            ),
            if (canRestore) ...[
              // **与班次列表分开。** 不分开的话它长得和上面几个班次一模一样、
              // 只是少一行时间，读起来像「又一个班次」而不是一个动作。
              // 一条细分隔线加次要文字色就够了，不必再来一个按钮。
              const SizedBox(height: AppTokens.spaceXs),
              // 分隔线用**全 app 那个配方**（`const Divider(height: 1)`，
              // `profile_screen.dart` 里用了五处）。这里原本我自作主张挑了
              // `AppTokens.glassBorder` —— 那是玻璃的**白色高光**，画在白面板上
              // 就是白上白，出图采样证实它一个像素都没画出来。
              const Divider(height: 1),
              const SizedBox(height: AppTokens.spaceXs),
              GlassPressable(
                child: ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
                  // 与上面的班次行同值，好让两者的左缘对齐（图标 20 与色点 12
                  // 宽度不同，文字会差 8dp —— 可接受，左边那条线对齐更重要）。
                  minLeadingWidth: 12,
                  horizontalTitleGap: AppTokens.gapIconText,
                  leading: AppIcon(Icons.restart_alt,
                      size: AppTokens.iconMd,
                      color: AppTokens.inkMuted(sheetContext)),
                  title: Text(L10n.restoreRotation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.rowSecondary
                          .copyWith(color: AppTokens.inkMuted(sheetContext))),
                  onTap: () => Navigator.pop(
                      sheetContext, const ShiftOverrideChoice.restore()),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// 班次色的圆点。
///
/// **12dp，与信息卡里那个色点同一个规格。** 全 app 表示「这是哪个班次」的色点
/// 就这两处；两处不一致（原来这里是 20dp）会让人以为是两个不同的东西。
///
/// 这个 12 是**字面量**而不是令牌 —— `AppTokens` 的图标刻度是 16/20/24，没有 12
/// 这一档，而 12 落在 4px 栅格上。`design_tokens_test` 也不扫 `Container(width:)`，
/// 所以它过了守门、却确实是写死的数：这是**有据可查的决定**，不是遗漏。
/// （信息卡那个 12dp 是同一回事，两处保持一致。）
class _ClassDot extends StatelessWidget {
  const _ClassDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
