import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_delete_button.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pickers.dart';
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
  void _setCrewStartDate(int i, DateTime date) {
    final off = daysBetween(dateOnly(date), dateOnly(_anchor));
    setState(() => _teamOffsets[i] = off);
  }

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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    _scheduleHeader(context),
                    const SizedBox(height: 12),
                    if (!_followHoliday) ...[
                      _myCycleStartCard(context),
                      const SizedBox(height: 12),
                      _classesCard(context),
                      const SizedBox(height: 12),
                      _cycleCard(context),
                      const SizedBox(height: 12),
                      _crewCard(context),
                      const SizedBox(height: 12),
                    ],
                    _followHolidayCard(context),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_outlined),
            label: Text(L10n.saveAndReschedule),
          ),
        ),
      ),
    );
  }

  /// 1) 排班名称。
  Widget _scheduleHeader(BuildContext context) {
    return GlassTile(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _scheduleNameCtrl,
        onChanged: (v) => _name = v,
        decoration: glassInputDecoration(context, L10n.scheduleName),
      ),
    );
  }

  /// 2) 我的班组起始日 —— 整页最重要的一项，紧贴名称下方。
  Widget _myCycleStartCard(BuildContext context) {
    return GlassTile(
      padding: const EdgeInsets.all(16),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.today_outlined),
        title: Text(
          L10n.myCycleStart,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(L10n.yearMonthDay(_anchor)),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () async {
          final picked = await showGlassDatePicker(
            context,
            initialDate: _anchor,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) _setMyCycleStart(picked);
        },
      ),
    );
  }

  /// 3) 班次设置：每个班次定义一次，周期里直接引用。
  Widget _classesCard(BuildContext context) {
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.55);
    return GlassTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.shiftClasses,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.shiftClassesHint,
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 10),
          ..._classes.asMap().entries.map((e) => _classRow(context, e.key)),
          const SizedBox(height: 4),
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
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.5);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        border: Border.all(color: outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _pickColor(index),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Color(c.color),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _nameCtrls[index],
                  onChanged: (v) => setState(() =>
                      _classes[index] = _editClass(_classes[index], name: v)),
                  decoration:
                      glassInputDecoration(context, L10n.shiftName, isDense: true),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 46,
                child: TextField(
                  controller: _abbrCtrls[index],
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  onChanged: (v) => setState(() =>
                      _classes[index] = _editClass(_classes[index], abbr: v)),
                  decoration: glassInputDecoration(context, L10n.abbrLabel,
                          isDense: true)
                      .copyWith(counterText: ''),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 4),
              GlassSwitch(
                value: c.isRest,
                onChanged: (v) => setState(() {
                  final cur = _classes[index];
                  _classes[index] = v
                      ? _editClass(cur,
                          isRest: true,
                          clearTimes: true,
                          alarmEnabled: false,
                          clearAlarmMinute: true)
                      : _editClass(cur,
                          isRest: false,
                          startMinute: cur.startMinute ?? toMinutes(8, 0),
                          endMinute: cur.endMinute ?? toMinutes(20, 0));
                }),
              ),
              GlassDeleteButton(onPressed: () => _deleteClass(index)),
            ],
          ),
          if (!c.isRest) ...[
            Row(
              children: [
                Expanded(
                  child: _timeTile(
                    context,
                    label: L10n.start,
                    minutes: c.startMinute,
                    onPick: (m) => setState(() => _classes[index] =
                        _editClass(_classes[index], startMinute: m)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _timeTile(
                    context,
                    label: L10n.end,
                    minutes: c.endMinute,
                    onPick: (m) => setState(() => _classes[index] =
                        _editClass(_classes[index], endMinute: m)),
                  ),
                ),
              ],
            ),
            if (c.crossesMidnight)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(L10n.crossesMidnight,
                    style: TextStyle(fontSize: 11, color: muted)),
              ),
            Row(
              children: [
                Expanded(child: Text(L10n.linkedAlarm)),
                GlassSwitch(
                  value: c.alarmEnabled,
                  onChanged: (v) => setState(() => _classes[index] =
                      _editClass(_classes[index], alarmEnabled: v)),
                ),
              ],
            ),
            if (c.alarmEnabled)
              _timeTile(
                context,
                label: L10n.alarmTime,
                minutes: c.alarmMinute,
                onPick: (m) => setState(() => _classes[index] =
                    _editClass(_classes[index], alarmMinute: m)),
              ),
          ],
        ],
      ),
    );
  }

  /// 开始/结束/闹钟时间都用这个条目。
  ///
  /// 外面垫一层透明 [Material]：班次行本身是带底色的 `Container`，
  /// 而 `ListTile` 的水波纹要画在最近的 `Material` 上，否则会被底色盖住
  /// （framework 会直接断言失败）。
  Widget _timeTile(
    BuildContext context, {
    required String label,
    required int? minutes,
    required ValueChanged<int?> onPick,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(minutes == null ? L10n.notSet : formatClock(minutes)),
        trailing: const Icon(Icons.access_time_outlined),
        onTap: () async {
          final now = minutes ?? toMinutes(8, 0);
          final picked = await showGlassTimePicker(
            context,
            initialTime: TimeOfDay(hour: now ~/ 60, minute: now % 60),
          );
          if (picked != null) onPick(picked.hour * 60 + picked.minute);
        },
      ),
    );
  }

  /// 4) 周期设置：几天一循环，以及每天引用哪个班次。
  Widget _cycleCard(BuildContext context) {
    return GlassTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cycleStepper(context),
          const SizedBox(height: 4),
          ...List.generate(_cycle.length, (i) => _cycleRow(context, i)),
        ],
      ),
    );
  }

  Widget _cycleStepper(BuildContext context) {
    return Row(
      children: [
        Text(L10n.cycleSection,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_outlined),
          onPressed:
              _cycle.length > 1 ? () => _setCycleLength(_cycle.length - 1) : null,
        ),
        Text('${_cycle.length}${L10n.cycleLengthUnit}'),
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
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(L10n.dayN(index + 1),
                style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
              ),
              child: DropdownButton<int>(
                value: _cycle[index],
                isExpanded: true,
                isDense: true,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: _classes.asMap().entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: Color(e.value.color),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(e.value.name,
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    )).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _cycle[index] = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _rangeText(_classes[_cycle[index]]),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
        ],
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
    return '${formatClock(c.startMinute!)} – ${nextDay ? '次日' : ''}${formatClock(e)}';
  }

  /// 5) 班组设置（可选）—— 默认折叠。
  Widget _crewCard(BuildContext context) {
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.55);
    return GlassTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
            onTap: () => setState(() => _crewExpanded = !_crewExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      L10n.crewSettingsOptional,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Text(L10n.teamCountN(_teamCount),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
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
            const SizedBox(height: 4),
            ...List.generate(_teamCount, (i) => _crewRow(context, i)),
            Text(L10n.teamHint, style: TextStyle(fontSize: 12, color: muted)),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
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
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
                onTap: () => setState(() => _ourTeamIndex = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        isOurs ? primary : primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTokens.radiusS),
                  ),
                  child: Text(
                    isOurs ? L10n.myTeam : L10n.setAsMine,
                    style: TextStyle(
                      fontSize: 12,
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
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Text(L10n.crewCycleStart,
                      style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(width: 8),
                  Text(
                    L10n.yearMonthDay(_crewStartDate(i)),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
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
        _teamNames.add(_defaultTeamName(_teamNames.length));
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

  String _defaultTeamName(int i) {
    if (L10n.isEn) return 'Team ${i + 1}';
    const names = ['一', '二', '三', '四', '五', '六', '七', '八'];
    return i < names.length ? '${names[i]}班' : '${i + 1}班';
  }

  /// 6) 跟随法定节假日：打开即变成空白表（无班次、无周期）。
  Widget _followHolidayCard(BuildContext context) {
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.55);
    return GlassTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  L10n.followHoliday,
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
          const SizedBox(height: 8),
          Text(
            L10n.followHolidayHint,
            style: TextStyle(fontSize: 12, color: muted),
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
        margin: const EdgeInsets.all(12),
        borderRadius:
            const BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.shiftColor,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
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

  void _deleteClass(int index) {
    final used = _cycle.where((c) => c == index).length;
    if (used > 0) {
      showGlassSnack(
        context,
        L10n.deleteShiftClassInUse.replaceAll('{n}', '$used'),
        icon: Icons.info_outline,
      );
      return;
    }
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
      await AlarmService.reschedule(
        ShiftSchedule(
          name: name,
          anchorDate: anchor,
          classes: _classes,
          cycle: _cycle,
          teamCount: _teamCount,
          teamNames: _teamNames,
          ourTeamIndex: _ourTeamIndex,
          teamOffsets: _teamOffsets,
        ),
        await repo.listCustomAlarms(),
        overrides: await repo.listShiftAlarmOverrides(),
      );
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
