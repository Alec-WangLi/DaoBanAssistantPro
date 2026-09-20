// app/test/schedule_template_test.dart
//
// 「我的模板」：从一套方案取模板（含把「我们班组」归一化到第 0 位）与编解码。
// 都是纯函数，直接 dart test。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/schedule_template.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

/// 用户那套：五班三倒 10 天一轮（白白中中休夜夜休休休），各班组差 2 天。
ShiftSchedule _tenDay({int ourTeamIndex = 0, List<int>? offsets}) =>
    ShiftSchedule(
      name: '测试排班',
      anchorDate: DateTime.utc(2026, 9, 21),
      classes: const [
        ShiftClass(
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60 + 30,
            endMinute: 20 * 60 + 30,
            color: 0xFF4C8DFF,
            alarmEnabled: true,
            alarmMinute: 7 * 60),
        ShiftClass(
            name: '中班',
            abbr: '中',
            startMinute: 16 * 60,
            endMinute: 24 * 60,
            color: 0xFFFF9F0A),
        ShiftClass(
            name: '夜班',
            abbr: '夜',
            startMinute: 0,
            endMinute: 8 * 60,
            color: 0xFF7A5CFF,
            alarmEnabled: true,
            alarmMinute: 23 * 60),
        ShiftClass(name: '休班', abbr: '休', isRest: true, color: 0xFF9AA0B4),
      ],
      cycle: const [0, 0, 1, 1, 3, 2, 2, 3, 3, 3],
      teamCount: 5,
      teamNames: const ['一班', '二班', '三班', '四班', '五班'],
      ourTeamIndex: ourTeamIndex,
      teamOffsets: offsets ?? const [0, 2, 4, 6, 8],
    );

/// 把「我们班组在第 0 位」的模板摊回一套方案，好与原件对比。
ShiftSchedule _scheduleOf(ScheduleTemplate t) => ShiftSchedule(
      name: t.name,
      anchorDate: DateTime.utc(2026, 9, 21),
      classes: t.classes,
      cycle: t.cycle,
      teamCount: t.teamCount,
      ourTeamIndex: 0,
      teamOffsets: t.teamOffsets,
    );

/// 某天各班组班次名的多重集合（班组身份不参与比对，班组分配才参与）。
List<String> _shiftNames(ShiftSchedule s, int day) {
  final date = s.anchorDate.add(Duration(days: day));
  return [
    for (var t = 0; t < s.teamCount; t++) s.teamShift(t, date)?.name ?? 'null',
  ]..sort();
}

