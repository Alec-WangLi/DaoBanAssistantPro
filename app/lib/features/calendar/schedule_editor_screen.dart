import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/layout.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_choice_chip.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../core/widgets/glass_segment.dart';
import '../../core/widgets/glass_snackbar.dart';
import '../../core/widgets/glass_switch.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import '../alarm/alarm_service.dart';

/// 排班方案编辑器。
///
/// 两层模型：先定义「班次」（白班/夜班/休班…），再排「周期」（第 N 天引用哪个
/// 班次）。周期长度与班组数是两个彼此独立的步进器 —— 周期决定几天一循环，班组数
/// 决定有几组人错开。
///
/// [scheduleId] 为空时编辑当前排班方案；否则编辑指定方案。
class ScheduleEditorScreen extends ConsumerStatefulWidget {
  const ScheduleEditorScreen({super.key, this.scheduleId});

  final int? scheduleId;

  @override
  ConsumerState<ScheduleEditorScreen> createState() =>
      _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends ConsumerState<ScheduleEditorScreen> {
  static const _palette = [
    0xFF4C8DFF, 0xFF7A5CFF, 0xFF9AA0B4, 0xFF5A5F73,
    0xFF34C759, 0xFFFF9F0A, 0xFFFF375F, 0xFF00C7BE,
  ];

  /// 简称输入框宽度：放得下 2 个汉字（`maxLength: 2`）再加边框内边距。
  ///
  /// 60 是按 **14 号字**算出来的（两个汉字 28，加 `OutlineInputBorder` 的
  /// 内边距）；字号统一到 16 后两个汉字要 32，60 又会把第二个字裁掉 ——
  /// 而只断言文本内容的 widget 测试看不出这种截断，只有真机截图才发现。
  /// 所以字号与这个宽度必须一起改。
  static const double _abbrFieldWidth = 68;

  bool _loaded = false;
  bool _notFound = false;
  bool _saving = false;
  String _name = '';
  DateTime _anchor = DateTime.utc(2025, 1, 6);

  /// 班次定义（一个班次只定义一次）。
  List<ShiftClass> _classes = [];

  /// 周期序列：长度即周期，元素是 [_classes] 的下标。
  List<int> _cycle = [];

  int _teamCount = 4;
  List<String> _teamNames = ['一班', '二班', '三班', '四班'];
  int _ourTeamIndex = 0;
  List<int> _teamOffsets = [0, 1, 2, 3];
  bool _followHoliday = false; // 空白表：跟随法定节假日，无班次轮换
  bool _crewExpanded = false;

  // 可编辑文本用真控制器（与 _classes / _teamNames 平行），而不是每次 build
  // 新建 —— 后者会让光标跳动并泄漏控制器。
  final List<TextEditingController> _nameCtrls = [];
  final List<TextEditingController> _abbrCtrls = [];
  final List<TextEditingController> _teamNameCtrls = [];
  final TextEditingController _scheduleNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _disposeClassCtrls();
    for (final c in _teamNameCtrls) {
      c.dispose();
    }
    _teamNameCtrls.clear();
    _scheduleNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    ShiftSchedule? d;
    if (widget.scheduleId != null) {
      d = await ref
          .read(appRepositoryProvider)
          .getScheduleDomain(widget.scheduleId!);
    } else {
      final active = await ref.read(activeScheduleProvider.future);
      d = active?.toDomain();
    }
    if (d == null) {
      if (mounted) setState(() => _notFound = true);
      return;
    }
    final dd = d;
    if (mounted && !_loaded) {
      setState(() {
        _loaded = true;
        _name = dd.name;
        _scheduleNameCtrl.text = dd.name;
        _anchor = dd.anchorDate;
        _classes = List.of(dd.classes);
        _cycle = List.of(dd.cycle);
        _teamCount = dd.teamCount;
        _teamNames = List.of(dd.teamNames);
        _ourTeamIndex = dd.ourTeamIndex;
        _teamOffsets = dd.teamOffsets.length == dd.teamCount
            ? List.of(dd.teamOffsets)
            : List.generate(
                dd.teamCount,
                (i) =>
                    ((i - dd.ourTeamIndex) % dd.teamCount + dd.teamCount) %
                    dd.teamCount,
              );
        _followHoliday = dd.isBlank;
        _syncClassCtrls();
        _syncTeamNameCtrls();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 控制器同步
  // ---------------------------------------------------------------------------

  void _syncClassCtrls() {
    _disposeClassCtrls();
    for (final c in _classes) {
      _nameCtrls.add(TextEditingController(text: c.name));
      _abbrCtrls.add(TextEditingController(text: c.abbr ?? ''));
    }
  }

  void _disposeClassCtrls() {
    for (final c in _nameCtrls) {
      c.dispose();
    }
    for (final c in _abbrCtrls) {
      c.dispose();
    }
    _nameCtrls.clear();
    _abbrCtrls.clear();
  }

  void _syncTeamNameCtrls() {
    for (final c in _teamNameCtrls) {
      c.dispose();
    }
    _teamNameCtrls.clear();
    for (final n in _teamNames) {
      _teamNameCtrls.add(TextEditingController(text: n));
    }
  }

  // ---------------------------------------------------------------------------
  // 日期换算
  // ---------------------------------------------------------------------------

  /// 某班组的「周期起始日」= 基准日 − teamOffsets[它] 天。
  DateTime _crewStartDate(int i) {
    final off = i < _teamOffsets.length ? _teamOffsets[i] : i;
    return dateOnly(_anchor).subtract(Duration(days: off));
  }

  /// 用户把某班组的起始日改成 [date] 后，回填 teamOffsets。
  ///
  /// 改的是「我这一组」时必须走 [_setMyCycleStart] 的重锚定语义而不是只改
  /// 单个偏移 —— 只改一个偏移会让我这组与其他班组的**相对错位**跟着变，
  /// 等于把整个班表结构弄坏了。
  void _setCrewStartDate(int i, DateTime date) {
    if (i == _ourTeamIndex) {
      _setMyCycleStart(date);
      return;
    }
    final off = daysBetween(dateOnly(date), dateOnly(_anchor));
    setState(() => _teamOffsets[i] = off);
  }

  /// 我的班组的周期起始日（顶部卡片的显示值）。
  DateTime get _myCrewStart => _crewStartDate(_ourTeamIndex);

  /// 把「我的班组」的起始日设为 [date]。
  ///
  /// 做法：把基准日挪到 [date]，并把所有班组偏移整体减去「我这一组的偏移」，
  /// 使我的班组在新基准日恰好处于周期第 0 项，同时保持各班组之间的相对错位
  /// 不变。
  ///
  /// 注意这里减去的是「我的基线偏移」（归一化后恒为 0），不是基准日的位移量：
  /// 后者会让整个日历多平移一份，班组行的「周期起始日」也会和顶部显示对不上。
  void _setMyCycleStart(DateTime date) {
    final base =
        _ourTeamIndex < _teamOffsets.length ? _teamOffsets[_ourTeamIndex] : 0;
    setState(() {
      _anchor = dateOnly(date);
      for (var i = 0; i < _teamOffsets.length; i++) {
        _teamOffsets[i] = _teamOffsets[i] - base;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.editSchedule)),
      body: _notFound
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(L10n.scheduleNotFound),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(L10n.back),
                  ),
                ],
              ),
            )
          : !_loaded
              ? const Center(child: CircularProgressIndicator())
              : CenteredContent(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                      AppTokens.spaceLg,
                      AppTokens.spaceSm,
                      AppTokens.spaceLg,
                      // 底部要给悬浮胶囊让位；短屏胶囊更矮，留白同步收。
                      AppLayout.of(context).isShort ? 56 : 100),
                  children: [
                    _previewStrip(context),
                    _headerCard(context),
                    const SizedBox(height: AppTokens.spaceMd),
                    if (!_followHoliday) ...[
                      _classesCard(context),
                      const SizedBox(height: AppTokens.spaceMd),
                      _cycleCard(context),
                      const SizedBox(height: AppTokens.spaceMd),
                      _crewCard(context),
                      const SizedBox(height: AppTokens.spaceMd),
                    ],
                    _followHolidayCard(context),
                  ],
                ),
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          // 正文用 CenteredContent 限了 720，底部的保存按钮要跟它对齐，
          // 否则宽屏上按钮横贯整屏、与居中的正文错位。不能直接复用
          // CenteredContent：它里面的 Center 没设 heightFactor，在
          // bottomNavigationBar 的松高度约束下会撑满整屏，把正文挤成 0
          // （widget 测试当场抓出来过）。这里只做水平限宽居中。
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: AppLayout.maxContentWidth),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check_outlined),
                label: Text(L10n.saveAndReschedule),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 0) 未来 14 天预览：改任何设置都能立刻看出对不对。
  ///
  /// 用 [_anchor] 而不是 [_myCrewStart]：`anchorDate` 才是真正持久化的字段，
  /// 这里要预览的就是保存后日历会显示的东西。
  Widget _previewStrip(BuildContext context) {
    final schedule = ShiftSchedule(
      name: _name,
      anchorDate: dateOnly(_anchor),
      classes: _classes,
      cycle: _cycle,
      teamCount: _teamCount,
      teamNames: _teamNames,
      ourTeamIndex: _ourTeamIndex,
      teamOffsets: _teamOffsets,
    );
    final today = dateOnly(DateTime.now());
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

    return GlassTile(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.previewNext14,
              style: const TextStyle(
                  fontSize: AppTokens.fontCaption, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppTokens.spaceSm),
          // 7 列 × 2 行，与日历的 7 列节奏一致 —— 横向滚动会让最后一格
          // 永远吊在半路，这里两行排满就没有裁切，也不需要滑动提示。
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: AppTokens.spaceSm),
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _previewCell(
                      schedule,
                      today.add(Duration(days: row * 7 + col)),
                      muted,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewCell(ShiftSchedule schedule, DateTime date, Color muted) {
    final s = schedule.shiftOn(date);
    final color = s == null ? muted : Color(s.color);
    return Column(
      children: [
        // 单行：窄格子里 `12/25` 这种 5 字符日期换行会把两行的高度撑破
        // （大字号系统字体下同理）。
        Text('${date.month}/${date.day}',
            maxLines: 1,
            style: TextStyle(fontSize: AppTokens.fontCaption, color: muted)),
        const SizedBox(height: AppTokens.spaceXs),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceSm, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            s?.shortLabel ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: AppTokens.fontCaption,
                fontWeight: FontWeight.w700,
                // 底色是班次色 16% 的淡染，字得按它算可读版本，不能直接用班次色
                // （橙 `#FF9F0A` 这类浅色压上去几乎看不见）。
                color: AppTokens.inkFor(
                    color,
                    Color.alphaBlend(
                        color.withValues(alpha: 0.16),
                        Theme.of(context).colorScheme.surface))),
          ),
        ),
      ],
    );
  }

  /// 1) 方案名称 + 我的班组起始日。
  ///
  /// 两者合成一张卡：名称原本单独占一张几乎空着的卡，而「我这组从哪天开始」
  /// 是整页第二重要的字段，放在一起信息密度更合理。
  Widget _headerCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return GlassTile(
      // 窄屏把卡片内边距收一档，把宽度留给内容（字号不缩，可读性优先）。
      padding: EdgeInsets.all(
          AppLayout.of(context).isNarrow ? AppTokens.spaceMd : AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _scheduleNameCtrl,
            onChanged: (v) => _name = v,
            decoration: glassInputDecoration(context, L10n.scheduleName),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
            onTap: () async {
              final picked = await showGlassDatePicker(
                context,
                initialDate: _myCrewStart,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) _setMyCycleStart(picked);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceSm, vertical: AppTokens.spaceMd),
              child: Row(
                children: [
                  Icon(Icons.today_outlined,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: AppTokens.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.myCycleStart,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppTokens.fontLead)),
                        const SizedBox(height: AppTokens.spaceXs),
                        Text(
                          L10n.yearMonthDay(_myCrewStart),
                          style: TextStyle(
                              fontSize: AppTokens.fontSupport, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.edit_outlined, size: 20, color: muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3) 班次设置：每个班次定义一次，周期里直接引用。
  Widget _classesCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return GlassTile(
      // 窄屏把卡片内边距收一档，把宽度留给内容（字号不缩，可读性优先）。
      padding: EdgeInsets.all(
          AppLayout.of(context).isNarrow ? AppTokens.spaceMd : AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.shiftClasses,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: AppTokens.fontLead),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            L10n.shiftClassesHint,
            style: TextStyle(fontSize: AppTokens.fontSupport, color: muted),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          ..._classes.asMap().entries.map((e) => _classRow(context, e.key)),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _addClass,
              icon: const Icon(Icons.add_outlined),
              label: Text(L10n.addShiftClass),
            ),
          ),
        ],
      ),
    );
  }

  Widget _classRow(BuildContext context, int index) {
    final c = _classes[index];
    final primary = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        border: Border.all(color: outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 身份行：色点（点一下改色）· 名称 · 简称 · 删除
          Row(
            children: [
              _colorDot(context, index, c),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: TextField(
                  controller: _nameCtrls[index],
                  onChanged: (v) => setState(() =>
                      _classes[index] = _editClass(_classes[index], name: v)),
                  decoration: glassInputDecoration(context, L10n.shiftName,
                      isDense: true),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              SizedBox(
                width: _abbrFieldWidth,
                child: TextField(
                  controller: _abbrCtrls[index],
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  onChanged: (v) => setState(() =>
                      _classes[index] = _editClass(_classes[index], abbr: v)),
                  decoration: glassInputDecoration(context, L10n.abbrLabel,
                          isDense: true)
                      .copyWith(counterText: ''),
                ),
              ),
              const SizedBox(width: AppTokens.spaceXs),
              GlassDeleteButton(
                compact: true,
                onPressed: () => _deleteClass(index),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          // 工作 / 休息用分段器：两个标签都在，不会像裸开关那样让人猜
          // 「拨过去是休息还是启用」。与闹钟页、我的页的选择器同款手感。
          GlassSegment(
            count: 2,
            height: 38,
            selectedIndex: c.isRest ? 1 : 0,
            onSelected: (i) => _setRest(index, i == 1),
            itemBuilder: (i, selected) => Center(
              child: Text(
                i == 0 ? L10n.work : L10n.rest,
                style: TextStyle(
                  fontSize: AppTokens.fontSupport,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : muted,
                ),
              ),
            ),
          ),
          if (!c.isRest) ...[
            const SizedBox(height: AppTokens.spaceMd),
            Row(
              children: [
                Expanded(
                  child: _timeChip(
                    context,
                    label: L10n.start,
                    minutes: c.startMinute,
                    onPick: (m) => setState(() => _classes[index] =
                        _editClass(_classes[index], startMinute: m)),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: _endTimeChip(
                    context,
                    label: L10n.end,
                    shift: c,
                    onPick: (m) => setState(() => _classes[index] =
                        _editClass(_classes[index], endMinute: m)),
                  ),
                ),
              ],
            ),
            if (c.crossesMidnight)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                child: Text(L10n.crossesMidnight,
                    style: TextStyle(
                        fontSize: AppTokens.fontCaption, color: muted)),
              ),
            const SizedBox(height: AppTokens.spaceXs),
            Row(
              children: [
                Expanded(
                  child: Text(L10n.linkedAlarm,
                      style: const TextStyle(fontSize: AppTokens.fontBody)),
                ),
                GlassSwitch(
                  value: c.alarmEnabled,
                  onChanged: (v) => setState(() => _classes[index] =
                      _editClass(_classes[index], alarmEnabled: v)),
                ),
              ],
            ),
            if (c.alarmEnabled) ...[
              const SizedBox(height: AppTokens.spaceSm),
              _timeChip(
                context,
                label: L10n.alarmTime,
                minutes: c.alarmMinute,
                onPick: (m) => setState(() => _classes[index] =
                    _editClass(_classes[index], alarmMinute: m)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// 可点的颜色圆点：外面加一圈描边，让它看起来是能点的。
  Widget _colorDot(BuildContext context, int index, ShiftClass c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _pickColor(index),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Color(c.color),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTokens.glassBorder(isDark)
                .withValues(alpha: isDark ? 0.30 : 0.85),
            width: 2,
          ),
        ),
      ),
    );
  }

  /// 切换工作/休息。
  ///
  /// 切成休息必须把时间和闹钟一起清掉（走 [_editClass] 的 clear* 通道，
  /// `copyWith` 没有「清成 null」的通道）；切回工作时补一组默认时间，
  /// 否则时间块会以「未设置」出现。
  void _setRest(int index, bool rest) {
    setState(() {
      final cur = _classes[index];
      _classes[index] = rest
          ? _editClass(cur,
              isRest: true,
              clearTimes: true,
              alarmEnabled: false,
              clearAlarmMinute: true)
          : _editClass(cur,
              isRest: false,
              startMinute: cur.startMinute ?? toMinutes(8, 0),
              endMinute: cur.endMinute ?? toMinutes(20, 0));
    });
  }

  /// 开始/结束/闹钟时间都用这个块。
  Widget _timeChip(
    BuildContext context, {
    required String label,
    required int? minutes,
    required ValueChanged<int?> onPick,
  }) {
    return _chipBody(
      context,
      label: label,
      value: minutes == null ? L10n.notSet : formatClock(minutes),
      onTap: () async {
        final now = minutes ?? toMinutes(8, 0);
        final picked = await showGlassTimePicker(
          context,
          initialTime: TimeOfDay(hour: now ~/ 60, minute: now % 60),
        );
        if (picked != null) onPick(picked.hour * 60 + picked.minute);
      },
    );
  }

  /// 结束时间块 —— 与开始时间的唯一区别是「结束可能落在次日」。
  ///
  /// `endMinute` 的域到 2880（24 小时值班 = 480 → 1920），所以：
  /// - 打开选择器必须用**钟面值**（[ShiftClass.endClockMinute]），
  ///   直接用 `endMinute ~/ 60` 会得到 32 点、越出小时滚轮的 0..23；
  /// - 确认时必须把「跨到次日」的那 1440 分钟加回去，否则值班会被静默
  ///   降级成当天结束，日历与闹钟跟着一起错。
  Widget _endTimeChip(
    BuildContext context, {
    required String label,
    required ShiftClass shift,
    required ValueChanged<int> onPick,
  }) {
    return _chipBody(
      context,
      label: label,
      value: _endTimeText(shift),
      onTap: () async {
        final clock = shift.endClockMinute ?? toMinutes(20, 0);
        final picked = await showGlassTimePicker(
          context,
          initialTime: TimeOfDay(hour: clock ~/ 60, minute: clock % 60),
        );
        if (picked == null) return;
        final base = picked.hour * 60 + picked.minute; // 0..1439
        final wasNextDay = shift.endMinute != null && shift.endMinute! >= 1440;
        onPick(base + (wasNextDay ? 1440 : 0));
      },
    );
  }

  /// 时间块的统一外观：可点的圆角玻璃块，标签小字在上、值在下方。
  ///
  /// 外面垫一层透明 [Material]：班次行本身是带底色的 `Container`，
  /// 而水波纹要画在最近的 `Material` 上，否则会被底色盖住。
  Widget _chipBody(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Material(
      color: Colors.transparent,
      child: GlassPressable(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMd, vertical: AppTokens.spaceSm),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppTokens.radiusM),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppTokens.fontSupport, color: muted)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: AppTokens.fontBody,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(Icons.access_time_outlined, size: 18, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 结束时间的副标题：落在次日时补「次日」前缀。
  ///
  /// 1440（即当日 24:00）也满足 [ShiftClass.endsNextDay]，但周期行与日历都
  /// 把它写成 `24:00`（同一时刻的两种写法），这里保持一致 —— 否则同一个
  /// 班次会在班次设置里说「次日00:00」、在周期行里说「24:00」。
  String _endTimeText(ShiftClass c) {
    final e = c.endMinute;
    if (e == null) return L10n.notSet;
    if (e == 1440) return formatClock(1440);
    return c.endsNextDay
        ? '${L10n.nextDay}${formatClock(c.endClockMinute!)}'
        : formatClock(e);
  }

  /// 4) 周期设置：几天一循环，以及每天引用哪个班次。
  Widget _cycleCard(BuildContext context) {
    return GlassTile(
      // 窄屏把卡片内边距收一档，把宽度留给内容（字号不缩，可读性优先）。
      padding: EdgeInsets.all(
          AppLayout.of(context).isNarrow ? AppTokens.spaceMd : AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cycleStepper(context),
          const SizedBox(height: AppTokens.spaceSm),
          ...List.generate(_cycle.length, (i) => _cycleRow(context, i)),
        ],
      ),
    );
  }

  Widget _cycleStepper(BuildContext context) {
    return Row(
      children: [
        Text(L10n.cycleSection,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: AppTokens.fontLead)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_outlined),
          onPressed:
              _cycle.length > 1 ? () => _setCycleLength(_cycle.length - 1) : null,
        ),
        Text('${_cycle.length}${L10n.cycleLengthUnit}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline_outlined),
          onPressed:
              _cycle.length < 60 ? () => _setCycleLength(_cycle.length + 1) : null,
        ),
      ],
    );
  }

  /// 变长时新的一天默认沿用最后一天的班次；变短直接截断。
  void _setCycleLength(int n) {
    if (_classes.isEmpty) return; // 没有班次定义就无从引用
    setState(() {
      if (n > _cycle.length) {
        final tail = _cycle.isEmpty ? 0 : _cycle.last;
        while (_cycle.length < n) {
          _cycle.add(tail);
        }
      } else {
        _cycle.removeRange(n, _cycle.length);
      }
    });
  }

  Widget _cycleRow(BuildContext context, int index) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final timeText = _rangeText(_classes[_cycle[index]]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showTime = cycleRowFitsTime(
            rowWidth: constraints.maxWidth,
            classNames: [for (final c in _classes) c.name],
            timeText: timeText,
          );
          return Row(
            children: [
              SizedBox(
                width: _dayLabelWidth,
                child: Text(L10n.dayN(index + 1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppTokens.fontSupport,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                // 班次多（五六班倒）或屏窄时横向滚动：右侧露出半个 chip
                // 就是「还能滑」的提示。滚动而不是换行 —— 换行会把每一行撑高，
                // 60 天的周期会立刻变得没法看。
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _classes.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                              right: i == _classes.length - 1
                                  ? 0
                                  : AppTokens.spaceSm),
                          child: GlassChoiceChip(
                            key: cycleChipKey(index, i),
                            label: _classes[i].name,
                            color: Color(_classes[i].color),
                            selected: i == _cycle[index],
                            onTap: () => setState(() => _cycle[index] = i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showTime) ...[
                const SizedBox(width: AppTokens.spaceMd),
                Text(timeText,
                    style: TextStyle(
                        fontSize: AppTokens.fontSupport, color: muted)),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 周期行右侧的只读时间，与日历上的显示规则一致。
  String _rangeText(ShiftClass c) {
    if (c.isRest || c.startMinute == null || c.endMinute == null) {
      return L10n.rest;
    }
    var e = c.endMinute!;
    final nextDay = e > 1440 || e < c.startMinute!;
    if (e > 1440) e -= 1440;
    return L10n.timeRange(
        formatClock(c.startMinute!), formatClock(e), nextDay);
  }

  /// 5) 班组设置（可选）—— 默认折叠。
  Widget _crewCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return GlassTile(
      // 窄屏把卡片内边距收一档，把宽度留给内容（字号不缩，可读性优先）。
      padding: EdgeInsets.all(
          AppLayout.of(context).isNarrow ? AppTokens.spaceMd : AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
            onTap: () => setState(() => _crewExpanded = !_crewExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      L10n.crewSettingsOptional,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppTokens.fontLead),
                    ),
                  ),
                  Icon(_crewExpanded
                      ? Icons.expand_less_outlined
                      : Icons.expand_more_outlined),
                ],
              ),
            ),
          ),
          if (_crewExpanded) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Row(
              children: [
                Text(L10n.teamCountN(_teamCount),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppTokens.fontBody)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_outlined),
                  onPressed: _teamCount > 1
                      ? () => _setTeamCount(_teamCount - 1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_outlined),
                  onPressed: _teamCount < 8
                      ? () => _setTeamCount(_teamCount + 1)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceXs),
            ...List.generate(_teamCount, (i) => _crewRow(context, i)),
            Text(L10n.teamHint,
                style: TextStyle(
                    fontSize: AppTokens.fontSupport, color: muted)),
          ],
        ],
      ),
    );
  }

  Widget _crewRow(BuildContext context, int i) {
    final primary = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.55);
    final isOurs = i == _ourTeamIndex;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceMd, AppTokens.spaceXs, AppTokens.spaceSm,
          AppTokens.spaceXs),
      decoration: BoxDecoration(
        color: isOurs ? primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        border: Border.all(
          color: isOurs ? primary : outline,
          width: isOurs ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _teamNameCtrls[i],
                  onChanged: (v) => _teamNames[i] = v,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: L10n.teamName,
                  ),
                  style: TextStyle(
                      fontWeight: isOurs ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              InkWell(
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
                onTap: () => setState(() => _ourTeamIndex = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceMd, vertical: AppTokens.spaceXs),
                  decoration: BoxDecoration(
                    color:
                        isOurs ? primary : primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTokens.radiusS),
                  ),
                  child: Text(
                    isOurs ? L10n.myTeam : L10n.setAsMine,
                    style: TextStyle(
                      fontSize: AppTokens.fontSupport,
                      fontWeight: FontWeight.w700,
                      color: isOurs
                          ? Theme.of(context).colorScheme.onPrimary
                          : primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
            onTap: () => _pickCrewStartDate(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 2, vertical: AppTokens.spaceXs),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, size: 16, color: muted),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(L10n.crewCycleStart,
                      style: TextStyle(
                          fontSize: AppTokens.fontSupport, color: muted)),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(
                    L10n.yearMonthDay(_crewStartDate(i)),
                    style: const TextStyle(
                        fontSize: AppTokens.fontSupport,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCrewStartDate(int i) async {
    final picked = await showGlassDatePicker(
      context,
      initialDate: _crewStartDate(i),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) _setCrewStartDate(i, picked);
  }

  void _setTeamCount(int n) {
    setState(() {
      _teamCount = n;
      while (_teamNames.length < n) {
        _teamNames.add(L10n.defaultTeamName(_teamNames.length));
      }
      if (_teamNames.length > n) {
        _teamNames.removeRange(n, _teamNames.length);
      }
      if (_ourTeamIndex >= n) _ourTeamIndex = n - 1;
      while (_teamOffsets.length < n) {
        _teamOffsets.add(_teamOffsets.length);
      }
      if (_teamOffsets.length > n) {
        _teamOffsets.removeRange(n, _teamOffsets.length);
      }
      _syncTeamNameCtrls();
    });
  }

  /// 6) 跟随法定节假日：打开即变成空白表（无班次、无周期）。
  Widget _followHolidayCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return GlassTile(
      // 窄屏把卡片内边距收一档，把宽度留给内容（字号不缩，可读性优先）。
      padding: EdgeInsets.all(
          AppLayout.of(context).isNarrow ? AppTokens.spaceMd : AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  L10n.followHoliday,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTokens.fontLead),
                ),
              ),
              GlassSwitch(
                value: _followHoliday,
                onChanged: (v) => setState(() {
                  _followHoliday = v;
                  if (v) {
                    // 切到空白表：清空班次与周期，班组收敛为「我」
                    _classes = [];
                    _cycle = [];
                    _syncClassCtrls();
                    _teamCount = 1;
                    _teamNames = [L10n.isEn ? 'Me' : '我'];
                    _ourTeamIndex = 0;
                    _teamOffsets = [];
                    _syncTeamNameCtrls();
                    if (_name.trim().isEmpty ||
                        _name.trim() == L10n.newSchedule) {
                      _name = L10n.holidayScheduleName;
                      _scheduleNameCtrl.text = _name;
                    }
                  } else if (_classes.isEmpty) {
                    // 从空白表切回普通表：恢复默认四班两倒
                    final d = defaultSchedule();
                    _classes = List.of(d.classes);
                    _cycle = List.of(d.cycle);
                    _teamCount = d.teamCount;
                    _teamNames = List.of(d.teamNames);
                    _ourTeamIndex = d.ourTeamIndex;
                    _teamOffsets = List.of(d.teamOffsets);
                    _syncClassCtrls();
                    _syncTeamNameCtrls();
                  }
                }),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            L10n.followHolidayHint,
            style: TextStyle(fontSize: AppTokens.fontSupport, color: muted),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 编辑动作
  // ---------------------------------------------------------------------------

  Future<void> _pickColor(int index) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (context) => GlassPanel(
        solid: true,
        margin: const EdgeInsets.all(AppTokens.spaceMd),
        borderRadius:
            const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                AppTokens.spaceLg, AppTokens.spaceLg, AppTokens.spaceXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.shiftColor,
                  style: const TextStyle(
                      fontSize: AppTokens.fontLead,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                Wrap(
                  spacing: AppTokens.spaceLg,
                  runSpacing: AppTokens.spaceLg,
                  children: _palette.map((c) {
                    final selected = _classes[index].color == c;
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  width: 3)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _classes[index] = _editClass(_classes[index], color: picked));
    }
  }

  void _addClass() {
    setState(() {
      final idx = _classes.length;
      final c = ShiftClass(
        name: L10n.newShiftName,
        color: _palette[idx % _palette.length],
        startMinute: toMinutes(8, 0),
        endMinute: toMinutes(20, 0),
      );
      _classes.add(c);
      _nameCtrls.add(TextEditingController(text: c.name));
      _abbrCtrls.add(TextEditingController());
    });
  }

  Future<void> _deleteClass(int index) async {
    final used = _cycle.where((c) => c == index).length;
    if (used > 0) {
      // 仍被周期引用：直接拦下，不弹确认 —— 这条路本来就删不掉。
      showGlassSnack(
        context,
        L10n.deleteShiftClassInUse.replaceAll('{n}', '$used'),
        icon: Icons.info_outline,
      );
      return;
    }

    // 删除会把周期里比它大的下标整体前移，而时间 / 颜色 / 闹钟配置都不在
    // 周期里，重加一个班次也复原不回来 —— 所以先确认一次。
    final name = _classes[index].name;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) => GlassDialog(
        title: L10n.deleteShiftClassTitle,
        content: Text(L10n.deleteShiftClassContent(name)),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: L10n.cancel,
          ),
          const SizedBox(width: AppTokens.spaceSm),
          GlassActionButton(
            variant: GlassActionVariant.danger,
            onPressed: () => Navigator.pop(dialogContext, true),
            label: L10n.delete,
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _classes.removeAt(index);
      _nameCtrls.removeAt(index).dispose();
      _abbrCtrls.removeAt(index).dispose();
      // 删掉一个定义后，周期里所有比它大的下标整体前移一位
      for (var i = 0; i < _cycle.length; i++) {
        if (_cycle[i] > index) _cycle[i]--;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = _name.trim().isEmpty ? L10n.schedule : _name.trim();
      final anchor = dateOnly(_anchor);
      await ref.read(appRepositoryProvider).saveSchedule(
            scheduleId: widget.scheduleId ??
                ref.read(activeScheduleProvider).valueOrNull?.schedule.id,
            name: name,
            anchorDate: anchor,
            classes: _classes,
            cycle: _cycle,
            makeCurrent: widget.scheduleId == null,
            teamCount: _teamCount,
            teamNames: _teamNames,
            ourTeamIndex: _ourTeamIndex,
            teamOffsets: _teamOffsets,
          );
      final repo = ref.read(appRepositoryProvider);
      // 重排必须用**当前**方案，不能用刚编辑的这套：用户可能编辑的是一套
      // 非当前方案，按它重排会把闹钟排到错的班表上，直到冷启动才自愈。
      final active = await repo.getActiveSchedule();
      if (active != null) {
        await AlarmService.reschedule(
          active,
          await repo.listCustomAlarms(),
          overrides: await repo.listShiftAlarmOverrides(),
        );
      }
      // 返回 true 告知上层「已保存」，由上层弹提示（避免 SnackBar 随页面一起销毁）
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// 直接构造替换一个 [ShiftClass]。
///
/// 不能直接用 `copyWith`：它把可空字段写成 `abbr ?? this.abbr`，没有「清成 null」
/// 的通道，于是「把某天的班次切成休班」时时间永远清不掉。
ShiftClass _editClass(
  ShiftClass c, {
  String? name,
  String? abbr,
  int? startMinute,
  int? endMinute,
  bool clearTimes = false,
  bool? isRest,
  int? color,
  bool? alarmEnabled,
  int? alarmMinute,
  bool clearAlarmMinute = false,
}) {
  return ShiftClass(
    name: name ?? c.name,
    abbr: abbr ?? c.abbr,
    startMinute: clearTimes ? null : (startMinute ?? c.startMinute),
    endMinute: clearTimes ? null : (endMinute ?? c.endMinute),
    isRest: isRest ?? c.isRest,
    color: color ?? c.color,
    alarmEnabled: alarmEnabled ?? c.alarmEnabled,
    alarmMinute: clearAlarmMinute ? null : (alarmMinute ?? c.alarmMinute),
  );
}

/// 周期行里某个 chip 的 Key —— 让测试能精确点到「第几天选哪个班次」。
Key cycleChipKey(int dayIndex, int classIndex) =>
    ValueKey('cycle-chip-$dayIndex-$classIndex');

/// 量一段文字在给定样式下的宽度（不依赖 BuildContext，便于单测）。
double _textWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// 周期行里某个 chip 的宽度（含内边距与色点）。
///
/// 色点只在未选中时画，但这里**始终**把它算进去：宁可估宽一点（于是更早
/// 隐藏时间）也不要估窄 —— 估窄会让 chip 被挤成半个。
double _chipWidth(String label) =>
    AppTokens.spaceMd * 2 +
    8 +
    AppTokens.spaceSm +
    _textWidth(label, const TextStyle(fontSize: AppTokens.fontSupport));

/// 这一行放不放得下右侧的只读时间。
///
/// 时间的宽度是变的：「08:00 – 18:00」与「20:30 – 次日08:00」差近一倍，
/// 而 chip 才是这一行的主要控件。放不下时**隐藏时间**，而不是把 chip 挤成
/// 半个 —— 那看起来像坏了而不是像能滑。时间属于班次定义，上面那张
/// 「班次设置」卡里逐条列着，隐藏不会丢信息。
bool cycleRowFitsTime({
  required double rowWidth,
  required List<String> classNames,
  required String timeText,
}) {
  final chips = classNames.fold<double>(
        0,
        (sum, name) => sum + _chipWidth(name),
      ) +
      AppTokens.spaceSm * (classNames.length - 1).clamp(0, 1 << 30);
  final needed = _dayLabelWidth +
      AppTokens.spaceSm +
      chips +
      AppTokens.spaceMd +
      _textWidth(timeText, const TextStyle(fontSize: AppTokens.fontSupport));
  return needed <= rowWidth;
}

/// 「第 N 天」标签的固定宽度。
const double _dayLabelWidth = 56;
