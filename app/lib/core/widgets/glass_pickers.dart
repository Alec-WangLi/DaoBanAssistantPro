import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../haptics.dart';
import '../layout.dart';
import '../l10n.dart';
import 'app_icon.dart';
import 'glass_action_button.dart';
import 'glass_dialog.dart';
import 'glass_pill.dart';
import 'glass_pressable.dart';
import 'glass_sheet_header.dart';
import 'glass_sheet_panel.dart';
import 'glass_step_button.dart';

/// 玻璃时间选择器：底部玻璃弹层 + 时/分滚轮 + Q弹按钮。
Future<TimeOfDay?> showGlassTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  return showGlassSheet<TimeOfDay>(
    context: context,
    // 不开这个开关，`showModalBottomSheet` 会把弹层高度压到屏幕的 9/16 ——
    // 横屏 420 高的屏上只有 236px，而下面的内容要 340px，必然溢出。
    isScrollControlled: true,
    builder: (context) => _GlassTimePickerSheet(initialTime: initialTime),
  );
}

class _GlassTimePickerSheet extends StatefulWidget {
  const _GlassTimePickerSheet({required this.initialTime});
  final TimeOfDay initialTime;

  @override
  State<_GlassTimePickerSheet> createState() => _GlassTimePickerSheetState();
}

class _GlassTimePickerSheetState extends State<_GlassTimePickerSheet> {
  late int _hour = widget.initialTime.hour;
  late int _minute = widget.initialTime.minute;

