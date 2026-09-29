// app/test/schedule_chain_repository_test.dart
//
// 装配与流：
//  · 只有一套方案时（**今天的样子**）与从前等价 —— 这是「老库一字不变」的回归；
//  · 两套带时段时按天解析各归各的；
//  · 按天改班的覆盖要落在那天**所属方案**名下（记在当前方案名下会静默失效）；
//  · 改**非当前**方案的时段，这条流必须重发（漏了 watch 整表就是「改完不动」）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

ShiftSchedule _sched(String name) => ShiftSchedule(
      name: name,
      anchorDate: DateTime.utc(2026, 1, 1),
      classes: [
        ShiftClass(
            name: '$name-白', abbr: '白', startMinute: 480, endMinute: 1080),
        ShiftClass(name: '$name-休', abbr: '休', isRest: true),
      ],
      // 周期 2 天：锚点起第 0 天白、第 1 天休。
      cycle: const [0, 1],
    );

DateTime _d(int y, int m, int day) => DateTime.utc(y, m, day);

Future<int> _save(AppRepository repo, String name, {required bool current}) {
  final s = _sched(name);
  return repo.saveSchedule(
    name: name,
    anchorDate: s.anchorDate,
    classes: s.classes,
    cycle: s.cycle,
    makeCurrent: current,
  );
}

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
  });
  tearDown(() => db.close());

  test('只有一套方案（今天的样子）→ 每天都归它，spans 为空', () async {
    await _save(repo, '四班两倒', current: true);
    final a = (await repo.getActiveSchedules())!;
    expect(a.all.length, 1);
    expect(a.chain.spans, isEmpty, reason: '没设时段 = 不参与衔接');
    expect(a.chain.scheduleOn(_d(2020, 1, 1))!.name, '四班两倒');
    expect(a.chain.scheduleOn(_d(2030, 1, 1))!.name, '四班两倒');
    expect(a.currentScheduleId, a.all.single.schedule.id);
  });

  test('两套各带时段 → 按天各归各的，时段之外仍归当前方案', () async {
    final aId = await _save(repo, 'A', current: true);
    final bId = await _save(repo, 'B', current: false);
    await repo.setScheduleSpan(aId, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
    await repo.setScheduleSpan(bId, from: _d(2026, 7, 1));

    final s = (await repo.getActiveSchedules())!;
    expect(s.chain.spans.length, 2);
    expect(s.chain.scheduleOn(_d(2026, 6, 30))!.name, 'A'); // 闭区间
    expect(s.chain.scheduleOn(_d(2026, 7, 1))!.name, 'B'); // 差一天
    expect(s.chain.scheduleOn(_d(2025, 1, 1))!.name, 'A', reason: '兜底是当前方案');
  });

  test('setScheduleSpan 能把时段清回 null（= 不再参与衔接）', () async {
    final id = await _save(repo, 'A', current: true);
    await repo.setScheduleSpan(id, from: _d(2026, 1, 1));
    expect((await repo.getActiveSchedules())!.chain.spans.length, 1);
    await repo.setScheduleSpan(id);
    expect((await repo.getActiveSchedules())!.chain.spans, isEmpty);
  });

  test('按天覆盖跟着「那天归哪套」走 —— 记在**那天所属方案**名下', () async {
    final aId = await _save(repo, 'A', current: true);
    final bId = await _save(repo, 'B', current: false);
    await repo.setScheduleSpan(aId, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
    await repo.setScheduleSpan(bId, from: _d(2026, 7, 1));

    final bRestId = (await repo.getScheduleDomain(bId))!.classes.last.id!;

    // 7/1 归 B，而**当前方案是 A**。修 `setDayOverrides` 之前，这里会把那条覆盖
    // 记在 A 名下 —— 既查不出来、也不报错，用户看到的是「改了班，日历纹丝不动」。
    await repo.setDayOverrides([_d(2026, 7, 1)], classId: bRestId);

    final rows = await db.select(db.shiftDayOverrides).get();
    expect(rows.length, 1);
    expect(rows.single.scheduleId, bId);
    expect(
      (await repo.getActiveSchedules())!.chain.shiftOn(_d(2026, 7, 1))!.isRest,
      isTrue,
      reason: '覆盖没生效 = 记到错的方案名下了',
    );
  });

  test('clearDayOverrides 同样按天找方案（否则撤不回来）', () async {
    final aId = await _save(repo, 'A', current: true);
    final bId = await _save(repo, 'B', current: false);
    await repo.setScheduleSpan(aId, from: _d(2026, 1, 1), to: _d(2026, 6, 30));
    await repo.setScheduleSpan(bId, from: _d(2026, 7, 1));
    final bRestId = (await repo.getScheduleDomain(bId))!.classes.last.id!;

    await repo.setDayOverrides([_d(2026, 7, 1)], classId: bRestId);
    await repo.clearDayOverrides([_d(2026, 7, 1)]);

    expect(await db.select(db.shiftDayOverrides).get(), isEmpty);
    // 撤回之后回到 B 的轮转：锚点 2026-01-01 起第 181 天 → 181 % 2 = 1 → 休
    expect(
      (await repo.getActiveSchedules())!.chain.shiftOn(_d(2026, 7, 1))!.name,
      'B-休',
    );
  });

  test('改**非当前**方案的时段 → 流重发，且装配里含非当前那套', () async {
    await _save(repo, 'A', current: true);
    final bId = await _save(repo, 'B', current: false);

    final seen = <int>[];
    final sub = db
        .watchActiveSchedule()
        .listen((s) => seen.add(s!.chain.spans.length));
    await Future<void>.delayed(const Duration(milliseconds: 20)); // 等首帧
    expect(seen, isNotEmpty);
    expect(seen.last, 0);

    await repo.setScheduleSpan(bId, from: _d(2026, 7, 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    // 两条各自守一件事：
    //  · **重发** —— 方案表那条触发源不能少。已反向验证：把它从 `triggers` 里
    //    删掉，这里立刻 `Expected: <1> Actual: <0>`。
    //  · **装配里含非当前那套** —— 从前 `_loadChildren(isCurrent)` 只装一套，
    //    这个断言在那套写法下恒为 1、`seen.last` 恒为 0。
    expect(seen.last, 1, reason: '改非当前方案不重发 = 日历/闹钟/小组件全不动');
    expect((await repo.getActiveSchedules())!.all.length, 2);
  });
}
