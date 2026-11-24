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
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_sheet_header.dart';
import '../../domain/shift_rotation.dart';

/// 选择层的结果：改成某个班次、恢复轮转，或「请假 / 加班」这两种日级动作。
enum ShiftOverrideIntent { change, restore, leave, overtime }

class ShiftOverrideChoice {
  const ShiftOverrideChoice.change(ShiftClass this.shift,
      {this.note, this.noteChanged = false})
      : restore = false,
        intent = ShiftOverrideIntent.change;
  const ShiftOverrideChoice.restore()
      : shift = null,
        restore = true,
        note = null,
        noteChanged = false,
        intent = ShiftOverrideIntent.restore;
  const ShiftOverrideChoice.leave()
      : shift = null,
        restore = false,
        note = null,
        noteChanged = false,
        intent = ShiftOverrideIntent.leave;
  const ShiftOverrideChoice.overtime()
      : shift = null,
        restore = false,
        note = null,
        noteChanged = false,
        intent = ShiftOverrideIntent.overtime;

  final ShiftClass? shift;
  final bool restore;

  /// 这一次改班顺带写的备注（已 trim；空串为 null）。
  ///
  /// **只跟着「改班次」走**：请假 / 加班各有自己的备注（存 `shift_day_extras`），
  /// 恢复轮转则要把这条备注一起清掉。见 `ShiftDayNotes`。
  final String? note;

  /// 用户**动过备注框**没有。
  ///
  /// 判据必须是「比进弹层时的那一份」，不能是「备注是不是空」：多天区间里各天
  /// 备注不一致时预填为空，照「空即删除」写库会把那些天的备注全抹掉。
  final bool noteChanged;
  final ShiftOverrideIntent intent;
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
/// 弹出「调整班次」选择层；用户取消返回 null。
///
/// [from] / [to] 是本次要改的日期区间（闭区间，单日时传同一天）。
/// [canRestore] 为真时底部出现「恢复轮转」—— 由调用方判断，只有当区间内至少
/// 有一天已经被覆盖过才有意义。
/// [currentClass] 是当前值，命中的那一项打勾；传 null 则都不打勾。
/// [initialNote] 是这一天已有的**调班备注**（多天区间里不一致时传 null）。
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
  String? initialNote,
  String Function(ShiftClass) timeRangeOf = _defaultTimeRange,
}) {
  final days = daysBetween(from, to) + 1;
  return showGlassSheet<ShiftOverrideChoice>(
    context: context,
    // 与 `glass_pickers.dart` 里的时间 / 日期 / 年月三个底部弹层同理 —— 就是设了
    // `isScrollControlled: true` 的那三个；同文件的 `showGlassOptionPicker` 没设，
    // 因为它只有一行文字的选项、撑不破 9/16。不开这个开关，弹层高度会被压到屏幕的
    // 9/16（600 高的屏只有 337px），而班次一多（四班两倒就有 4 行、前两行还带时间
    // 副标题）必然放不下 —— 最后几行被裁进滚动区，看得见却点不着。
    // 备注输入框也靠它：`isScrollControlled` 关着时键盘弹起来连面板都顶不上去。
    isScrollControlled: true,
    builder: (sheetContext) => _ShiftOverrideSheet(
      schedule: schedule,
      range: L10n.overrideRangeTitle(
          L10n.monthDay(from), L10n.monthDay(to), days),
      currentClass: currentClass,
      canRestore: canRestore,
      initialNote: initialNote,
      timeRangeOf: timeRangeOf,
    ),
  );
}

/// 「调整班次」面板本体。
///
/// **必须是有状态组件**：备注的 `TextEditingController` 要跨「键盘弹起导致的重建」
/// 活下来 —— 放在 builder 里现 new 一份的话，每敲一个字输入框就被重置。
class _ShiftOverrideSheet extends StatefulWidget {
  const _ShiftOverrideSheet({
    required this.schedule,
    required this.range,
    required this.currentClass,
    required this.canRestore,
    required this.initialNote,
    required this.timeRangeOf,
  });

  final ShiftSchedule schedule;
  final String range;
  final ShiftClass? currentClass;
  final bool canRestore;
  final String? initialNote;
  final String Function(ShiftClass) timeRangeOf;

  @override
  State<_ShiftOverrideSheet> createState() => _ShiftOverrideSheetState();
}