void main() {
  test('模板从方案里取：我们班组转到第 0 位、错位归零', () {
    final t = ScheduleTemplate.fromSchedule(_tenDay(ourTeamIndex: 2),
        name: '我的班');

    expect(t.teamCount, 5);
    expect(t.teamOffsets.first, 0, reason: '我们班组的错位必须是 0');
    // 原来的错位是 [0,2,4,6,8]、我们是下标 2 → 转成 [4,6,8,0,2] − 4
    expect(t.teamOffsets, [0, 2, 4, -4, -2]);
    expect(t.cycle, [0, 0, 1, 1, 3, 2, 2, 3, 3, 3]);
    expect(t.classes.map((c) => c.name),
        ['白班', '中班', '夜班', '休班']);
    expect(t.cycleLength, 10);
  });

  test('班组之间的相对错位一个像素都不动', () {
    final src = _tenDay(ourTeamIndex: 3);
    final t = ScheduleTemplate.fromSchedule(src, name: '我的班');
    for (var i = 0; i < src.teamCount; i++) {
      final srcA = _offsetOf(src, (i + src.ourTeamIndex) % src.teamCount);
      final srcB = _offsetOf(src, src.ourTeamIndex);
      expect(t.teamOffsets[i], srcA - srcB,
          reason: '第 $i 组与「我们班组」的间隔必须与原件一致');
    }
  });

  test('用模板建出来的方案与原方案同构（每天各班组的分工完全一样）', () {
    final src = _tenDay(ourTeamIndex: 2);
    final t = ScheduleTemplate.fromSchedule(src, name: '我的班');
    final built = _scheduleOf(t);

    for (var day = 0; day < src.cycleLength; day++) {
      expect(_shiftNames(built, day), _shiftNames(src, day),
          reason: '第 ${day + 1} 天两组方案的班组分工应当相同');
    }
    // 相位**有意不保留**：模板与内置模板同一条约定 —— 新建出来的方案里
    // 「我们班组」从周期第 1 天开始（相位要改，在编辑器里挑「我这组从这个
    // 周期开始」即一次点选）。所以这里断言的是起手相位，而不是「我们班组
    // 的班次一文不变」。
    expect(built.teamOffsets.first, 0);
    expect(built.teamShift(0, built.anchorDate)!.name, src.classes.first.name);
  });

  test('错位表短于班组数时按域里的回退规则补齐', () {
    // teamOffsets 空 → 域里回退到 `i - ourTeamIndex`（我们班组是下标 1 时
    // 五组分别落在 -1/0/1/2/3），再转成「我们打头、归零」。
    final t = ScheduleTemplate.fromSchedule(
        _tenDay(ourTeamIndex: 1, offsets: const []),
        name: '我的班');
    expect(t.teamOffsets, [0, 1, 2, 3, -1],
        reason: '这条回退规则本身是给历史数据兜底的，模板只负责如实搬过来');
  });

  test('每天在岗班组数与选择页卡片同一口径', () {
    final t = ScheduleTemplate.fromSchedule(_tenDay(), name: '我的班');
    expect(t.workingTeamsPerDay, 3);
  });

  group('编解码', () {
    test('班次定义往返：三个可空字段都保得住', () {
      final t = ScheduleTemplate.fromSchedule(_tenDay(), name: '我的班');
      final back = decodeTemplateClasses(encodeTemplateClasses(t.classes));
      expect(back.length, 4);
      expect(back[0].name, '白班');
      expect(back[0].startMinute, 8 * 60 + 30);
      expect(back[0].alarmMinute, 7 * 60);
      expect(back[0].alarmEnabled, isTrue);
      // 中班没有闹钟、夜班从 00:00 开始（钟面 0 与「没填」必须分得开）
      expect(back[1].alarmEnabled, isFalse);
      expect(back[1].alarmMinute, isNull);
      expect(back[2].startMinute, 0);
      expect(back[3].isRest, isTrue);
      expect(back[3].startMinute, isNull);
      expect(back[3].abbr, '休');
    });

    test('班次 id 不入模板：模板里的班次不需要稳定身份', () {
      final t = ScheduleTemplate.fromSchedule(_tenDay(), name: '我的班');
      final back = decodeTemplateClasses(encodeTemplateClasses(t.classes));
      expect(back.every((c) => c.id == null), isTrue);
    });

    test('周期与错位往返（含负错位）', () {
      expect(decodeTemplateCycle(encodeTemplateCycle(const [0, 0, 1, 1, 3])),
          [0, 0, 1, 1, 3]);
      expect(decodeTemplateOffsets(encodeTemplateOffsets(const [0, 2, -4, 6])),
          [0, 2, -4, 6]);
      expect(decodeTemplateInts(''), isEmpty);
      expect(decodeTemplateInts('0, 2 ,x'), [0, 2, 0],
          reason: '解析不出来的那一段按 0 处理，与 parseTeamOffsets 同口径');
    });

    test('坏数据不炸：返回空表，由调用方跳过这一条', () {
      expect(decodeTemplateClasses('{不是 JSON'), isEmpty);
      expect(decodeTemplateClasses(''), isEmpty);
      expect(decodeTemplateClasses('123'), isEmpty);
    });
  });
}

/// 方案里第 [i] 组的错位（含 `teamShift` 那条回退规则）。
int _offsetOf(ShiftSchedule s, int i) => i < s.teamOffsets.length
    ? s.teamOffsets[i]
    : i - s.ourTeamIndex;
