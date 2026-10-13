import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/layout.dart';
import '../../core/l10n.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_loading.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_segment.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../core/widgets/glass_switch.dart';
import '../../core/widgets/glass_weekday_picker.dart';
import '../../core/widgets/section_heading.dart';
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
    // 「未来 30 天」按天解析 —— 30 天里跨时段边界比 60 天更常见，只画当前方案
    // 就会出现「日历上换了、闹钟页没换」。
    final chain = async.valueOrNull?.chain;
    final alarms =
        ref.watch(customAlarmsProvider).valueOrNull ?? const <CustomAlarm>[];
    final overrides = ref.watch(shiftAlarmOverridesProvider).valueOrNull ??
        const <int, bool>{};
    ref.watch(appSettingsProvider.select((s) => s.language)); // 语言切换时重建（**只订阅语言** —— 全量 watch 会让拨触觉开关也白重建整页）

    final now = DateTime.now();
    final today = dateOnly(now);
    final shiftAlarms = <_ShiftAlarmEntry>[];
    if (chain != null) {
      for (var i = 0; i < 30; i++) {
        final date = today.add(Duration(days: i));
        final t = chain.shiftOn(date);
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
            _sectionTitleRow(L10n.upcoming30),
            Expanded(child: _shiftAlarmSection(context, chain, shiftAlarms)),
            const SizedBox(height: 8),
            _sectionTitleRow(L10n.customAlarms),
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
      floatingActionButtonLocation: const AboveCapsuleLocation.bar(),
      floatingActionButton: _bottomActionBar(context),
    );
  }

  /// 小节标题 + 整行水平 16 的留白（本节的行也走同一档水平内缩）。
  /// 标题本体是共享件 [SectionHeading]（v0.12.0 收口）。
  Widget _sectionTitleRow(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SectionHeading(title),
      ),
    );
  }

  Widget _shiftAlarmSection(BuildContext context, ShiftSource? chain,
      List<_ShiftAlarmEntry> shiftAlarms) {
    if (chain == null) {
      return const GlassLoading();
    }
    if (shiftAlarms.isEmpty) {
      return EmptyState(L10n.noUpcoming30);
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
      // 与上面「班次闹钟」那处同一个角色、同一种形状 —— 收进同一个共享件，
      // 两处同时为空时留白一致（原先这里是 `fromLTRB(16,16,16,8)`、上面是
      // `fromLTRB(16,24,16,24)`，同屏两种空态留白）。
      return EmptyState(L10n.noCustomAlarms);
    }
    return ListView.builder(
      // 这是页面上最下面那段列表，而底部按钮条**悬浮**在它上面：不留底部空白
      // 的话最后一行会被压住（它的删除键点不到）。与待办页同一个常量。
      padding: const EdgeInsets.fromLTRB(16, 0, 16, kFloatingActionInset),
      physics: const BouncingScrollPhysics(),
      itemCount: alarms.length,
      itemBuilder: (context, i) => _alarmTile(context, alarms[i]),
    );
  }

  Widget _bottomActionBar(BuildContext context) {
    // 宽屏下正文被 `CenteredContent` 限宽 720 并居中，这条按钮条也要跟着那个栏宽 ——
    // 不然它在 1280 的车机上从左边缘铺到右边缘，两台按钮孤零零挂在屏幕两端
    // （与待办页那颗「＋」是同一处毛病，2026-10-13 一起收）。
    final contentW = math.min(
        MediaQuery.sizeOf(context).width, AppLayout.maxContentWidth.toDouble());
    final width = contentW - 32;
    return SizedBox(
      // 工装 / 用例量它落点的抓手。
      key: const Key('alarm-action-bar'),
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

  Widget _shiftAlarmTile(BuildContext context, _ShiftAlarmEntry e) {
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      // 测试用抓手：按天的行 + 行里每条闹钟的块（`alarm-block-<天>-<序号>`）。
      // 「前一天」标记要断言**跟着各自那条走**，只能靠这个块定位。
      key: Key('alarm-day-row-${dayNumber(e.date)}'),
      translucentFill: false,
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
                      // 不落在班次当天时标一下：只写钟点会被读成班次当天
                      // （16:30–次日 00:30 的 00:15 就是这一类）。
                      if (_dayMarkerOf(e.shift, e.shift.alarms[k])
                          case final marker?)
                        Text(
                          marker,
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
      translucentFill: false,
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
    // 默认「一次性」：新建自定义闹钟里绝大多数就是「响这一次」，响过之后
    // `deleteExpiredOnceAlarms` 会把它收走，不用用户自己回来删。编辑既有闹钟时
    // 当然还是读存下来的那个值。
    var repeatType = a?.repeatType ?? 0; // 0=一次性 1=每天 2=每周
    // 用户选的日期，**保持原样不动**（新建时就是今天）。真正会响的那天由
    // `_onceDate` 派生 —— 时间默认此刻、写「今天」的话那一刻已经过去了，这一条
    // 既不会响也会被自动删掉（见 `nextOnceDate`）。
    //
    // 这里不能「改钟点时就把 `onceDate` 就地改写成结果」：默认值一顺延到明天，
    // 用户再把钟点往前调回今天，就再也回不到今天了 —— 派生而不是回写，才不会
    // 把默认值当成用户的选择。
    var onceDate = a?.onceDate ?? dateOnly(DateTime.now());
    DateTime onceDateAt(int hour, int minute) => nextOnceDate(
        now: DateTime.now(), chosen: onceDate, hour: hour, minute: minute);
    var weekdays = a?.weekdays ?? 0;
    if (repeatType == 2 && weekdays == 0) {
      weekdays = 1 << (DateTime.now().weekday - 1);
    }

    showGlassDialog<void>(
      context: context,
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
                  // 这一行写的是**真正会响的那天**（`onceDateAt` 派生），不是用户
                  // 选的那个原始日期 —— 两者只在「选的那天已经过去」时才不同。
                  trailing: Text(
                      L10n.monthDay(onceDateAt(time.hour, time.minute))),
                  onTap: () async {
                    final p = await showGlassDatePicker(
                      context,
                      initialDate: onceDateAt(time.hour, time.minute),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) setState(() => onceDate = dateOnly(p));
                  },
                ),
              if (repeatType == 2)
                // 与重复待办弹窗共用同一个控件（`core/widgets/glass_weekday_picker.dart`）：
                // 那段配方原来内联在这里，抄第二份必然抄歪，而抄歪不会报错。
                // **触觉也由那个控件自己发**（`Haptics.select()`，「选中变了」），
                // 这里不许再补一记 —— 一次操作震两下比一下信息量更少。
                GlassWeekdayPicker(
                  value: weekdays,
                  onChanged: (v) => setState(() => weekdays = v),
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
                // 一次性闹钟的日期在这里**再派生一次**：用户可能开着窗一直没动，
                // 那个钟点已经过去了。写库的必须是「下一次出现」，否则这一条不会
                // 响、还会被 `deleteExpiredOnceAlarms` 收走。
                final onceAt =
                    repeatType == 0 ? onceDateAt(time.hour, time.minute) : null;
                if (isEdit) {
                  await repo.updateCustomAlarm(
                    a,
                    hour: time.hour,
                    minute: time.minute,
                    repeatType: repeatType,
                    onceDate: onceAt,
                    weekdays: repeatType == 2 ? weekdays : 0,
                  );
                } else {
                  await repo.addCustomAlarm(
                    hour: time.hour,
                    minute: time.minute,
                    repeatType: repeatType,
                    onceDate: onceAt,
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

/// 这条闹钟不落在班次当天时的标记（`前一天` / `次日`）；落在当天返回 null。
///
/// 只写钟点会被读成班次当天 —— 16:30–次日 00:30 的 00:15 一旦只写「00:15」，
/// 看着就像上班前的那个凌晨（比上班早 16 小时）。
String? _dayMarkerOf(ShiftClass shift, ShiftAlarm alarm) =>
    switch (alarmDayAnchor(shift, alarm)) {
      AlarmDayAnchor.prev => L10n.prevDay,
      AlarmDayAnchor.next => L10n.nextDayMarker,
      AlarmDayAnchor.same => null,
    };