class _ShiftOverrideSheetState extends State<_ShiftOverrideSheet> {
  late final TextEditingController _noteCtrl =
      TextEditingController(text: widget.initialNote ?? '');

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 选中某个班次：备注随这一下一起提交（只有「改班次」带备注，
  /// 请假 / 加班 / 恢复轮转各有自己的入口与生命期）。
  void _pickClass(ShiftClass c) {
    final String note = _noteCtrl.text.trim();
    final String initial = (widget.initialNote ?? '').trim();
    Navigator.pop(
      context,
      ShiftOverrideChoice.change(
        c,
        note: note.isEmpty ? null : note,
        noteChanged: note != initial,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule;
    final narrow = AppLayout.of(context).isNarrow;
    final primary = Theme.of(context).colorScheme.primary;
    // 键盘弹起来时面板要整体上移（底部弹层那层布局不看 viewInsets，见
    // `day_extra_sheet.dart` 的说明与 AGENTS.md 第 6 条）。不弹时这里是 0 高。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassPanel(
        solid: true,
        margin: const EdgeInsets.all(12),
        borderRadius:
            const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // **默认是 center，必须显式改成 stretch。** 居中时标题那个 `Padding`
            // 会按内容宽度收缩、于是标题居中，而底下的行是撑满左对齐的 —— 一个
            // 弹层里两种对齐，看着就是「没排过版」。全 app 的列表内容都左对齐。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部走共享件：拖拽把手 + 主色竖条 + 标题 + 分隔线。
              //
              // **这个弹层是干什么的，得由它自己说。** 用户 2026-10-13 真机反馈：
              // 长按那天弹出来一屏班次，全屏没有一处写着「调整班次」—— 光看几个
              // 班次名，不知道这屏是干嘛的、点了会发生什么。
              //
              // 日期区间退到**副标题槽**：它回答的是**这次改哪几天**（范围和上下文），
              // 不是这个弹层的名字。
              GlassSheetHeader(title: L10n.adjustShift, subtitle: widget.range),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppTokens.spaceXs),
                  children: [
                    for (final c in schedule.classes)
                      GlassPressable(
                        child: ListTile(
                          // `dense` + 收紧的内边距：`ListTile` 双行的默认高度约 72dp，
                          // 比全 app 的行节奏松散一大截。
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.spaceMd),
                          // **窄窗能不能读，全在这两个值上**（见 v0.10.x 的注释）：
                          // `ListTile` 默认 minLeadingWidth 40 + horizontalTitleGap 16，
                          // 200dp 宽的行只剩 ~60dp 给文字。
                          minLeadingWidth: 12,
                          horizontalTitleGap: AppTokens.gapIconText,
                          leading: _ClassDot(color: Color(c.color)),
                          title: Text(c.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: (narrow || widget.timeRangeOf(c).isEmpty)
                              ? null
                              : Text(widget.timeRangeOf(c),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTokens.labelSecondary),
                          trailing: identical(c, widget.currentClass)
                              ? AppIcon(Icons.check,
                                  size: AppTokens.iconMd,
                                  color: primary)
                              : null,
                          onTap: () => _pickClass(c),
                        ),
                      ),
                  ],
                ),
              ),
              // 备注：**先写备注再点班次**，两件事一次提交。
              //
              // 放在分隔线以上、班次列表之下 —— 读起来是「改班时顺手写一句」，
              // 而不是和「请假 / 加班 / 恢复轮转」并列的另一个动作。
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTokens.spaceMd,
                    AppTokens.spaceSm, AppTokens.spaceMd, AppTokens.spaceXs),
                child: TextField(
                  key: const Key('shift-override-note'),
                  controller: _noteCtrl,
                  maxLength: 40,
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  style: AppTokens.rowSecondary,
                  decoration: _noteDecoration(context, primary).copyWith(
                    hintText: L10n.shiftNoteHint,
                    counterText: '',
                    prefixIcon: AppIcon(Icons.edit_note_outlined,
                        size: AppTokens.iconMd,
                        color: AppTokens.inkMuted(context)),
                    labelText: L10n.shiftNoteLabel,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceXs),
              // **与班次列表分开。** 不分开的话它们长得和上面几个班次一模一样、
              // 只是少一行时间，读起来像「又一个班次」而不是一个动作。
              const Divider(height: 1),
              const SizedBox(height: AppTokens.spaceXs),
              _extraAction(
                context,
                key: 'shift-override-leave',
                icon: Icons.event_busy_outlined,
                label: L10n.leave,
                choice: const ShiftOverrideChoice.leave(),
              ),
              _extraAction(
                context,
                key: 'shift-override-overtime',
                icon: Icons.more_time_outlined,
                label: L10n.overtime,
                choice: const ShiftOverrideChoice.overtime(),
              ),
              if (widget.canRestore)
                GlassPressable(
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceMd),
                    minLeadingWidth: 12,
                    horizontalTitleGap: AppTokens.gapIconText,
                    leading: AppIcon(Icons.restart_alt,
                        size: AppTokens.iconMd,
                        color: AppTokens.inkMuted(context)),
                    title: Text(L10n.restoreRotation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.rowSecondary
                            .copyWith(color: AppTokens.inkMuted(context))),
                    onTap: () => Navigator.pop(
                        context, const ShiftOverrideChoice.restore()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 备注框的装饰：**在实心白面板上也要看得见**。
  ///
  /// `glassInputDecoration` 的填充与描边都是「白上白」—— 编辑器那页靠卡片自身的
  /// 浅灰底把框衬出来，而这个弹层是 `solid:true` 的白面板，直接用等于画了个隐形框
  /// （2026-11-17 出图第一版就是这样）。这里改用与未选中 chip 同一套配方：
  /// 主色 6% 填充 + 白描边压到 85%，既看得见又不抢眼。
  InputDecoration _noteDecoration(BuildContext context, Color primary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusM),
      borderSide: BorderSide(
        color: AppTokens.glassBorder(isDark)
            .withValues(alpha: isDark ? 0.30 : 0.85),
      ),
    );
    return glassInputDecoration(context, isDense: true).copyWith(
      fillColor: primary.withValues(alpha: 0.06),
      border: border,
      enabledBorder: border,
    );
  }
}

/// 「请假 / 加班」那种动作行：图标 + 次要色文字，读起来是动作而不是班次。
Widget _extraAction(
  BuildContext context, {
  required String key,
  required IconData icon,
  required String label,
  required ShiftOverrideChoice choice,
}) {
  final muted = AppTokens.inkMuted(context);
  return GlassPressable(
    child: ListTile(
      key: Key(key),
      dense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      minLeadingWidth: 12,
      horizontalTitleGap: AppTokens.gapIconText,
      leading: AppIcon(icon, size: AppTokens.iconMd, color: muted),
      title: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTokens.rowSecondary.copyWith(color: muted)),
      onTap: () => Navigator.pop(context, choice),
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
