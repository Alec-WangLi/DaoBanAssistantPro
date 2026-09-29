// app/test/advance_recurring_test.dart
//
// 生成器：让每个系列「当前这一次」的样子与今天对齐。
//
// 六种状态各一条 —— 其中三条（不倒退 / 跨两周 / 删完不补）是「错了也不报错」的
// 那类：界面只是某天多出来一条、或者少了一条，没有任何异常。
//
// 比日期一律走 `dayNumber`：drift 读回来的是**本地** DateTime，而存进去的是 UTC
// 纯日期（全仓比「同一天」的既有约定）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

/// 2026-09-23 是周三。测试全都以它当「今天」的基准。
final _wed = DateTime.utc(2026, 9, 23);

/// 下一个周三。
final _nextWed = DateTime.utc(2026, 9, 30);

/// 中间隔了一个周三（9/30）的那个周三。
final _twoWeeksOn = DateTime.utc(2026, 10, 7);

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  /// 一条「每周三 09:00、提前 0 分钟提醒」的系列，起始日就是 9/23。
  Future<int> weekly() => repo.addRecurringTodo(
        title: '周三例会',
        repeat: RecurRepeat.weekly,
        startDate: _wed,
        timeMinute: 9 * 60,
        advanceRemindMinutes: 0,
        weekdays: 1 << 2,
      );

  test('没有未完成的行 → 新建一条，日期是当前这一次', () async {
    final id = await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final rows = await repo.listEvents();
    expect(rows.length, 1);
    expect(rows.single.seriesId, id);
    expect(dayNumber(rows.single.date), dayNumber(_wed));
    expect(rows.single.isCompleted, isFalse);
    expect(rows.single.title, '周三例会');
    expect(rows.single.timeMinute, 9 * 60);
    expect(rows.single.advanceRemindMinutes, 0);
  });

  test('再跑一次不会多建一条（幂等）', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    await repo.advanceRecurringTodos(today: _wed);
    expect((await repo.listEvents()).length, 1);
  });

  test('过期未勾 → **就地顺延**，行的 id 不变', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final before = (await repo.listEvents()).single;

    await repo.advanceRecurringTodos(today: _nextWed);
    final after = (await repo.listEvents()).single;
    expect(after.id, before.id, reason: '顺延是改这一条，不是新建一条');
    expect(dayNumber(after.date), dayNumber(_nextWed));
    expect(after.isCompleted, isFalse);
  });

  test('跨两周没打开 App → 只顺延到**最近一次**，不补中间那几次', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    // 跳过 9/30，直接到 10/7
    await repo.advanceRecurringTodos(today: _twoWeeksOn);
    final rows = await repo.listEvents();
    expect(rows.length, 1, reason: '错过的不补，列表里只有当前这一条');
    expect(dayNumber(rows.single.date), dayNumber(_twoWeeksOn));
  });

  test('**用户手工改到将来 → 不倒退**（这周的会挪到周五）', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final e = (await repo.listEvents()).single;
    final fri = DateTime.utc(2026, 9, 25);
    await repo.setEventDate(e.id, fri);
    // 生成器再跑（今天还是 9/23，occurrence 是 9/23，行在 9/25）
    await repo.advanceRecurringTodos(today: _wed);
    expect(dayNumber((await repo.listEvents()).single.date), dayNumber(fri),
        reason: '生成器只往前顺延，永不回退 —— 否则用户挪的日子会被拽回来');
  });

  test('删掉当前那条（跳过）之后再跑 → **不补回来**', () async {
    final id = await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final e = (await repo.listEvents()).single;
    // 列表里的「删」= 跳过这一次 + 删掉那一行（见 `recurring_screen_test`）
    await repo.skipRecurringOccurrence(id, e.date);
    await repo.deleteEvent(e);
    await repo.advanceRecurringTodos(today: _wed);
    expect(await repo.listEvents(), isEmpty,
        reason: '删了又回来 = 用户眼里的删不掉');
  });

  test('到了下一次 occurrence，跳过标记自然失效、它又出现', () async {
    final id = await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final e = (await repo.listEvents()).single;
    await repo.skipRecurringOccurrence(id, e.date);
    await repo.deleteEvent(e);

    await repo.advanceRecurringTodos(today: _nextWed);
    final rows = await repo.listEvents();
    expect(rows.length, 1);
    expect(dayNumber(rows.single.date), dayNumber(_nextWed));
  });

  test('勾过之后（无未完成行）→ 下一次到点新建一条，历史留着', () async {
    await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    final e = (await repo.listEvents()).single;
    await repo.setEventCompleted(e, true);

    await repo.advanceRecurringTodos(today: _nextWed);
    final rows = await repo.listEvents();
    expect(rows.length, 2, reason: '完成的那条是历史，新的一次另起一条');
    expect(rows.where((r) => r.isCompleted).length, 1);
    final days = rows.map((r) => dayNumber(r.date)).toSet();
    expect(days, {dayNumber(_wed), dayNumber(_nextWed)});
  });

  test('停用 → 不新建也不顺延，已经出现的那条留着', () async {
    final id = await weekly();
    await repo.advanceRecurringTodos(today: _wed);
    await repo.setRecurringEnabled(id, false);
    await repo.advanceRecurringTodos(today: _twoWeeksOn);
    final rows = await repo.listEvents();
    expect(rows.length, 1);
    expect(dayNumber(rows.single.date), dayNumber(_wed),
        reason: '停用只是不再自动出现，不替你把它收走');
  });

  test('起始日在将来 → 什么都不做', () async {
    await repo.addRecurringTodo(
      title: '下个月开始',
      repeat: RecurRepeat.monthly,
      startDate: DateTime.utc(2026, 10, 1),
      monthDay: 1,
    );
    await repo.advanceRecurringTodos(today: _wed);
    expect(await repo.listEvents(), isEmpty);
  });

  test('多条未完成（脏数据）→ 收敛成一条', () async {
    final id = await weekly();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 9, 16), seriesId: id);
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 9, 9), seriesId: id);
    await repo.advanceRecurringTodos(today: _wed);
    final live =
        (await repo.listEvents()).where((r) => !r.isCompleted).toList();
    expect(live.length, 1, reason: '一个系列至多一条未完成的行');
    expect(dayNumber(live.single.date), dayNumber(_wed));
  });

  test('多个系列互不干扰', () async {
    final a = await weekly();
    final b = await repo.addRecurringTodo(
      title: '每天交班',
      repeat: RecurRepeat.daily,
      startDate: _wed,
      timeMinute: 7 * 60,
      advanceRemindMinutes: 0,
    );
    await repo.advanceRecurringTodos(today: _wed);
    final rows = await repo.listEvents();
    expect(rows.length, 2);
    expect(rows.map((r) => r.seriesId).toSet(), {a, b});
  });
}
