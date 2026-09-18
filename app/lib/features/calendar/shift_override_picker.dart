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
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLg, AppTokens.spaceLg, AppTokens.spaceLg, 8),
              child: Text(title, style: AppTokens.titleStrong),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in schedule.classes)
                    GlassPressable(
                      child: ListTile(
                        leading: _ClassDot(color: Color(c.color)),
                        title: Text(c.name),
                        subtitle: timeRangeOf(c).isEmpty
                            ? null
                            : Text(timeRangeOf(c),
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
            if (canRestore)
              GlassPressable(
                child: ListTile(
                  leading: AppIcon(Icons.restart_alt,
                      size: AppTokens.iconMd,
                      color: AppTokens.inkMuted(sheetContext)),
                  title: Text(L10n.restoreRotation),
                  onTap: () => Navigator.pop(
                      sheetContext, const ShiftOverrideChoice.restore()),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 班次色的圆点，落在 `ListTile.leading` 位。
///
/// 尺寸取 `iconMd`（20dp），**有意不与信息卡里那个 12dp 的色点统一**：
/// - 这里它在 `ListTile.leading`，对面那个打勾（`trailing`）也是 20dp，缩到 12
///   会和它失衡；
/// - 信息卡里那个 12dp 是行内元素，本来就该小一档。
///
/// 20dp 取的是令牌 `AppTokens.iconMd`；信息卡那个 12dp 是**字面量**（恰好落在
/// 4px 栅格上，**不在**令牌上，也就不受 `design_tokens_test` 的字面量守门覆盖）。
/// 两者尺寸不同是**有据可查的决定**，不是遗漏（spec §7.4）。
class _ClassDot extends StatelessWidget {
  const _ClassDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: AppTokens.iconMd,
        height: AppTokens.iconMd,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
