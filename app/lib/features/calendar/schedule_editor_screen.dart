import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/l10n.dart';
import '../../core/widgets/glass_input.dart';
import '../../core/widgets/glass_pickers.dart';
import '../../core/widgets/glass_switch.dart';
import '../../data/app_repository.dart';
import '../../domain/shift_rotation.dart';
import '../alarm/alarm_service.dart';

/// 排班方案编辑器：方案名 + 锚点日 + 班组设置 + 班次类型。
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
  DateTime _anchor = DateTime.now();
  List<ShiftType> _types = [];
  int _teamCount = 4;
  List<String> _teamNames = ['一班', '二班', '三班', '四班'];
  int _ourTeamIndex = 0;
  List<int> _teamOffsets = [0, 1, 2, 3];
  bool _followHoliday = false; // 空白表：跟随法定节假日，无班次轮换

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
        _anchor = dd.anchorDate;
        _types = List.of(dd.shiftTypes);
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
        _followHoliday = dd.shiftTypes.isEmpty;
      });
    }
  }

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
                _followHolidayCard(context),
                if (!_followHoliday) ...[
                  const SizedBox(height: 12),
                  _teamCard(context),
                  const SizedBox(height: 12),
                  ..._types.asMap().entries
                      .map((e) => _shiftCard(context, e.key, e.value)),
                ],
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

  Widget _scheduleHeader(BuildContext context) {
    return GlassTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: TextEditingController(text: _name),
            onChanged: (v) => _name = v,
            decoration: glassInputDecoration(context, L10n.scheduleName),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(L10n.anchorDate),
            subtitle: Text(L10n.yearMonthDay(_anchor)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final picked = await showGlassDatePicker(
                context,
                initialDate: _anchor,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _anchor = picked);
            },
          ),
          const SizedBox(height: 4),
          Text(
            L10n.anchorHint,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

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
                    // 切到空白表：清空班次，班组收敛为「我」
                    _types = [];
                    _teamCount = 1;
                    _teamNames = [L10n.isEn ? 'Me' : '我'];
                    _ourTeamIndex = 0;
                    _teamOffsets = [];
                    if (_name.trim().isEmpty ||
                        _name.trim() == L10n.newSchedule) {
                      _name = L10n.holidayScheduleName;
                    }
                  } else if (_types.isEmpty) {
                    // 从空白表切回普通表：恢复默认四班两倒
                    final d = defaultSchedule();
                    _types = List.of(d.shiftTypes);
                    _teamCount = d.teamCount;
                    _teamNames = List.of(d.teamNames);
                    _ourTeamIndex = d.ourTeamIndex;
                    _teamOffsets = List.of(d.teamOffsets);
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

  Widget _teamCard(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return GlassTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(L10n.teamSettings,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_outlined),
                onPressed:
                    _teamCount > 2 ? () => _setTeamCount(_teamCount - 1) : null,
              ),
              Text(L10n.teamN(_teamCount)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_outlined),
                onPressed:
                    _teamCount < 8 ? () => _setTeamCount(_teamCount + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_teamCount, (i) {
            final isOurs = i == _ourTeamIndex;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOurs
                    ? primary.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTokens.radiusM),
                border: Border.all(
                  color: isOurs ? primary : outline,
                  width: isOurs ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _teamNames[i]),
                      onChanged: (v) =>
                          setState(() => _teamNames[i] = v),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: L10n.teamName,
                      ),
                      style: TextStyle(
                          fontWeight:
                              isOurs ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(L10n.today, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppTokens.radiusS),
                    ),
                    child: DropdownButton<int>(
                      value: _teamOffsets[i],
                      isDense: true,
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(AppTokens.radiusS),
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      items: _types.asMap().entries.map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                          )).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _teamOffsets[i] = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppTokens.radiusS),
                    onTap: () => setState(() => _ourTeamIndex = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOurs ? primary : primary.withValues(alpha: 0.10),
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
            );
          }),
          Text(
            L10n.teamHint,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
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
      // 锚点日班次下标：与班组数联动
      while (_teamOffsets.length < n) {
        _teamOffsets.add(_teamOffsets.length);
      }
      if (_teamOffsets.length > n) {
        _teamOffsets.removeRange(n, _teamOffsets.length);
      }
      // 天数与班组数联动：增删班次类型
      while (_types.length < n) {
        _types.add(ShiftType(
          order: _types.length,
          name: L10n.restShift,
          isRest: true,
          color: 0xFF9AA0B4,
        ));
      }
      if (_types.length > n) {
        _types.removeRange(n, _types.length);
      }
    });
  }

  String _defaultTeamName(int i) {
    if (L10n.isEn) return 'Team ${i + 1}';
    const names = ['一', '二', '三', '四', '五', '六', '七', '八'];
    return i < names.length ? '${names[i]}班' : '${i + 1}班';
  }

  Widget _shiftCard(BuildContext context, int index, ShiftType t) {
    return GlassTile(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Color(t.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(L10n.dayN(index + 1),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              GlassSwitch(
                value: t.isRest,
                onChanged: (v) => setState(
                  () => _types[index] = t.copyWith(
                    isRest: v,
                    startMinute: v ? null : (t.startMinute ?? toMinutes(8, 0)),
                    endMinute: v ? null : (t.endMinute ?? toMinutes(20, 0)),
                    alarmEnabled: v ? false : t.alarmEnabled,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(t.isRest ? L10n.rest : L10n.work,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: TextEditingController(text: t.name),
            onChanged: (v) => _types[index] = t.copyWith(name: v),
            decoration: glassInputDecoration(context, L10n.shiftName,
                isDense: true),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _palette.map((c) {
              final selected = t.color == c;
              return GestureDetector(
                onTap: () =>
                    setState(() => _types[index] = t.copyWith(color: c)),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: selected
                        ? [BoxShadow(color: Color(c), blurRadius: 8)]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          if (!t.isRest) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _timeTile(
                    context,
                    label: L10n.start,
                    minutes: t.startMinute,
                    onPick: (m) => setState(
                        () => _types[index] = t.copyWith(startMinute: m)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _timeTile(
                    context,
                    label: L10n.end,
                    minutes: t.endMinute,
                    onPick: (m) => setState(
                        () => _types[index] = t.copyWith(endMinute: m)),
                  ),
                ),
              ],
            ),
            if (t.crossesMidnight)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(L10n.crossesMidnight,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5))),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(L10n.linkedAlarm)),
                GlassSwitch(
                  value: t.alarmEnabled,
                  onChanged: (v) => setState(
                      () => _types[index] = t.copyWith(alarmEnabled: v)),
                ),
              ],
            ),
            if (t.alarmEnabled)
              _timeTile(
                context,
                label: L10n.alarmTime,
                minutes: t.alarmMinute,
                onPick: (m) =>
                    setState(() => _types[index] = t.copyWith(alarmMinute: m)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _timeTile(
    BuildContext context, {
    required String label,
    required int? minutes,
    required ValueChanged<int?> onPick,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(minutes == null ? L10n.notSet : _fmt(minutes)),
      trailing: const Icon(Icons.access_time_outlined),
      onTap: () async {
        final now = minutes == null ? toMinutes(8, 0) : minutes;
        final picked = await showGlassTimePicker(
          context,
          initialTime: TimeOfDay(hour: now ~/ 60, minute: now % 60),
        );
        if (picked != null) onPick(picked.hour * 60 + picked.minute);
      },
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final current = ref.read(activeScheduleProvider).valueOrNull;
      final name = _name.trim().isEmpty ? L10n.schedule : _name.trim();
      await ref.read(appRepositoryProvider).saveSchedule(
            scheduleId: widget.scheduleId ?? current?.schedule.id,
            name: name,
            anchorDate: dateOnly(_anchor),
            types: _types,
            makeCurrent: widget.scheduleId == null,
            teamCount: _teamCount,
            teamNames: _teamNames,
            ourTeamIndex: _ourTeamIndex,
            teamOffsets: _teamOffsets,
          );
      final repo = ref.read(appRepositoryProvider);
      final alarms = await repo.listCustomAlarms();
      final overrides = await repo.listShiftAlarmOverrides();
      await AlarmService.reschedule(
        ShiftSchedule(
          name: name,
          anchorDate: dateOnly(_anchor),
          shiftTypes: _types,
          teamCount: _teamCount,
          teamNames: _teamNames,
          ourTeamIndex: _ourTeamIndex,
          teamOffsets: _teamOffsets,
        ),
        alarms,
        overrides: overrides,
      );
      // 返回 true 告知上层「已保存」，由上层弹提示（避免 SnackBar 随页面一起销毁）
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _fmt(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
