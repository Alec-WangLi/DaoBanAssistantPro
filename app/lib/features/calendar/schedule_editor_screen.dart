import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/layout.dart';
import '../../core/l10n.dart';
import '../../core/shift_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_button.dart';
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
import '../../domain/monthly_pattern.dart';
import '../../domain/schedule_template.dart';
import '../../domain/shift_rotation.dart';
import '../alarm/alarm_service.dart';
import 'shift_color_picker.dart';

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

  /// 简称输入框宽度：放得下 2 个汉字（`maxLength: 2`）再加边框内边距。
  ///
  /// 60 是按 **14 号字**算出来的（两个汉字 28，加 `OutlineInputBorder` 的
  /// 内边距）；字号统一到 16 后两个汉字要 32，60 又会把第二个字裁掉 ——
  /// 而只断言文本内容的 widget 测试看不出这种截断，只有真机截图才发现。
  /// 所以字号与这个宽度必须一起改。
  static const double _abbrFieldWidth = 68;

  /// 闹钟名输入框的宽度：与时间块、删除钮并排一行，所以按「够写两个字」定
  /// （「起床」「午休」），比简称框宽一档留出内边距。窄屏上被挤的是**时间块**
  /// （它是 Expanded），名字框与删除钮要保持可点 —— 这条由视觉工装出图核对。
  static const double _alarmLabelFieldWidth = 120;

  /// 班次卡的**身份行**在卡片内宽小于这个值时把「简称」折到第二行。
  ///
  /// 非折叠那一行需要的固定宽度约 148（色点 20 + 两个间距 + 简称框 68 + 删除钮），
  /// 取 160 留一点余量给名称框 —— 名称框是 `Expanded`，能缩到 0，但缩到十几个
  /// 像素等于没法用。200dp 小窗里卡片内宽只有 116，所以那一档必然折行。
  /// 见 [_classIdentityRow]。
  static const double _classRowStackBelow = 160;

  /// **闹钟那一行**折行阈值：名字框（`_alarmLabelFieldWidth` 120）+ 时间块 +
  /// 删除钮，非折叠那一行要两百出头才排得开。见 [_alarmRow]。
  static const double _alarmRowStackBelow = 200;

  /// 底部那颗「保存并重排闹钟」胶囊的高度：M3 的 `FilledButton` 默认值，
  /// 探针在 420×900 与 200×400 两档下量到的都是它。v0.12.0 换成自家的
  /// `GlassButton` 之后**这颗胶囊不再由字体撑高**（`GlassButton` 是定高），
  /// 圆角取它的一半（= `AppTokens.pillOf(_saveButtonHeight)` 的半径）。
  /// **`kFloatingSaveInset = 92` 是按这个 48 推出来的**（16 + 48 + 16 + 12），
  /// 改它必须一并重算那条常量。
  static const double _saveButtonHeight = 48;

  bool _loaded = false;
  bool _notFound = false;
  bool _saving = false;
  String _name = '';
  DateTime _anchor = DateTime.utc(2025, 1, 6);

  /// 班次定义（一个班次只定义一次）。
  List<ShiftClass> _classes = [];

  /// 本方案已设置的按天调整天数（只用于预览上方那行提示）。
  ///
  /// 从 `_load` 读到的领域对象上取，不再查库 —— 覆盖数就在手里，多一次
  /// 数据库往返只会让它在保存后有机会跟界面上的方案对不上。
  int _overrideDays = 0;

  /// 每个班次定义被多少天单独覆盖过：`classId → 覆盖天数`。
  ///
  /// `ShiftSchedule.dayOverrides` 存的是 classes **下标**，而删班次会挪动下标 ——
  /// 所以加载时就把下标换算成 classId（覆盖行在库里引用的也是它），之后无论
  /// 编辑器里怎么增删班次，这份计数都不会错位。
  ///
  /// 用途：删班次 / 打开「跟随法定节假日」这两条路都会让 `saveSchedule` 的
  /// 悬空清理连带删掉覆盖行，得先告诉用户会丢几天。
  Map<int, int> _overridesByClassId = const {};

  /// 周期序列：长度即周期，元素是 [_classes] 的下标。
  List<int> _cycle = [];

  /// 这套方案走**按月锚定**吗（每月 1 号归零）。**模式唯一的判据**。
  ///
  /// 与 [_cycle] **各存各的、切换不丢数据**：切到按月再切回来，周期还在；反之
  /// 亦然。所以别拿「哪一边是空的」去猜模式（详见 `ShiftSchedule` 的类文档）。
  bool _monthly = false;

  /// 按月切法：一段 = 「每月的第 N 天起 → 某个班次」，第一段恒从 1 起。
  List<MonthlySegment> _monthlySegments = [];

  /// 各班组的**段**偏移（单位是段，不是天）。
  List<int> _teamSegOffsets = [];

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
    final repo = ref.read(appRepositoryProvider);
    ShiftSchedule? d;
    if (widget.scheduleId != null) {
      d = await repo.getScheduleDomain(widget.scheduleId!);
    } else {
      final active = await ref.read(activeScheduleProvider.future);
      d = active?.currentDomain;
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
        _overrideDays = dd.dayOverrides.length;
        _overridesByClassId = _countOverridesByClassId(dd);
        _cycle = List.of(dd.cycle);
        _monthly = dd.monthly;
        _monthlySegments = List.of(dd.monthlySegments);
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
        // 段偏移与天偏移同一个补位口径（长度不够就按「相对我们班组」补），
        // 只是取模的单位是**段数**；没有段表时补 0（那时它本来就不参与计算）。
        final segCount = dd.monthlySegments.length;
        _teamSegOffsets = dd.teamSegOffsets.length == dd.teamCount
            ? List.of(dd.teamSegOffsets)
            : [
                for (var i = 0; i < dd.teamCount; i++)
                  segCount == 0 ? 0 : (i - dd.ourTeamIndex) % segCount,
              ];
        _followHoliday = dd.isBlank;
        _syncClassCtrls();
        _syncTeamNameCtrls();
      });
    }
  }

  /// 把领域层的「day → classes 下标」换算成「classId → 天数」。
  ///
  /// 换算是必要的：`dayOverrides` 存下标，而下标会随编辑器里删班次而变动；
  /// 库里的覆盖行引用的却是 classId。换算一次之后这份计数就与编辑器的增删
  /// 无关了。查不到下标的脏数据本来就无效（`saveSchedule` 也不会为它删任何
  /// 东西），直接跳过。
  static Map<int, int> _countOverridesByClassId(ShiftSchedule d) {
    final counts = <int, int>{};
    for (final idx in d.dayOverrides.values) {
      if (idx < 0 || idx >= d.classes.length) continue;
      final id = d.classes[idx].id;
      if (id == null) continue; // 还没落库的班次，不会有覆盖行指着它
      counts.update(id, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
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
      // 正文一直铺到屏幕底、从底部那颗胶囊**下面穿过去**（与首页导航胶囊同一套
      // 写法：`extendBody` + 按钮条自己不画任何底色）。
      //
      // 不加这个的话，正文会停在按钮条的上沿被**硬切**（探针实测：卡片正好在距屏底
      // 80 处齐刷刷断掉），下面露出一整片平色 —— 用户 2026-10-01 真机反馈的
      // 「单独加了一层蒙板挡住」就是它。`bottomNavigationBar` 本身没错，错的是
      // 正文到那里就没了；`extendBody` 让它继续铺下去，而浮动层照旧画在上面。
      extendBody: true,
      appBar: AppBar(
        // 标题按宽度缩小而不是省略（与另外两张整页同一个配方）。
        title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(L10n.editSchedule)),
        actions: [
          IconButton(
            tooltip: L10n.saveAsTemplate,
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _saving ? null : _saveAsTemplate,
          ),
        ],
      ),
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
                      // 底部要给悬浮胶囊让位。旧版这里是 `isShort ? 56 : 100` 的
                      // 分档 —— 那是按「正文到按钮条上沿就被切掉」的老结构算的，
                      // `extendBody` 之后正文伸到屏幕底，56 那一档（小窗）就不够了：
                      // 最后一行正好塞在胶囊底下。
                      //
                      // **叠上系统栏**：按钮条包在 `SafeArea` 里、会跟着手势条一起
                      // 上移，这里的留白必须跟着（见 `kFloatingSaveInset` 的注释）。
                      MediaQuery.paddingOf(context).bottom + kFloatingSaveInset),
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
      // 按钮条**不画底色**（只有那颗胶囊自己），这样正文从下面穿过去时看得见。
      // 位置仍在屏底、仍是浮层：`bottomNavigationBar` 在 Scaffold 的层序里就在
      // 正文之上，只是从这一版起正文不再被它截断。
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
              // 胶囊是**浮在正文上**的 —— 它现在是自家的 `GlassButton`（primary
              // 那一档），自带全 app「悬浮的主操作」同一套投影（主色 @0.30、
              // blur 14、offset (0,4)），所以这里**不再自己叠一层**（两层会叠成
              // 两重影）。高度与圆角仍按 48 的胶囊来（`kFloatingSaveInset` 就是
              // 按这个 48 推的），圆角取高度的一半。
              //
              // 外面套的 `IntrinsicWidth` **是必须的**：`GlassButton` 没有内在宽度
              // （里面那个 `Center` 会一路撑到 `maxWidth`），而这里的约束是**松的**
              // —— 直接放进去它会变成通栏长条（换件后出图量到 388 宽）。套一层
              // `IntrinsicWidth` 让它收缩到内容宽度，仍是「按内容定宽、靠 `Align`
              // 居中悬浮」的一颗胶囊（换件前那颗 `FilledButton` 约 180 宽）。
              // 同一招在 `schedule_screen` 的归档胶囊上也用过。
              //
              // 左右的 `padding` 只有**定宽**的按钮才需要：`GlassButton` 没有内边距
              // （另外三个调用点都是通栏、内容居中，不加也看不出来），而这里收窄成
              // 胶囊之后，文字会贴到两端的圆头上（出图看出来的）。
              child: IntrinsicWidth(
                child: GlassButton(
                  primary: true,
                  height: _saveButtonHeight,
                  radius: _saveButtonHeight / 2,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceXl),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check_outlined),
                  child: Text(L10n.saveAndReschedule),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 用编辑器**当前**（还没保存的）状态拼一份方案。
  ///
  /// 预览条与撞班检查都要它：两者问的都是「照现在这套设置排出来是什么样」，
  /// 各拼一份迟早会有一处漏改。**有意不带 dayOverrides**（按天覆盖）—— 理由
  /// 见 [_previewStrip]。
  ShiftSchedule _draftSchedule() => ShiftSchedule(
        name: _name,
        anchorDate: dateOnly(_anchor),
        classes: _classes,
        cycle: _cycle,
        teamCount: _teamCount,
        teamNames: _teamNames,
        ourTeamIndex: _ourTeamIndex,
        teamOffsets: _teamOffsets,
        monthly: _monthly,
        monthlySegments: _monthlySegments,
        teamSegOffsets: _teamSegOffsets,
      );

  /// 0) 未来 14 天预览：改任何设置都能立刻看出对不对。
  ///
  /// 用 [_anchor] 而不是 [_myCrewStart]：`anchorDate` 才是真正持久化的字段，
  /// 这里要预览的就是保存后日历会显示的东西。
  Widget _previewStrip(BuildContext context) {
    // **有意不传 dayOverrides**：预览要回答的是「按这套规则未来 14 天是什么班」。
    // 叠上按天覆盖之后，用户改周期就看不出规则本身的变化了，预览会失去意义。
    // 代价是它跟日历上看到的不一致 —— 所以下面在有覆盖时给一行提示。
    final schedule = _draftSchedule();
    final today = dateOnly(DateTime.now());
    final muted = AppTokens.inkMuted(context);

    return GlassTile(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 预览不叠按天覆盖（见方法开头），跟日历不一致时得说清楚，否则
          // 用户会以为自己的调整丢了。
          if (_overrideDays > 0) ...[
            Text(
              L10n.previewHasOverrides(_overrideDays),
              key: const Key('editor-override-hint'),
              style: AppTokens.labelSecondary.copyWith(color: muted),
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
          // 基线是 12/w700，microStrong 精确匹配（12 档只有它有 w700）
          Text(L10n.previewNext14, style: AppTokens.microStrong),
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
        // 单行：窄格子里 `12/25` 这种 5 字符日期换行会把两行的高度撑破。
        // **按可用宽度等比缩小而不是省略**（设计 §6.5）：它是定尺的点阵，
        // 与日历格子同一条规矩 —— 折行会撑破，省略会吃掉字。
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('${date.month}/${date.day}',
              maxLines: 1,
              style: AppTokens.microText.copyWith(color: muted)),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceSm, vertical: AppTokens.gapHair),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              s?.shortLabel ?? '—',
              maxLines: 1,
              style: AppTokens.microStrong.copyWith(
                  // 底色是班次色 16% 的淡染，字得按它算可读版本，不能直接用班次色
                  // （橙 `#FF9F0A` 这类浅色压上去几乎看不见）。
                  color: AppTokens.inkFor(
                      color,
                      Color.alphaBlend(color.withValues(alpha: 0.16),
                          Theme.of(context).colorScheme.surface))),
            ),
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
    final muted = AppTokens.inkMuted(context);
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
          // 按月模式**不显示**这一行：按月不读基准日（每月 1 号恒等于第一段），
          // 摆一个改不动结果的日期在那儿，就是让用户在界面上操作一个不生效的值。
          if (!_monthly) ..._myCycleStartRow(context, muted),
        ],
      ),
    );
  }

  /// 顶部那张卡的第二行：「我这组从这个周期开始」。**只有周期模式用得上。**
  List<Widget> _myCycleStartRow(BuildContext context, Color muted) => [
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
                AppIcon(Icons.today_outlined,
                    size: AppTokens.iconMd,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: AppTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.myCycleStart, style: AppTokens.titleStrong),
                      const SizedBox(height: AppTokens.spaceXs),
                      Text(
                        L10n.yearMonthDay(_myCrewStart),
                        style: AppTokens.rowSecondary.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                AppIcon(Icons.edit_outlined,
                    size: AppTokens.iconMd, color: muted),
              ],
            ),
          ),
        ),
      ];

  /// 3) 班次设置：每个班次定义一次，周期里直接引用。
  Widget _classesCard(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
    return GlassTile(
      // 窄屏把卡片内边距收一档，把宽度留给内容（字号不缩，可读性优先）。
      padding: EdgeInsets.all(
          AppLayout.of(context).isNarrow ? AppTokens.spaceMd : AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.shiftClasses,
            style: AppTokens.titleStrong,
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            L10n.shiftClassesHint,
            style: AppTokens.rowSecondary.copyWith(color: muted),
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
    final muted = AppTokens.inkMuted(context);
    // 响铃落在哪天是「算」出来的、看不出来（00:00 上班 + 23:00 响铃 = **前一天**
    // 晚上；16:30–次日 00:30 的 00:15 = **次日**，见 `alarmDayAnchor`），
    // 所以下面既改钟点的写法、又补一行
    // 小字：用户反馈里问的正是「这 23:00 到底是哪天」。
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
          // 身份行：色点（点一下改色）· 名称 · 简称 · 删除。
          // 窄到放不下时把「简称」折到第二行 —— 见 [_classIdentityRow]。
          _classIdentityRow(context, index, c),
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
                // 13 档最重的角色是 w600，分段器标签原本就是 w700：选中态只改
                // 色不改重，字重是控件自己的标签强调，按 spec 走 copyWith。
                style: AppTokens.labelSecondary.copyWith(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : muted,
                ).copyWith(fontWeight: FontWeight.w700),
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
                    style: AppTokens.microText.copyWith(color: muted)),
              ),
            const SizedBox(height: AppTokens.spaceXs),
            Row(
              children: [
                Expanded(
                  child: Text(L10n.linkedAlarm,
                      style: AppTokens.rowPrimary),
                ),
                GlassSwitch(
                  key: Key('shift-alarm-switch-$index'),
                  value: c.alarmEnabled,
                  onChanged: (v) => setState(() => _classes[index] =
                      _editClass(_classes[index], alarmEnabled: v)),
                ),
              ],
            ),
            if (c.alarmEnabled) ...[
              const SizedBox(height: AppTokens.spaceSm),
              for (var k = 0; k < c.alarms.length; k++)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: _alarmRow(context, index, c, k),
                ),
              // 不落在班次当天的小字：整组给一句就够 —— 它点的是**哪一条不在当天**，
              // 不是某一条的正文；多条各给一句会重复成一片。
              if (c.alarms.any((a) => _alarmDayLabel(c, a) != null))
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Text(
                    L10n.alarmDayHint(
                        formatClock(c.startMinute!),
                        _alarmDayLabel(
                            c,
                            c.alarms.firstWhere(
                                (a) => _alarmDayLabel(c, a) != null))!),
                    style: AppTokens.microText.copyWith(color: muted),
                  ),
                )
              else if (c.startMinute == null && c.alarms.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Text(L10n.alarmNoStartHint,
                      style: AppTokens.microText.copyWith(color: muted)),
                ),
              // 到上限就**收掉按钮**、换一行说明：设计语言里没有「禁用态」，
              // 一颗点了没反应的按钮比没有按钮更让人困惑。
              if (c.alarms.length < maxAlarmsPerShift)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GlassActionButton(
                      variant: GlassActionVariant.secondary,
                      icon: const AppIcon(Icons.add_outlined),
                      label: L10n.addAlarm,
                      onPressed: () => setState(() {
                        _classes[index] =
                            _editClass(_classes[index], alarms: [
                          ...c.alarms,
                          // 新的一条默认排在上一条之后一小时；第一条落到 08:00
                          // （与 `_timeChip` 没设过时的缺省一致）。
                          ShiftAlarm(
                              minute: c.alarms.isEmpty
                                  ? toMinutes(8, 0)
                                  : ((c.alarms.last.minute + 60) % 1440)),
                        ]);
                      }),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Text(L10n.alarmLimitReached,
                      style: AppTokens.microText.copyWith(color: muted)),
                ),
            ],
          ],
        ],
      ),
    );
  }

  /// 可点的颜色圆点：外面加一圈描边，让它看起来是能点的。
  /// 班次卡的身份行：色点 · 名称 · 简称 · 删除。
  ///
  /// **窄到放不下时把「简称」折到第二行。** 色点(20) + 名称 + 简称框(68) + 删除钮
  /// 那三样固定宽度加起来约 148，而 200 宽的小窗里卡片内宽只有 116 —— 不折行就是
  /// 一条溢出的横条（工装在小窗那一档当场报 32px）。
  ///
  /// 降级顺序照 v0.11.12 那条「折行 > 按宽缩小 > 换短串」：**折行优先**。收缩简称
  /// 框到放不下两个汉字，等于把用户自己输的字吃掉，比折行糟。
  ///
  /// 这一处是 v0.11.15 加「按月」那一屏时**工装抓出来的既有缺陷**：之前没有任何
  /// 一屏在 400 高的窗口里构建到这张卡（上面两张卡正好占满），所以它从没现形过。
  Widget _classIdentityRow(BuildContext context, int index, ShiftClass c) {
    final nameField = TextField(
      controller: _nameCtrls[index],
      onChanged: (v) => setState(
          () => _classes[index] = _editClass(_classes[index], name: v)),
      decoration: glassInputDecoration(context, L10n.shiftName, isDense: true),
    );
    final abbrField = SizedBox(
      width: _abbrFieldWidth,
      child: TextField(
        controller: _abbrCtrls[index],
        maxLength: 2,
        textAlign: TextAlign.center,
        onChanged: (v) => setState(
            () => _classes[index] = _editClass(_classes[index], abbr: v)),
        decoration: glassInputDecoration(context, L10n.abbrLabel, isDense: true)
            .copyWith(counterText: ''),
      ),
    );
    final dot = _colorDot(context, index, c);
    final del = GlassDeleteButton(
      compact: true,
      onPressed: () => _deleteClass(index),
    );

    return LayoutBuilder(builder: (context, cons) {
      if (cons.maxWidth >= _classRowStackBelow) {
        return Row(
          children: [
            dot,
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(child: nameField),
            const SizedBox(width: AppTokens.spaceSm),
            abbrField,
            const SizedBox(width: AppTokens.spaceXs),
            del,
          ],
        );
      }
      return Column(
        children: [
          Row(
            children: [
              dot,
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(child: nameField),
              const SizedBox(width: AppTokens.spaceXs),
              del,
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Align(alignment: Alignment.centerRight, child: abbrField),
        ],
      );
    });
  }

  /// 一条联动闹钟那一行：时间块 · 名字框 · 删除。
  ///
  /// **窄到放不下时把名字框折到第二行** —— 与 [_classIdentityRow] 同一条降级顺序
  /// （折行优先）。名字框写死 [_alarmLabelFieldWidth]、删除钮又不能压，200 宽的小窗
  /// 里卡片内宽只有 116，这一行不折就是一条溢出的横条（工装报 52px）。
  Widget _alarmRow(BuildContext context, int index, ShiftClass c, int k) {
    final chip = Expanded(
      child: _timeChip(
        context,
        label: L10n.alarmTime,
        minutes: c.alarms[k].minute,
        // 不落在班次当天的那两档都带日前缀（「前一天 23:00」/
        // 「次日 00:15」）—— 只写钟点会被读成班次当天。
        valueText: _alarmDayLabel(c, c.alarms[k]),
        onPick: (m) {
          // `_timeChip` 的 onPick 类型是可空 int（没选就调不到
          // 这里），但闹钟必须有个钟点，所以空值直接忽略。
          if (m == null) return;
          setState(() => _classes[index] =
              _editClass(_classes[index], alarms: [
                for (var j = 0; j < c.alarms.length; j++)
                  j == k
                      ? ShiftAlarm(minute: m, label: c.alarms[j].label)
                      : c.alarms[j],
              ]));
        },
      ),
    );
    final labelField = SizedBox(
      width: _alarmLabelFieldWidth,
      child: _AlarmLabelField(
        key: Key('shift-alarm-label-$index-$k'),
        label: c.alarms[k].label,
        onChanged: (v) => setState(
            () => _classes[index] = _editClass(_classes[index], alarms: [
                  for (var j = 0; j < c.alarms.length; j++)
                    j == k
                        ? ShiftAlarm(minute: c.alarms[j].minute, label: v)
                        : c.alarms[j],
                ])),
      ),
    );
    final del = GlassDeleteButton(
      compact: true,
      onPressed: () => setState(() => _classes[index] =
          _editClass(_classes[index], alarms: [
            for (var j = 0; j < c.alarms.length; j++)
              if (j != k) c.alarms[j],
          ])),
    );

    return LayoutBuilder(builder: (context, cons) {
      final rowKey = Key('shift-alarm-row-$index-$k');
      if (cons.maxWidth >= _alarmRowStackBelow) {
        return Row(key: rowKey, children: [
          chip,
          const SizedBox(width: AppTokens.spaceSm),
          labelField,
          const SizedBox(width: AppTokens.spaceXs),
          del,
        ]);
      }
      return Column(children: [
        Row(key: rowKey, children: [
          chip,
          const SizedBox(width: AppTokens.spaceXs),
          del,
        ]),
        const SizedBox(height: AppTokens.spaceXs),
        Align(alignment: Alignment.centerRight, child: labelField),
      ]);
    });
  }

  Widget _colorDot(BuildContext context, int index, ShiftClass c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _pickColor(index),
      child: Container(
        key: ValueKey('shift-color-dot-$index'),
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
              clearAlarms: true)
          : _editClass(cur,
              isRest: false,
              startMinute: cur.startMinute ?? toMinutes(8, 0),
              endMinute: cur.endMinute ?? toMinutes(20, 0));
    });
  }

  /// 开始/结束/闹钟时间都用这个块。
  ///
  /// [valueText] 覆盖默认的钟点显示 —— 响铃时间落在上班前一天时要写成
  /// 「前一天 23:00」（见 `ShiftClass.alarmPreviousDay`），钟点本身还是 [minutes]。
  Widget _timeChip(
    BuildContext context, {
    required String label,
    required int? minutes,
    required ValueChanged<int?> onPick,
    String? valueText,
  }) {
    return _chipBody(
      context,
      label: label,
      value: valueText ??
          (minutes == null ? L10n.notSet : formatClock(minutes)),
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
    final muted = AppTokens.inkMuted(context);
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
                      // 标签**单行、按宽缩小**。
                      //
                      // ⚠️ 这里**不要**写 `maxLines: 2` 假装「先折两行」：`FittedBox`
                      // 给子件的是无界宽约束，段落永远只排一行，那句「折行」是死代码
                      // （独立审查指出）。走这个件的标签本来就是单字词
                      // （开始 / 结束 / 响铃），缩才是对的那一档。
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(label,
                            maxLines: 1,
                            style:
                                AppTokens.rowSecondary.copyWith(color: muted)),
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value,
                            maxLines: 1, style: AppTokens.labelStrong),
                      ),
                    ],
                  ),
                ),
                AppIcon(Icons.access_time_outlined,
                    size: AppTokens.iconMd, color: muted),
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
          // 「日子怎么数」的二选一：连续周期，还是每月 1 号归零。
          //
          // **不把「跟随法定节假日」并进这个分段器**：那一条是破坏性的（切过去
          // 会清空班次定义与全部按天覆盖，所以现在才要弹确认框 + 单独一张卡 +
          // 一个开关）。把破坏性选项混进日常切换里，等于把「问一次」的机会抹掉。
          GlassSegment(
            count: 2,
            selectedIndex: _monthly ? 1 : 0,
            onSelected: (i) => _setMonthly(i == 1),
            itemBuilder: (i, selected) => Text(
              i == 0 ? L10n.scheduleModeCycle : L10n.scheduleModeMonthly,
              // 与「我的」页那个主题分段器同一套写法：未选中 w500、选中 w700。
              style: AppTokens.labelSecondary.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (_monthly) ..._monthlyBody(context) else ..._cycleBody(context),
        ],
      ),
    );
  }

  /// 按周期那一支（原本就是这张卡的全部内容）。
  List<Widget> _cycleBody(BuildContext context) => [
        _cycleStepper(context),
        const SizedBox(height: AppTokens.spaceSm),
        ...List.generate(_cycle.length, (i) => _cycleRow(context, i)),
        ..._crewClashNotice(context),
      ];

  /// 按月那一支：一个小标题 + 段列表 + 「添加一段」。
  List<Widget> _monthlyBody(BuildContext context) {
    return [
      Row(
        children: [
          Text(L10n.monthlySection, style: AppTokens.titleStrong),
          const Spacer(),
          Text(L10n.monthlySegmentCount(_monthlySegments.length),
              style: AppTokens.labelStrong),
        ],
      ),
      const SizedBox(height: AppTokens.spaceXs),
      ...List.generate(_monthlySegments.length, (i) => _monthRow(context, i)),
      GlassPressable(
        child: ListTile(
          key: const Key('month-add-segment'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          horizontalTitleGap: AppTokens.gapIconText,
          leading: AppIcon(Icons.add_circle_outline_outlined,
              size: AppTokens.iconMd, color: Theme.of(context).colorScheme.primary),
          title: Text(L10n.monthlyAddSegment, style: AppTokens.rowPrimary),
          // 最后一段已经能开到 31 号时，再加一段就只能挤在 31 号那天 —— 收掉按钮
          // 比加出一段「从 31 号起、到月底」的摆设好。
          onTap: _monthlySegments.isEmpty ||
                  _monthlySegments.last.startDay >= 31
              ? null
              : _addMonthSegment,
        ),
      ),
      ..._crewClashNotice(context),
    ];
  }

  /// 切「按周期 / 按月」。**两边各存各的，切换不丢数据**，只是换一个生效。
  void _setMonthly(bool v) {
    setState(() {
      _monthly = v;
      if (v) _seedMonthlyIfEmpty();
    });
  }

  /// 段表为空时种一套起步切法：**按班组数种段**、均分 31 天，第 i 段指向第 i 个
  /// 班次定义，并把各组的段偏移设成 0..n-1。
  ///
  /// 为什么不只种一段：班组数 > 1 时「N 个班组抢一段」必然撞班，用户一进来就看到
  /// 撞班提示 —— 一个刚切过来就报错的初体验。按班组数种则天然不撞，而且班组数 = 1
  /// 时正好退化成 `[(1, 0)]`（一整月一个班次），与 spec §6.2 写的是同一个意图。
  ///
  /// **只在空的时候种**：否则会把用户上一次切过来时排好的段表冲掉（那也是「切换
  /// 不丢数据」这条约定的一部分）。
  void _seedMonthlyIfEmpty() {
    if (_monthlySegments.isNotEmpty || _classes.isEmpty) return;
    _monthlySegments = [
      for (final s in defaultMonthlySegments(_teamCount))
        MonthlySegment(
          startDay: s.startDay,
          // 班次定义比班组还少时绕回来用 —— 那种配置本来就排不开（同一天
          // 必有两个班组上同一个班），界面上会当场报撞班，比留一段「没有班次」
          // 的空段好：空段是不报错的。
          classIndex: s.classIndex % _classes.length,
        ),
    ];
    _teamSegOffsets = [for (var i = 0; i < _teamCount; i++) i];
  }

  /// 加一段：接在最后一段之后，班次沿用最后一段的（与周期「变长时沿用最后一天」
  /// 同一条手感）。
  void _addMonthSegment() {
    if (_monthlySegments.isEmpty) return;
    setState(() {
      final last = _monthlySegments.last;
      final next = last.startDay + 1;
      if (next > 31) return;
      _monthlySegments.add(
          MonthlySegment(startDay: next, classIndex: last.classIndex));
    });
  }

  /// 删一段 = **把它并进上一段**。
  ///
  /// 这是唯一能保持「不覆盖出现空档」的删法：段只带起始日、结束日由下一段的起始日
  /// 决定，所以删掉中间那一段之后，它的日子自然归上一段。第一段删不了 —— 它恒从
  /// 1 日起，删了就没有「每月 1 号」这个锚了（所以第一行不给删除键）。
  Future<void> _deleteMonthSegment(int index) async {
    if (index <= 0 || index >= _monthlySegments.length) return;
    final day = _monthlySegments[index].startDay;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: L10n.monthlyDeleteSegmentTitle,
        content: Text(L10n.monthlyDeleteSegmentContent(day)),
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
    if (ok != true || !mounted) return;
    setState(() => _monthlySegments.removeAt(index));
  }

  /// 改某一段的起始日。**只列合法的日号**：要比上一段大、又要给后面的段留位置。
  Future<void> _pickMonthStartDay(int index) async {
    if (index <= 0 || index >= _monthlySegments.length) return;
    final min = _monthlySegments[index - 1].startDay + 1;
    // 后面还有 `n - 1 - index` 段，每段至少要占一天，所以这一段最大到
    // `31 - 后面几段`。
    final max = 31 - (_monthlySegments.length - 1 - index);
    if (min > max) return;
    final picked = await showGlassOptionPicker<int>(
      context,
      title: L10n.monthlySection,
      options: [for (var d = min; d <= max; d++) d],
      labelOf: L10n.monthlyFromDay,
      selected: _monthlySegments[index].startDay,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _monthlySegments[index] = MonthlySegment(
        startDay: picked,
        classIndex: _monthlySegments[index].classIndex,
      );
    });
  }

  /// 按月段列表的一行：左边是可点的「每月第 N 天起」，中间是班次胶囊，右边删除。
  Widget _monthRow(BuildContext context, int index) {
    final muted = AppTokens.inkMuted(context);
    final seg = _monthlySegments[index];
    final classIndex =
        seg.classIndex >= 0 && seg.classIndex < _classes.length ? seg.classIndex : -1;
    final timeText = classIndex < 0 ? '' : _rangeText(_classes[classIndex]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showTime = classIndex >= 0 &&
              cycleRowFitsTime(
                rowWidth: constraints.maxWidth,
                classNames: [for (final c in _classes) c.name],
                timeText: timeText,
              );
          return Row(
            children: [
              // 第一段固定从 1 日起，不给点（点开也只有 1 这一个选项）。
              Expanded(
                flex: 3,
                child: InkWell(
                  key: monthRowDayKey(index),
                  borderRadius: BorderRadius.circular(AppTokens.radiusS),
                  onTap: index == 0 ? null : () => _pickMonthStartDay(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.spaceXs),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(L10n.monthlyFromDay(seg.startDay),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTokens.labelSecondary),
                        ),
                        if (index > 0) ...[
                          const SizedBox(width: AppTokens.spaceXs),
                          AppIcon(Icons.edit_outlined,
                              size: AppTokens.iconSm, color: muted),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                flex: 5,
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
                            selected: i == seg.classIndex,
                            onTap: () => setState(() {
                              _monthlySegments[index] = MonthlySegment(
                                startDay: seg.startDay,
                                classIndex: i,
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (classIndex >= 0 && showTime) ...[
                const SizedBox(width: AppTokens.spaceMd),
                Text(timeText,
                    style: AppTokens.rowSecondary.copyWith(color: muted)),
              ],
              // 第一行不给删除键 —— 第一段恒从 1 日起，删了就没有「1 号」了。
              if (index > 0)
                GlassDeleteButton(
                  key: monthRowDeleteKey(index),
                  compact: true,
                  onPressed: () => _deleteMonthSegment(index),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _cycleStepper(BuildContext context) {
    return Row(
      children: [
        Text(L10n.cycleSection, style: AppTokens.titleStrong),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_outlined),
          onPressed:
              _cycle.length > 1 ? () => _setCycleLength(_cycle.length - 1) : null,
        ),
        Text('${_cycle.length}${L10n.cycleLengthUnit}',
            // 基线是裸 TextStyle(fontWeight: w600)（字号随主题 = 14）。
            // 14 档没有 w600，取最接近的 labelStrong —— +100 而非精确。
            style: AppTokens.labelStrong),
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

  /// 撞班提示 + 一键均分；没有撞班就什么都不出现。
  ///
  /// 挂在**周期设置**这张卡里、而不是「班组设置」那张：撞班的起因是周期长度，
  /// 用户改完长度人就在这儿；而班组设置默认是**折叠**的，提示跟着一起藏起来
  /// 就等于没有（2026-09-21 那位用户就是这么撞了才发现，还以为是 App 的 bug）。
  ///
  /// 只举撞得最多的一对做例子：全部都列出来在卡片里放不下，也没必要。
  List<Widget> _crewClashNotice(BuildContext context) {
    final clashes = crewClashes(_draftSchedule());
    if (clashes.isEmpty) return const [];

    // 按月那一支**连 `days` 都不算**：四年扫描按当日号数去重得到的是「各种月长的
    // 并集」，那个数字说不清是哪个月里的几天（spec §5.2）—— 报出来是个偏大的假数。
    final days = _monthly ? 0 : clashes.map((c) => c.cycleDay).toSet().length;
    final perPair = <(int, int), int>{};
    for (final c in clashes) {
      perPair[(c.teamA, c.teamB)] = (perPair[(c.teamA, c.teamB)] ?? 0) + 1;
    }
    final top = perPair.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    final muted = AppTokens.inkMuted(context);
    // 动作文字走 inkFor 而不是裸主色：主色压在这张卡上实测 4.61:1，只是刚好过线，
    // 换个主色调就可能掉下去（全 app 的彩色文字都走这条）。
    final action = AppTokens.inkFor(
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.surface);

    return [
      const SizedBox(height: AppTokens.spaceSm),
      Text(
        _monthly
            ? L10n.crewClashHintMonthly(_teamNames[top.$1], _teamNames[top.$2])
            : L10n.crewClashHint(days, _teamNames[top.$1], _teamNames[top.$2]),
        key: const Key('editor-crew-clash-hint'),
        style: AppTokens.rowSecondary.copyWith(color: muted),
      ),
      const SizedBox(height: AppTokens.spaceXs),
      const Divider(height: 1),
      GlassPressable(
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          horizontalTitleGap: AppTokens.gapIconText,
          leading: AppIcon(Icons.restart_alt,
              size: AppTokens.iconMd, color: action),
          title: Text(
            _monthly ? L10n.evenCrewSegments : L10n.evenCrewStarts,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTokens.rowSecondary.copyWith(color: action),
          ),
          onTap: _evenCrewStarts,
        ),
      ),
    ];
  }

  /// 把各组按**当前模式的单位**均分 —— **我们班组原地不动**。
  ///
  /// 均分是为了让别人不再和自己撞班，顺手把用户自己的错位挪走是不可接受的
  /// （他的班次会跟着整体平移）。所以整组一起平移，保持「我」那一项不变。
  ///
  /// 按月模式把 `n` 传**段数**、写回 `_teamSegOffsets` —— `evenTeamOffsets` 的算式
  /// 两边同形（第 i 组落在 `i × n ÷ 班组数` 处），只是单位换成了段。
  void _evenCrewStarts() {
    if (_monthly) {
      final n = _monthlySegments.length;
      if (n == 0) return;
      final ours = _ourTeamIndex < _teamSegOffsets.length
          ? _teamSegOffsets[_ourTeamIndex]
          : 0;
      final even = evenTeamOffsets(n, _teamCount,
          keepIndex: _ourTeamIndex, keepOffset: ours);
      if (even.length != _teamSegOffsets.length) return; // 理论上不会发生
      setState(() {
        for (var i = 0; i < even.length; i++) {
          // **要取模**：`evenTeamOffsets` 是「保住我们班组那一格、整组一起平移」，
          // 平移量一为负（我们的偏移比均分给它的那一格小）就会算出负数或 ≥ 段数
          // 的值。段偏移的单位是段，落回 0..段数-1 才是同一个旋转 —— 不取模的话
          // 班组行会显示「从第 -1 段开始」/「从第 4 段开始」而总共只有 3 段
          // （班次算出来是对的，只有数字是废话）。Dart 的 `%` 对正除数恒非负。
          _teamSegOffsets[i] = even[i] % n;
        }
      });
      return;
    }
    final ours = _ourTeamIndex < _teamOffsets.length
        ? _teamOffsets[_ourTeamIndex]
        : 0;
    final even = evenTeamOffsets(_cycle.length, _teamCount,
        keepIndex: _ourTeamIndex, keepOffset: ours);
    if (even.length != _teamOffsets.length) return; // 理论上不会发生
    setState(() {
      for (var i = 0; i < even.length; i++) {
        _teamOffsets[i] = even[i];
      }
    });
  }

  Widget _cycleRow(BuildContext context, int index) {
    final muted = AppTokens.inkMuted(context);
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
                    style: AppTokens.labelSecondary),
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
                    style: AppTokens.rowSecondary.copyWith(color: muted)),
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
    final muted = AppTokens.inkMuted(context);
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
                      style: AppTokens.titleStrong,
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
                    // 基线就是 14/w700，labelStrong 精确匹配
                    style: AppTokens.labelStrong),
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
            Text(_monthly ? L10n.monthlyCrewHint : L10n.teamHint,
                style: AppTokens.rowSecondary.copyWith(color: muted)),
          ],
        ],
      ),
    );
  }

  Widget _crewRow(BuildContext context, int i) {
    final primary = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final muted = AppTokens.inkMuted(context);
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
                  style: AppTokens.titleStrong
                      .copyWith(fontWeight: isOurs ? FontWeight.w700 : FontWeight.w500),
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
                    // 可点的 chip 按钮标签，原本就是 w700（比同行的说明文字重），
                    // 13 档最重只到 w600，按 spec 的「角色内个别变化」走 copyWith。
                    style: AppTokens.labelSecondary.copyWith(
                      color: isOurs
                          ? Theme.of(context).colorScheme.onPrimary
                          : primary,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          // 第二行：周期模式给「周期起始日」，按月模式给「从第几段入场」——
          // 按月不读基准日，摆一个日期在那儿就是让用户操作一个不生效的值。
          if (_monthly)
            InkWell(
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
              onTap: () => _pickCrewSegmentStart(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.gapHair, vertical: AppTokens.spaceXs),
                child: Row(
                  children: [
                    AppIcon(Icons.format_list_numbered,
                        size: AppTokens.iconSm, color: muted),
                    const SizedBox(width: AppTokens.spaceSm),
                    Text(
                      L10n.crewSegmentStart(
                          (i < _teamSegOffsets.length ? _teamSegOffsets[i] : 0) +
                              1),
                      style: AppTokens.labelSecondary,
                    ),
                  ],
                ),
              ),
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
              onTap: () => _pickCrewStartDate(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.gapHair, vertical: AppTokens.spaceXs),
                child: Row(
                  children: [
                    AppIcon(Icons.event_outlined,
                        size: AppTokens.iconSm, color: muted),
                    const SizedBox(width: AppTokens.spaceSm),
                    Text(L10n.crewCycleStart,
                        style: AppTokens.rowSecondary.copyWith(color: muted)),
                    const SizedBox(width: AppTokens.spaceSm),
                    Text(
                      L10n.yearMonthDay(_crewStartDate(i)),
                      style: AppTokens.labelSecondary,
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

  /// 按月模式：改某个班组**从第几段入场**（段序 1 起，界面上写给人看）。
  ///
  /// 存的是 0 起的下标（`teamSegOffsets`），选项里 +1 显示。
  Future<void> _pickCrewSegmentStart(int i) async {
    final n = _monthlySegments.length;
    if (n == 0) return;
    final picked = await showGlassOptionPicker<int>(
      context,
      title: L10n.monthlySection,
      options: [for (var k = 0; k < n; k++) k],
      labelOf: (k) => L10n.crewSegmentStart(k + 1),
      selected: i < _teamSegOffsets.length ? _teamSegOffsets[i] : 0,
    );
    if (picked == null || !mounted) return;
    setState(() {
      while (_teamSegOffsets.length <= i) {
        _teamSegOffsets.add(0);
      }
      _teamSegOffsets[i] = picked;
    });
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
      // 段偏移跟着班组数一起长/缩（它与 `_teamOffsets` 长度恒等于 teamCount）。
      while (_teamSegOffsets.length < n) {
        _teamSegOffsets.add(_teamSegOffsets.length);
      }
      if (_teamSegOffsets.length > n) {
        _teamSegOffsets.removeRange(n, _teamSegOffsets.length);
      }
      _syncTeamNameCtrls();
    });
  }

  /// 6) 跟随法定节假日：打开即变成空白表（无班次、无周期）。
  Widget _followHolidayCard(BuildContext context) {
    final muted = AppTokens.inkMuted(context);
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
                  style: AppTokens.titleStrong,
                ),
              ),
              GlassSwitch(
                value: _followHoliday,
                onChanged: _setFollowHoliday,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            L10n.followHolidayHint,
            style: AppTokens.rowSecondary.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  /// 翻「跟随法定节假日」这个开关。
  ///
  /// **打开它会把 `_classes` 清空**，而保存时 `saveSchedule` 的悬空清理会连带
  /// 删掉**全部**按天覆盖（spec §4.2）；切回来恢复的默认四班两倒又是全新的 id，
  /// 那些覆盖再也接不回去。所以真会丢东西（本来有班次、且有覆盖）时必须先问
  /// 一次，问清楚是几天。
  ///
  /// **先确认再翻开关**，不做「乐观翻开、取消再翻回」：`GlassSwitch` 的 `value`
  /// 完全由外部给定（它自己不存状态），所以不确认就直接返回、不调 `setState`，
  /// 开关的视觉状态从头到尾没动过 —— 不会出现「翻过去又弹回来」那一下抖动。
  Future<void> _setFollowHoliday(bool v) async {
    if (v && _classes.isNotEmpty && _overridesByClassId.isNotEmpty) {
      final lost = _overridesByClassId.values.fold<int>(0, (a, b) => a + b);
      final confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (dialogContext) => GlassDialog(
          title: L10n.followHolidayConfirmTitle,
          content: Text(L10n.followHolidayDropsOverrides(lost)),
          actions: [
            GlassActionButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              label: L10n.cancel,
            ),
            const SizedBox(width: AppTokens.spaceSm),
            GlassActionButton(
              variant: GlassActionVariant.danger,
              onPressed: () => Navigator.pop(dialogContext, true),
              label: L10n.confirm,
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _followHoliday = v;
      if (v) {
        // 切到空白表：清空班次与周期，班组收敛为「我」。
        //
        // **按月那一套也要一起清**：空白表没有班次定义，段表指着不存在的下标
        // 就是一堆悬空引用（保存时会被 `saveSchedule` 的悬空清理连带删掉，
        // 但留着它在编辑器里也只会让预览算出一堆 null）。
        _classes = [];
        _cycle = [];
        _monthly = false;
        _monthlySegments = [];
        _teamSegOffsets = [];
        _syncClassCtrls();
        _teamCount = 1;
        _teamNames = [L10n.isEn ? 'Me' : '我'];
        _ourTeamIndex = 0;
        _teamOffsets = [];
        _syncTeamNameCtrls();
        if (_name.trim().isEmpty || _name.trim() == L10n.newSchedule) {
          _name = L10n.holidayScheduleName;
          _scheduleNameCtrl.text = _name;
        }
      } else if (_classes.isEmpty) {
        // 从空白表切回普通表：恢复默认四班两倒（因为空白表把两边都清空了）
        final d = defaultSchedule();
        _classes = List.of(d.classes);
        _cycle = List.of(d.cycle);
        _monthly = false;
        _monthlySegments = [];
        // 空表而不是 [0,1,2,3]：那时它本来就不参与计算，而塞一份**天偏移**进去
        // 只会让「这个字段存的是段」这条约定在库里看起来是假的。
        // （落库是 ''，`toDomain` 会按「相对我们班组」补回来。）
        _teamSegOffsets = [];
        _teamCount = d.teamCount;
        _teamNames = List.of(d.teamNames);
        _ourTeamIndex = d.ourTeamIndex;
        _teamOffsets = List.of(d.teamOffsets);
        _syncClassCtrls();
        _syncTeamNameCtrls();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 编辑动作
  // ---------------------------------------------------------------------------

  /// 点行末那颗色点 → 弹取色层 → 把结果写回这一条班次。
  ///
  /// 取色那三百行搬到 `shift_color_picker.dart` 了（16 颗预设、色相条、饱和度/明度
  /// 方盘、十六进制输入）。这里只剩「传当前色进去、把结果写回」两件事。
  ///
  /// ⚠️ **`_editClass` 那套别动** —— 它有意的**不走 `copyWith`**（`copyWith` 把可空
  /// 字段写成 `xx ?? this.xx`，没有「把可空字段清成 null」的通道；切休班时时间就
  /// 永远清不掉）。这一版只是换了颜色的来源。
  Future<void> _pickColor(int index) async {
    final picked = await showShiftColorPicker(
      context,
      current: _classes[index].color,
      sampleLabel: _classes[index].abbr ?? _classes[index].name,
    );
    if (picked == null || !mounted) return;
    setState(
        () => _classes[index] = _editClass(_classes[index], color: picked));
  }

  /// 把当前这套存成「我的模板」（新建排班时可以再选它）。
  ///
  /// 取的是 [_draftSchedule] —— 也就是**编辑器眼下的草稿状态**，与预览条同一个
  /// 来源：用户可以把一套还没保存的改动直接存成模板，不必先保存成方案。
  Future<void> _saveAsTemplate() async {
    // **周期与按月段表，有一边有内容就存得下来**：只判周期的话，按月方案会被
    // 当成「没有排班规则」拦下（而它明明有一套切法）。
    if (_followHoliday ||
        _classes.isEmpty ||
        (_cycle.isEmpty && _monthlySegments.isEmpty)) {
      // 空白表（跟随法定节假日）没有班次与规则，存下来是一张空卡
      // （读回时也会被跳过），不如当场说清楚。
      showGlassSnack(context, L10n.templateNeedsPattern,
          icon: Icons.info_outline);
      return;
    }
    // 控制器**不 dispose**：与待办弹窗（`schedule_screen.dart` 的 `_showAddDialog`）
    // 同一套写法 —— 提前 dispose 会在弹窗退场动画里被 TextField 再读一次，
    // 直接抛「A TextEditingController was used after being disposed」。
    final ctrl = TextEditingController(text: _name.trim());
    final name = await showGlassDialog<String>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: L10n.saveAsTemplate,
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: glassInputDecoration(context, L10n.templateName),
        ),
        actions: [
          GlassActionButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: L10n.cancel,
          ),
          const SizedBox(width: 8),
          GlassActionButton(
            variant: GlassActionVariant.primary,
            onPressed: () =>
                Navigator.of(dialogContext).pop(ctrl.text.trim()),
            label: L10n.save,
          ),
        ],
      ),
    );
    // 空名字当没存：模板名是选择页卡片上唯一的识别信息，留空比不存更糟。
    if (name == null || name.isEmpty || !mounted) return;

    await ref
        .read(appRepositoryProvider)
        .saveTemplate(ScheduleTemplate.fromSchedule(_draftSchedule(),
            name: name));
    // 存完立刻作废选择页那份缓存：用户很可能在这一趟里先开过「新建排班」，
    // 不作废的话他回去看不到刚存的那条（见 savedTemplatesProvider 的说明）。
    ref.invalidate(savedTemplatesProvider);
    if (!mounted) return;
    showGlassSnack(context, L10n.templateSaved(name),
        icon: Icons.bookmark_added_outlined);
  }

  void _addClass() {
    setState(() {
      final idx = _classes.length;
      final c = ShiftClass(
        name: L10n.newShiftName,
        color: kShiftPalette[idx % kShiftPalette.length],
        startMinute: toMinutes(8, 0),
        endMinute: toMinutes(20, 0),
      );
      _classes.add(c);
      _nameCtrls.add(TextEditingController(text: c.name));
      _abbrCtrls.add(TextEditingController());
    });
  }

  Future<void> _deleteClass(int index) async {
    // **周期与按月段表都要数**：只数周期的话，按月方案里被「段」引用的班次会被
    // 放行 —— 删掉之后段的下标整体前移、指向别的班次，不报错、只是那几天显示成
    // 别的班（与「覆盖指飞」是同一类静默错）。
    final used = _cycle.where((c) => c == index).length +
        _monthlySegments.where((s) => s.classIndex == index).length;
    if (used > 0) {
      // 仍被引用：直接拦下，不弹确认 —— 这条路本来就删不掉。
      showGlassSnack(
        context,
        L10n.deleteShiftClassInUse.replaceAll('{n}', '$used'),
        icon: Icons.info_outline,
      );
      return;
    }

    // 删除会把周期里比它大的下标整体前移，而时间 / 颜色 / 闹钟配置都不在
    // 周期里，重加一个班次也复原不回来 —— 所以先确认一次。
    //
    // 还有一样复原不回来的东西：**按天覆盖**。引用这个班次的覆盖行会在保存时
    // 被 `saveSchedule` 的悬空清理连带删掉（spec §4.2），而覆盖没有「重加」这条
    // 路 —— 所以天数必须写进确认框，不能只提时间 / 颜色 / 闹钟。
    final name = _classes[index].name;
    final lostOverrides = _overridesByClassId[_classes[index].id] ?? 0;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: L10n.deleteShiftClassTitle,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.deleteShiftClassContent(name)),
            if (lostOverrides > 0) ...[
              const SizedBox(height: AppTokens.spaceMd),
              Text(L10n.deleteShiftClassOverridesLost(lostOverrides)),
            ],
          ],
        ),
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
      // 段表**同待遇**：引用检查与下标重映射都要做，否则段会静默指到别的班次。
      for (var i = 0; i < _monthlySegments.length; i++) {
        final s = _monthlySegments[i];
        if (s.classIndex > index) {
          _monthlySegments[i] = MonthlySegment(
              startDay: s.startDay, classIndex: s.classIndex - 1);
        }
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = _name.trim().isEmpty ? L10n.schedule : _name.trim();
      final anchor = dateOnly(_anchor);
      final repo = ref.read(appRepositoryProvider);
      await repo.saveSchedule(
            scheduleId: widget.scheduleId ??
                ref.read(activeScheduleProvider).valueOrNull?.currentScheduleId,
            name: name,
            anchorDate: anchor,
            classes: _classes,
            cycle: _cycle,
            makeCurrent: widget.scheduleId == null,
            teamCount: _teamCount,
            teamNames: _teamNames,
            ourTeamIndex: _ourTeamIndex,
            teamOffsets: _teamOffsets,
            monthly: _monthly,
            monthSegments: _monthlySegments,
            teamSegOffsets: _teamSegOffsets,
          );
      // 重排读的是**整条链**（`rescheduleAll` → `getActiveSchedules`），链上既有
      // 刚编辑的这套、也有「其余时间」那套 —— 所以「编辑的是一套非当前方案」
      // 这条路径本来就对，不必再特别处理。
      await AlarmService.rescheduleAll(repo);
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
  List<ShiftAlarm>? alarms,
  bool clearAlarms = false,
}) {
  return ShiftClass(
    // 必须带下去：丢了 id 就等于把这个班次变成「新班次」，保存时会插一条新行，
    // 而旧行连同引用它的按天覆盖（shift_day_overrides.classId）一起被删 ——
    // 用户只是改个简称，按天调整就全指飞了。
    id: c.id,
    name: name ?? c.name,
    abbr: abbr ?? c.abbr,
    startMinute: clearTimes ? null : (startMinute ?? c.startMinute),
    endMinute: clearTimes ? null : (endMinute ?? c.endMinute),
    isRest: isRest ?? c.isRest,
    color: color ?? c.color,
    alarmEnabled: alarmEnabled ?? c.alarmEnabled,
    alarms: clearAlarms ? const [] : (alarms ?? c.alarms),
  );
}

/// 闹钟名字的长度上限（字符数）。
///
/// 不封顶的话，闹钟页那一行会被超长名字顶到溢出（独立审查提的）。12 个字对
/// 「起床 / 午休 / 交接班提醒」这类名字绰绰有余。
const int _alarmNameMaxLength = 12;

/// 一条闹钟的名字输入框：自己持 controller，初值由 [label] 给。
///
/// **不把 controller 放进编辑器的状态里**：闹钟可以随时增删，班次下标 × 闹钟下标
/// 两层对账很容易漏一处，而漏了的表现是「改了名字没生效」或「名字串到别的闹钟
/// 上」，都不报错。控件自己持有时靠位置做 Key（`shift-alarm-label-<班次>-<序号>`，
/// 由调用方给），**删掉前面那条闹钟之后同一格会换上别人的名字** —— 所以必须靠
/// [didUpdateWidget] 把文本同步过去。
class _AlarmLabelField extends StatefulWidget {
  const _AlarmLabelField(
      {super.key, required this.label, required this.onChanged});

  final String? label;

  /// 已经 trim 过：空串一律当没填（用户敲了个空格不该变成「白班 · 」）。
  final ValueChanged<String?> onChanged;

  @override
  State<_AlarmLabelField> createState() => _AlarmLabelFieldState();
}

class _AlarmLabelFieldState extends State<_AlarmLabelField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.label ?? '');

  @override
  void didUpdateWidget(covariant _AlarmLabelField old) {
    super.didUpdateWidget(old);
    final next = widget.label ?? '';
    // 比的是 `_ctrl.text.trim()`：正在打字时下一个字符可能是空格，不该被当成
    // 「换了另一条闹钟」而把输入重置掉。
    if (next != old.label && next != _ctrl.text.trim()) {
      _ctrl.text = next;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        // 名字有长度上限：不封顶的话，闹钟页那一行会被超长名字顶到溢出
        // （独立审查提的）。12 个字对「起床 / 午休 / 交接班提醒」这类名字绰绰有余，
        // 与旁边的简称框一样**不显示计数器**（120 宽的框里那是噪音）。
        maxLength: _alarmNameMaxLength,
        onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v.trim()),
        decoration: glassInputDecoration(context, L10n.alarmNameOptional,
                isDense: true)
            .copyWith(hintText: L10n.alarmNameHint, counterText: ''),
      );
}

/// 周期行里某个 chip 的 Key —— 让测试能精确点到「第几天选哪个班次」。
Key cycleChipKey(int dayIndex, int classIndex) =>
    ValueKey('cycle-chip-$dayIndex-$classIndex');

/// 按月段列表里第 [i] 行那一整块「每月第 N 天起」的 Key —— 点它就是改这一段的
/// 起始日（第一行不给点）。与 [cycleChipKey] 同一套：让测试能按行定位。
Key monthRowDayKey(int i) => ValueKey('month-row-day-$i');

/// 按月段列表第 [i] 行的删除键（第一行没有）。
///
/// 单独给 Key 是因为页面上还有**班次定义那一排**的紧凑删除钮 ——
/// `find.byType(GlassDeleteButton)` 会一起数进来，按行定位只能靠 Key。
Key monthRowDeleteKey(int i) => ValueKey('month-row-del-$i');

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
    _textWidth(label, AppTokens.rowSecondary);

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
      _textWidth(timeText, AppTokens.rowSecondary);
  return needed <= rowWidth;
}

/// 「第 N 天」标签的固定宽度。
const double _dayLabelWidth = 56;

/// 这条闹钟落在班次当天的哪一边 —— 只管**读法**：前一天 / 次日给一个带日前缀的
/// 整串（`前一天 23:00` / `次日 00:15`），落在当天返回 null（不标）。
///
/// 为什么非标不可：只写钟点会被读成班次当天 —— 16:30–次日 00:30 的 00:15 只写
/// 「00:15」，看着就像上班前的那个凌晨（比上班早 16 小时），而那正是用户报的
/// 「看不到有这个选项」。
String? _alarmDayLabel(ShiftClass c, ShiftAlarm a) {
  final clock = formatClock(a.minute);
  return switch (alarmDayAnchor(c, a)) {
    AlarmDayAnchor.prev => L10n.clockPrevDay(clock),
    AlarmDayAnchor.next => L10n.clockNextDay(clock),
    AlarmDayAnchor.same => null,
  };
}
