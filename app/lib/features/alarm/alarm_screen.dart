import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/layout.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_segment.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../core/widgets/glass_switch.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import 'alarm_service.dart';

/// 闹钟：未来 30 天班次闹钟（可单独开关，响过的自动隐藏）+ 自定义闹钟。
class AlarmScreen extends ConsumerStatefulWidget {
  const AlarmScreen({super.key});

  @override
  ConsumerState<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends ConsumerState<AlarmScreen>
    with WidgetsBindingObserver {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cleanupExpired();
    // 页面可见期间每分钟重建一次，让刚响过的闹钟自动从列表消失。
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cleanupExpired();
      if (mounted) setState(() {});
    }
  }

  /// 删除已响过的一次性自定义闹钟（后台触发后残留的条目）。
  Future<void> _cleanupExpired() async {
    try {
      await ref.read(appRepositoryProvider).deleteExpiredOnceAlarms();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activeScheduleProvider);
    final schedule = async.valueOrNull?.toDomain();
    final alarms =
        ref.watch(customAlarmsProvider).valueOrNull ?? const <CustomAlarm>[];
    final overrides = ref.watch(shiftAlarmOverridesProvider).valueOrNull ??
        const <int, bool>{};
    ref.watch(appSettingsProvider); // 语言切换时重建

    final now = DateTime.now();
    final today = dateOnly(now);
    final shiftAlarms = <_ShiftAlarmEntry>[];
    if (schedule != null) {
      for (var i = 0; i < 30; i++) {
        final date = today.add(Duration(days: i));
        final t = schedule.shiftOn(date);
        if (t == null || t.isRest || !t.alarmEnabled || t.alarms.isEmpty) {
          continue;
        }
        // 这个班次当天**只要还有没响过的闹钟**就保留这一行（响过的自动隐藏）。
        // 判据不能只看第一条 —— 见 `hasPendingShiftAlarm`。
        if (!hasPendingShiftAlarm(t, date, now)) continue;
        shiftAlarms.add(_ShiftAlarmEntry(date, t, overrides[dayNumber(date)] ?? true));
      }
    }

    return Scaffold(
      body: SafeArea(
        child: CenteredContent(child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  L10n.titleAlarm,
                  style: AppTokens.bigNumber,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _sectionTitleRow(context, L10n.upcoming30),
            Expanded(child: _shiftAlarmSection(context, schedule, shiftAlarms)),
            const SizedBox(height: 8),
            _sectionTitleRow(context, L10n.customAlarms),
            Expanded(child: _customAlarmSection(context, alarms)),
            // 底部按钮条是 floatingActionButton、**悬浮在内容之上**
            // （见 _AboveCapsuleBarLocation），正文不给自己留位置就会被压住：
            // 小窗里「自定义闹钟」的空状态提示正好落在它下面。
            // 竖屏内容本来就够短、轮不到压，所以只在小窗/横屏补这块留白。
            if (AppLayout.of(context).isShort ||
                AppLayout.of(context).isNarrow)
              const SizedBox(height: 156),
          ],
        ),
      )),
      floatingActionButtonLocation: const _AboveCapsuleBarLocation(),
      floatingActionButton: _bottomActionBar(context),
    );
  }

  Widget _sectionTitleRow(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _sectionTitle(context, title),
      ),
    );
  }

  Widget _shiftAlarmSection(BuildContext context, ShiftSchedule? schedule,
      List<_ShiftAlarmEntry> shiftAlarms) {
    if (schedule == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (shiftAlarms.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Text(
            L10n.noUpcoming30,
            style: AppTokens.rowSecondary
                .copyWith(color: AppTokens.inkMuted(context)),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      itemCount: shiftAlarms.length,
      itemBuilder: (context, i) => _shiftAlarmTile(context, shiftAlarms[i]),
    );
  }

  Widget _customAlarmSection(BuildContext context, List<CustomAlarm> alarms) {
    if (alarms.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            L10n.noCustomAlarms,
            style: AppTokens.rowSecondary
                .copyWith(color: AppTokens.inkMuted(context)),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      itemCount: alarms.length,
      itemBuilder: (context, i) => _alarmTile(context, alarms[i]),
    );
  }

  Widget _bottomActionBar(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 32;
    return SizedBox(
      width: width,
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: GlassButton(
              primary: true,
              icon: const Icon(Icons.add_outlined),
              onPressed: () => _showAlarmDialog(),
              child: Text(L10n.newAlarm),
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: GlassButton(
              icon: const Icon(Icons.bolt_outlined),
              onPressed: () => _testAlarm(context),
              child: Text(L10n.testAlarmShort),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: AppTokens.titleStrong,
      ),
    );
  }

  Widget _shiftAlarmTile(BuildContext context, _ShiftAlarmEntry e) {
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      // 测试用抓手：按天的行 + 行里每条闹钟的块（`alarm-block-<天>-<序号>`）。
      // 「前一天」标记要断言**跟着各自那条走**，只能靠这个块定位。
      key: Key('alarm-day-row-${dayNumber(e.date)}'),
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          GlassSwitch(
            value: e.enabled,
            onChanged: (v) async {
              await ref.read(appRepositoryProvider).setShiftAlarmOverride(e.date, v);
              _reschedule();
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.shift.name,
                  style: AppTokens.titleStrong.copyWith(
                    color: AppTokens.inkFor(Color(e.shift.color),
                        Theme.of(context).colorScheme.surface),
                  ),
                ),
                Text(
                  L10n.monthDayWeekday(e.date),
                  style: AppTokens.microText.copyWith(color: muted),
                ),
              ],
            ),
          ),
          // 这个班次当天有几条闹钟就列几行（时间 + 可选名字）；落在上班前一天的
          // 那条自己带一行「前一天」小字 —— 多条混排时标记必须跟着**各自那条**
          // 走，不标就会被读成班次当天的钟点（v0.8.9 用户问的正是这个）。
          //
          // **这一列必须 Flexible**：名字最长 12 个字，连着时间一起算下来可能超过
          // 这一行剩下的宽度 —— 不放 Flexible 的话行内会 RenderFlex 溢出
          // （release 下静默裁掉）。名字那一行自身再截断一次（独立审查提的）。
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var k = 0; k < e.shift.alarms.length; k++)
                  Column(
                    key: Key('alarm-block-${dayNumber(e.date)}-$k'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        e.shift.alarms[k].label == null ||
                                e.shift.alarms[k].label!.trim().isEmpty
                            ? _fmt(e.shift.alarms[k].minute)
                            : '${_fmt(e.shift.alarms[k].minute)} '
                                '${e.shift.alarms[k].label!.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.titleStrong,
                      ),
                      if (alarmFallsOnPreviousDay(
                          e.shift, e.shift.alarms[k]))
                        Text(
                          L10n.prevDay,
                          style: AppTokens.microText.copyWith(color: muted),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _alarmTile(BuildContext context, CustomAlarm a) {
    return GlassTile(
      enableBlur: false,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onTap: () => _showAlarmDialog(a: a),
      child: Row(
        children: [
          GlassSwitch(
            value: a.enabled,
            onChanged: (v) async {
              await ref.read(appRepositoryProvider).setCustomAlarmEnabled(a, v);
              _reschedule();
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmt(a.hour * 60 + a.minute),
                  style: AppTokens.sectionTitle,
                ),
                Text(
                  _repeatLabel(a),
                  style: AppTokens.microText
                      .copyWith(color: AppTokens.inkMuted(context)),
                ),
              ],
            ),
          ),
          GlassDeleteButton(
            // 与待办列表同理：行尾用紧凑形态，别让一屏几行的列表挂满红圆。
            compact: true,
            onPressed: () async {
              await ref.read(appRepositoryProvider).deleteCustomAlarm(a);
              _reschedule();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _reschedule() async {
    // 直接查库拿最新排班 + 闹钟 + 按天覆盖 + 待办，避免刚增删改后 Riverpod 流
    // 还未刷新导致漏排/错排。
    await AlarmService.rescheduleAll(ref.read(appRepositoryProvider));
  }

  Future<void> _testAlarm(BuildContext context) async {
    try {
      await AlarmService.testAlarm();
      if (context.mounted) {
        showGlassSnack(
          context,
          L10n.testAlarmScheduled,
          icon: Icons.check_circle_outlined,
          iconColor: AppTokens.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showGlassSnack(
          context,
          '${L10n.testAlarmFailed}$e',
          icon: Icons.error_outlined,
          iconColor: AppTokens.danger,
        );
      }
    }
  }

  /// 新建（[a] 为 null）或编辑（[a] 非空）自定义闹钟。
  void _showAlarmDialog({CustomAlarm? a}) {
    final isEdit = a != null;
    final now = TimeOfDay.now();
    var time = TimeOfDay(hour: a?.hour ?? now.hour, minute: a?.minute ?? now.minute);
    var repeatType = a?.repeatType ?? 1; // 0=一次性 1=每天 2=每周
    var onceDate = a?.onceDate ?? dateOnly(DateTime.now());
    var weekdays = a?.weekdays ?? 0;
    if (repeatType == 2 && weekdays == 0) {
      weekdays = 1 << (DateTime.now().weekday - 1);
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => GlassDialog(
          title: isEdit ? L10n.editAlarm : L10n.newAlarm,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L10n.time),
                trailing: Text(_fmt(time.hour * 60 + time.minute),
                    style: AppTokens.sectionTitle),
                onTap: () async {
                  final p = await showGlassTimePicker(
                      context, initialTime: time);
                  if (p != null) setState(() => time = p);
                },
              ),
              GlassSegment(
                count: 3,
                selectedIndex: repeatType,
                onSelected: (i) => setState(() => repeatType = i),
                itemBuilder: (i, selected) => Text(
                  [L10n.once, L10n.daily, L10n.weekly][i],
                  // 基线 13px：未选中 w500、选中 w700。13 档最重的角色是 w600 的
                  // labelSecondary，两个分支都由这里显式给字重，按 spec 走 copyWith。
                  style: AppTokens.labelSecondary.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (repeatType == 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L10n.date),
                  trailing: Text(L10n.monthDay(onceDate)),
                  onTap: () async {
                    final p = await showGlassDatePicker(
                      context,
                      initialDate: onceDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) setState(() => onceDate = dateOnly(p));
                  },
                ),
              if (repeatType == 2)
                Wrap(
                  spacing: AppTokens.gapIconText,
                  children: List.generate(7, (i) {
                    final bit = 1 << i;
                    final selected = (weekdays & bit) != 0;
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          weekdays &= ~bit;
                        } else {
                          weekdays |= bit;
                        }
                      }),
                      child: AnimatedContainer(
                        duration: AppTokens.durMed,
                        curve: Curves.easeOutBack,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.spaceMd,
                            vertical: AppTokens.spaceSm),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppTokens.radiusL),
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.72)),
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white.withValues(
                                    alpha: isDark ? 0.16 : 0.65),
                          ),
                        ),
                        child: Text(
                          L10n.weekday(i),
                          // 同上面的分段器：13 档取 w600 的 labelSecondary，
                          // 选中加粗到 w700 由这里显式给出。
                          style: AppTokens.labelSecondary.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
          actions: [
            GlassActionButton(
              onPressed: dialogCloser(context),
              label: L10n.cancel,
            ),
            const SizedBox(width: 8),
            GlassActionButton(
              variant: GlassActionVariant.primary,
              onPressed: () async {
                // 一周重复但一天都没选 = 这一下什么也没做，锁当帧放开。
                if (repeatType == 2 && weekdays == 0) return;
                // 关窗回调在 await 之前取好，且只在自己这层还是最上层时才 pop：
                // 连点两次「添加」会插两条自定义闹钟并 pop 两次，第二次 pop 掉的是
                // App 唯一那层路由 = 整屏纯黑（与待办那个 bug 同一形状）。
                final close = dialogCloser(context);
                final repo = ref.read(appRepositoryProvider);
                if (isEdit) {
                  await repo.updateCustomAlarm(
                    a,
                    hour: time.hour,
                    minute: time.minute,
                    repeatType: repeatType,
                    onceDate: repeatType == 0 ? onceDate : null,
                    weekdays: repeatType == 2 ? weekdays : 0,
                  );
                } else {
                  await repo.addCustomAlarm(
                    hour: time.hour,
                    minute: time.minute,
                    repeatType: repeatType,
                    onceDate: repeatType == 0 ? onceDate : null,
                    weekdays: repeatType == 2 ? weekdays : 0,
                  );
                }
                close();
                _reschedule();
              },
              label: isEdit ? L10n.save : L10n.add,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftAlarmEntry {
  const _ShiftAlarmEntry(this.date, this.shift, this.enabled);
  final DateTime date;
  final ShiftClass shift;
  final bool enabled;
}

String _repeatLabel(CustomAlarm a) {
  switch (a.repeatType) {
    case 0:
      return a.onceDate != null
          ? '${L10n.once} · ${L10n.monthDay(a.onceDate!)}'
          : L10n.once;
    case 2:
      final days = <String>[];
      for (var wd = 1; wd <= 7; wd++) {
        if ((a.weekdays & (1 << (wd - 1))) != 0) {
          days.add(L10n.weekday(wd - 1));
        }
      }
      return '${L10n.weekly} · ${days.join(L10n.isEn ? ', ' : '、')}';
    default:
      return L10n.daily;
  }
}

String _fmt(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// 底部按钮条上移，避开悬浮玻璃胶囊（与待办页 FAB 的 `_AboveCapsuleFabLocation` 同一 76px 偏移，底边对齐）。
class _AboveCapsuleBarLocation extends FloatingActionButtonLocation {
  const _AboveCapsuleBarLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final base = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    return Offset(16, base.dy - 76);
  }
}