  Widget _wheel({
    required int itemCount,
    required int initialItem,
    required ValueChanged<int> onChanged,
  }) {
    return _wheelWithAppFont(
      context,
      CupertinoPicker(
        scrollController: FixedExtentScrollController(initialItem: initialItem),
        itemExtent: 40,
        // 每吸附到新的一格震一记「咔哒」（2026-11-10 用户拍板）。
        //
        // 旧版这里是「滚轮一律不震」，怕的是把触觉挂到滚动**过程**上 —— 那会拨
        // 一次连震十几下。`onSelectedItemChanged` 不是那个东西：它只在**选中项
        // 真的变了**时回调一次，手感正是 iOS 时间轮盘那种「哒、哒、哒」。滚动
        // 过程中每一帧都震才是要避免的，那件事仍然禁止。
        onSelectedItemChanged: (i) {
          Haptics.select();
          onChanged(i);
        },
        selectionOverlay: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.25),
            ),
          ),
        ),
        children: List.generate(itemCount, (i) {
          return Center(
            child: Text(
              '$i'.padLeft(2, '0'),
              style: AppTokens.dialogTitle,
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheetPanel(
      child: SafeArea(
        // 用弹层**自己的**预算：外层的 margin 与 SafeArea 已经被
        // LayoutBuilder 扣掉了，再照 MediaQuery 自己算一遍容易漏项。
        child: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.selectTime,
                  style: AppTokens.titleStrong,
                ),
                const SizedBox(height: 8),
                // 滚轮吃掉「扣掉固定件之后」的全部高度，封顶 180。
                // **不要再按 `maxHeight` 减常数**：那个常数把标题行高按 22 算，
                // 实际字体下是 25，360×360 小窗差 3px 直接溢出（2026-11-25
                // 加把手后由 Flexible 的有界约束把它暴露出来）。
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: Row(
                      children: [
                        Expanded(
                          child: _wheel(
                            itemCount: 24,
                            initialItem: _hour,
                            onChanged: (i) => _hour = i,
                          ),
                        ),
                        const Text(':', style: AppTokens.bigNumber),
                        Expanded(
                          child: _wheel(
                            itemCount: 60,
                            initialItem: _minute,
                            onChanged: (i) => _minute = i,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GlassActionButton(
                      onPressed: () => Navigator.pop(context),
                      label: L10n.cancel,
                    ),
                    GlassActionButton(
                      variant: GlassActionVariant.primary,
                      onPressed: () {
                        Haptics.select();
                        Navigator.pop(
                            context, TimeOfDay(hour: _hour, minute: _minute));
                      },
                      label: L10n.confirm,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃日期选择器：底部玻璃弹层 + 迷你日历网格（点选即返回）。
///
/// v0.13.23（issue #7）：年月标题可点跳月、翻月箭头显式取色（裸 `Icon` 在深色下
/// 落回纯黑）、面板固定 6 行高 —— 三条都在这一个件里，六个调用点一起受益
/// （统计导出起/止、新建闹钟、添加待办、添加时段、排班编辑两处）。
Future<DateTime?> showGlassDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showGlassSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _GlassDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
    ),
  );
}

class _GlassDatePickerSheet extends StatefulWidget {
  const _GlassDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_GlassDatePickerSheet> createState() => _GlassDatePickerSheetState();
}

class _GlassDatePickerSheetState extends State<_GlassDatePickerSheet> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialDate.year, widget.initialDate.month, 1);
  }

  /// 翻月：一次换月 = 「选中变了」，与统计页期间条同口径一记 `select`（D6）。
  void _stepMonth(int delta) {
    Haptics.select();
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  /// 点年月标题 → 月份弹层（issue #7 第一条：跨几个月只能一下一下点箭头太慢）。
  ///
  /// 月份格自己**故意不震**（`showGlassMonthPicker` 里的注释：两处都挂就是
  /// 一次操作两响），所以由调用方在拿到结果这一步发。
  Future<void> _pickMonth() async {
    final picked = await showGlassMonthPicker(context, initialMonth: _month);
    if (!mounted || picked == null) return;
    Haptics.select();
    setState(() => _month = DateTime(picked.year, picked.month, 1));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // 日期格按可用高度收缩；高屏上取到上限 40，与今天一致。
    final rowH =
        (AppLayout.of(context).availableHeight * 0.10).clamp(32.0, 40.0);
    final leading = DateTime(_month.year, _month.month, 1).weekday - 1;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final selected = widget.initialDate;

    final rows = <Widget>[];
    var rowCells = <Widget>[];
    // 空格必须与日期格**同一套几何**（高度 + 外边距）：第一版拿裸 `SizedBox`
    // 补空行，每行差两个 `gapHair`，翻月时面板仍在跳（427 / 431 实测）。
    Widget emptyCell() => Expanded(
          child: Container(
            height: rowH,
            margin: const EdgeInsets.all(AppTokens.gapHair),
          ),
        );
    for (var i = 0; i < leading; i++) {
      rowCells.add(emptyCell());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_month.year, _month.month, d);
      final enabled = !date.isBefore(widget.firstDate) &&
          !date.isAfter(widget.lastDate);
      final isSelected = date.year == selected.year &&
          date.month == selected.month &&
          date.day == selected.day;
      rowCells.add(Expanded(
        child: GestureDetector(
          onTap: enabled
              ? () {
                  Haptics.select();
                  Navigator.pop(context, date);
                }
              : null,
          child: Container(
            height: rowH,
            margin: const EdgeInsets.all(AppTokens.gapHair),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
            ),
            // 日期数字归一到格子里，**不换行**：200×400 小窗里每格只有
            // 14 宽，「10」会折成「1 / 0」两行（2026-11-25 出图当场看见）。
            // 与日历页同一条口径（D12：正文禁截断，宁缩不折）。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$d',
                maxLines: 1,
                style: AppTokens.rowPrimary.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (enabled
                          ? Theme.of(context).colorScheme.onSurface
                          : AppTokens.inkFaint(context)),
                ),
              ),
            ),
          ),
        ),
      ));
      if (rowCells.length == 7) {
        rows.add(Row(children: rowCells));
        rowCells = <Widget>[];
      }
    }
    if (rowCells.isNotEmpty) {
      while (rowCells.length < 7) {
        rowCells.add(emptyCell());
      }
      rows.add(Row(children: rowCells));
    }
    // 固定 6 行：31 天要 6 行、30 天常常 5 行、2 月可能 4 行 ——
    // 面板高度跟着月份一高一低，正是 issue #7 第三条。
    while (rows.length < 6) {
      rows.add(Row(children: List.generate(7, (_) => emptyCell())));
    }

    return GlassSheetPanel(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final leftBtn = GlassStepButton(
                    icon: Icons.chevron_left_outlined,
                    onTap: () => _stepMonth(-1),
                  );
                  final rightBtn = GlassStepButton(
                    icon: Icons.chevron_right_outlined,
                    onTap: () => _stepMonth(1),
                  );
                  // `Flexible` 必须套在 `Row` 里（`GlassPill` 的子件是
                  // Container，直接给 Flexible 会抛 ParentData 错误）。
                  // 这是统计页期间条同一条配方的搬运（E19）。
                  final titlePill = GlassPill(
                    onTap: _pickMonth,
                    emphasis: true,
                    height: 44,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              L10n.yearMonth(_month),
                              style: AppTokens.titleStrong,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  // 一行要 44 + 44 + 两个间距 + 一个读得出来的标题；再窄就
                  // 真的放不下了（200×400 小窗实测一行给标题只剩 2px，还
                  // 横向溢出 6px）。窄窗改成标题在上、两枚箭头分列下排。
                  if (constraints.maxWidth < _pickerHeaderOneRowMin) {
                    return Column(
                      children: [
                        titlePill,
                        const SizedBox(height: AppTokens.spaceXs),
                        Row(
                          children: [leftBtn, const Spacer(), rightBtn],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      leftBtn,
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(child: Center(child: titlePill)),
                      const SizedBox(width: AppTokens.spaceSm),
                      rightBtn,
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Row(
                children: List.generate(7, (i) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        L10n.weekdays[i],
                        style: AppTokens.microLabel.copyWith(
                          color: AppTokens.inkMuted(context),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 4),
              // 日期格里没有滚轮，不存在手势争抢 —— 收缩到下限仍放不下时，
              // 滚动比把最后一行裁掉好。表头与星期行留在滚动区外，始终可见。
              Flexible(
                child: SingleChildScrollView(child: Column(children: rows)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日期选择弹层顶栏改成上下两排的宽度阈值（逻辑像素）。
///
/// 一行要两枚 44 的步骤钮 + 2×8 间距，标题至少再留 120 才读得出来 ——
/// 224 取整到 240。200×400 小窗的可用宽只有 102，一行必然横向溢出。
const double _pickerHeaderOneRowMin = 240;

/// 年月选择器与年份选择器共用的年份区间。
///
/// **一份常量、两处引用**：两个弹层都在 2000–2100 里滚，口径必须一致 ——
/// 分开写两个数，改一处就漏一处（E19「同一算式只许一处」）。
const int _pickerMinYear = 2000;
const int _pickerMaxYear = 2100;

/// 让 Cupertino 滚轮跟随**应用字体**。
///
/// Cupertino 默认的 `pickerTextStyle` 用的是 `CupertinoSystemDisplay` —— 这套字体
/// 只在 iOS 上存在。Android 真机靠系统字体回落看不出来，但**渲染工装里没有它**，
/// 数字会渲成一排实心方块（2026-11-23 年份弹层第一次进屏单时当场看到）。
///
/// 只替换字体族：字号 / 字重 / 颜色 / 字距仍由每一格的样式与 Cupertino 的默认值
/// 决定，真机观感不变。
Widget _wheelWithAppFont(BuildContext context, Widget child) {
  final base = Theme.of(context).textTheme.bodyMedium;
  final theme = CupertinoTheme.of(context);
  return CupertinoTheme(
    data: theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        pickerTextStyle: theme.textTheme.pickerTextStyle.copyWith(
          fontFamily: base?.fontFamily,
          fontFamilyFallback: base?.fontFamilyFallback,
        ),
      ),
    ),
    child: child,
  );
}

/// 玻璃年月选择器：底部玻璃弹层 + 年份滚轮 + 4×3 月份网格（点选即返回）。
Future<DateTime?> showGlassMonthPicker(
  BuildContext context, {
  required DateTime initialMonth,
}) {
  return showGlassSheet<DateTime>(
    context: context,
    // 与时间选择器同理：不开这个开关，弹层会被压到屏幕的 9/16。
    isScrollControlled: true,
    builder: (context) => _GlassMonthPickerSheet(initialMonth: initialMonth),
  );
}

class _GlassMonthPickerSheet extends StatefulWidget {
  const _GlassMonthPickerSheet({required this.initialMonth});
  final DateTime initialMonth;

  @override
  State<_GlassMonthPickerSheet> createState() => _GlassMonthPickerSheetState();
}

class _GlassMonthPickerSheetState extends State<_GlassMonthPickerSheet> {
  late int _year = widget.initialMonth.year;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentMonth = widget.initialMonth.month;

    return GlassSheetPanel(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 年份滚轮与月份格按弹层预算收缩。高屏上必然取到上限，
            // 因此竖屏结果与今天完全一致。
            final yearH = (constraints.maxHeight * 0.28).clamp(72.0, 120.0);
            final rowH = (constraints.maxHeight * 0.10).clamp(32.0, 40.0);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.jumpToMonth,
                    style: AppTokens.titleStrong,
                  ),
                  const SizedBox(height: 8),
                  // 年份滚轮
                  SizedBox(
                    height: yearH,
                    child: _wheelWithAppFont(
                      context,
                      CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                            initialItem: _year - _pickerMinYear),
                        itemExtent: 40,
                        onSelectedItemChanged: (i) {
                          // 与时间轮盘同一口径：换了一年才震，滚动过程不震。
                          Haptics.select();
                          setState(() => _year = _pickerMinYear + i);
                        },
                        selectionOverlay: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusM),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.25)),
                          ),
                        ),
                        children: List.generate(
                            _pickerMaxYear - _pickerMinYear + 1, (i) {
                          return Center(
                            child: Text(
                              '${_pickerMinYear + i}',
                              style: AppTokens.dialogTitle,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 4×3 月份网格。
                  //
                  // 套一层 Flexible + 滚动是**结构上的兜底**：靠系数估算高度
                  // 容易被标题行高这类固定项顶破（实测差 17px），而网格里
                  // 没有滚轮、不抢手势，滚动是安全的。预算再紧也只是滚动。
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: List.generate(4, (r) {
                          return Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppTokens.spaceSm),
                            child: Row(
                              children: List.generate(3, (c) {
                                final month = r * 3 + c + 1;
                                final isCurrent = month == currentMonth;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      // 这里**故意不震**：月份格是「从弹层里选一个
                                      // 月份」，调用方（日历）拿到结果后会走
                                      // `_setMonth()`，那一步才发 `select()`。
                                      // 两处都挂就是一次操作两响。
                                      Navigator.pop(
                                          context, DateTime(_year, month, 1));
                                    },
                                    child: Container(
                                      height: rowH,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: AppTokens.spaceXs),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? accent
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.radiusS),
                                        border: isCurrent
                                            ? null
                                            : Border.all(
                                                color: Colors.white.withValues(
                                                    alpha:
                                                        isDark ? 0.12 : 0.6),
                                              ),
                                      ),
                                      child: Text(
                                        L10n.monthShort(month),
                                        style: AppTokens.rowPrimary.copyWith(
                                          fontWeight: isCurrent
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isCurrent
                                              ? Colors.white
                                              : onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 玻璃年份选择器：底部玻璃弹层 + 年份滚轮（按下「确定」才返回）。
///
/// 与 [showGlassMonthPicker] 同族，只挑年份 —— 统计页的年视图里跨十年不该点
/// 十下箭头（2026-11-23 用户反馈：年份只能左右切）。
///
/// **触觉分两处、各一记**：滚轮换格自己发 `select()`（与时间轮盘同口径）；
/// 「确定」**不发** —— 调用方拿到年份后走统一的期间切换，那一步才是「选中变了」。
/// 两处都挂就是一次操作两响（与月份选择器里月份格同一条理由）。
Future<int?> showGlassYearPicker(
  BuildContext context, {
  required int initialYear,
}) {
  return showGlassSheet<int>(
    context: context,
    // 与时间 / 年月选择器同理：不开这个开关，弹层会被压到屏幕的 9/16。
    isScrollControlled: true,
    builder: (context) => _GlassYearPickerSheet(initialYear: initialYear),
  );
}

class _GlassYearPickerSheet extends StatefulWidget {
  const _GlassYearPickerSheet({required this.initialYear});

  final int initialYear;

  @override
  State<_GlassYearPickerSheet> createState() => _GlassYearPickerSheetState();
}

class _GlassYearPickerSheetState extends State<_GlassYearPickerSheet> {
  /// 夹进滚轮区间：调用方传 1999 / 2101 时滚轮也不该越界。
  late int _year =
      widget.initialYear.clamp(_pickerMinYear, _pickerMaxYear).toInt();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GlassSheetPanel(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.jumpToYear, style: AppTokens.titleStrong),
                const SizedBox(height: 8),
                // 与时间选择器同一份兜底：吃掉剩余高度、封顶 180（理由见那一处）。
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: _wheelWithAppFont(
                      context,
                      CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                            initialItem: _year - _pickerMinYear),
                        itemExtent: 40,
                        onSelectedItemChanged: (i) {
                          // 换了一年才震，滚动过程不震（与上面那个年份滚轮同口径）。
                          Haptics.select();
                          setState(() => _year = _pickerMinYear + i);
                        },
                        selectionOverlay: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusM),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.25)),
                          ),
                        ),
                        children: List.generate(
                          _pickerMaxYear - _pickerMinYear + 1,
                          (i) => Center(
                            child: Text(
                              '${_pickerMinYear + i}',
                              style: AppTokens.dialogTitle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // **Flexible 是 200 宽小窗的兜底**：两颗按钮的自然宽度
                    // 加起来比弹层内宽（约 102）宽 23px，不 flex 就横溢；
                    // `GlassActionButton` 内部是 `FittedBox(scaleDown)`，给了
                    // 上限之后是「按宽缩小」，不是裁字（与那件自己的注释同一口径）。
                    Flexible(
                      child: GlassActionButton(
                        onPressed: () => Navigator.pop(context),
                        label: L10n.cancel,
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    Flexible(
                      child: GlassActionButton(
                        variant: GlassActionVariant.primary,
                        // 不震：调用方应用年份时自己发 `select()`（见函数注释）。
                        onPressed: () => Navigator.pop(context, _year),
                        label: L10n.confirm,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 从一列选项里挑一个（底部玻璃弹层，选中项打勾并转主色）。
///
/// 标签由调用方给：选项本身可能是 `int`（比如提醒档位里的「不设 / 准时」），
/// 排版与文案都在调用方手里，这里只管「列出、标出当前项、返回选中值」。
///
/// **[T] 不要用可空类型**：这个弹层靠「返回 null = 用户取消了」来判断，选项里
/// 再出现 null，「选了它」和「点外面关掉」就分不开了。需要「无」这一档时用
/// 一个哨兵值（见 `L10n.remindNone`）。
Future<T?> showGlassOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  required T selected,
}) {
  return showGlassSheet<T>(
    context: context,
    builder: (sheetContext) => GlassSheetPanel(
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassSheetHeader(title: title),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    GlassPressable(
                      child: ListTile(
                        title: Text(labelOf(option)),
                        trailing: option == selected
                            ? AppIcon(Icons.check,
                                size: AppTokens.iconMd,
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .primary)
                            : null,
                        onTap: () {
                          Haptics.select();
                          Navigator.pop(sheetContext, option);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
