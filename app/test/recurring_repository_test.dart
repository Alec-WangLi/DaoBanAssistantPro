// app/test/recurring_repository_test.dart
//
// 系列那几行的增删改查 + 跳过一次。都是直接对仓库，不经过界面。
//
// 重点在几条容易漏的关联：
//  ① 删系列要**连带删它的行**（否则列表里留下几条永远挂空的「历史」）；
//  ② 「以后不再重复」（unlink）与「删除整个重复」是**两件事**：前者一条待办都
//     不许删，后者才连带删 —— 混了就会把用户正在编辑的那条待办删掉；
//  ③ 把一条待办挂上系列 / 摘下来，`seriesId` 真的落库；
//  ④ `clearAll` 要把新表也清掉（AGENTS 里那条「清空要连带删」的老规矩）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/recurring_todo.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';

void main() {
  late AppDatabase db;
  late AppRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AppRepository(db);
    await repo.ensureSeeded();
  });
  tearDown(() => db.close());

  Future<int> addSeries({int weekdays = 1 << 2}) => repo.addRecurringTodo(
        title: '周三例会',
        repeat: RecurRepeat.weekly,
        startDate: DateTime.utc(2026, 10, 14),
        timeMinute: 9 * 60,
        advanceRemindMinutes: 0,
        weekdays: weekdays,
      );

  test('新增之后读得回来，字段逐个对得上', () async {
    final id = await addSeries();
    final s = (await repo.listRecurringTodos()).single;
    expect(s.id, id);
    expect(s.title, '周三例会');
    expect(s.repeat, RecurRepeat.weekly);
    expect(s.weekdays, 1 << 2);
    expect(s.timeMinute, 9 * 60);
    expect(s.advanceRemindMinutes, 0);
    expect(dayNumber(s.startDate), dayNumber(DateTime(2026, 10, 14)));
    expect(s.enabled, isTrue);
    expect(s.skipThrough, isNull);
    expect(s.alarmEnabled, isFalse);
    expect(s.monthDay, 1);
  });

  test('updateRecurringTodo 覆盖全部字段（含把提醒改回「不提醒」）', () async {
    final id = await addSeries();
    final s = (await repo.listRecurringTodos()).single;
    // **显式构造**而不是 `copyWith(advanceRemindMinutes: null)` —— copyWith 是
    // `?? this.x`，没有把可空字段清成 null 的通道，那条断言会假绿（旧值还在）。
    await repo.updateRecurringTodo(RecurringTodo(
      id: id,
      title: '周例会',
      repeat: RecurRepeat.monthly,
      startDate: s.startDate,
      monthDay: 15,
      advanceRemindMinutes: null,
    ));
    final after = (await repo.listRecurringTodos()).single;
    expect(after.title, '周例会');
    expect(after.repeat, RecurRepeat.monthly);
    expect(after.monthDay, 15);
    expect(after.advanceRemindMinutes, isNull, reason: '要能真的清成 null');
  });

  test('停用 / 启用', () async {
    final id = await addSeries();
    await repo.setRecurringEnabled(id, false);
    expect((await repo.listRecurringTodos()).single.enabled, isFalse);
    await repo.setRecurringEnabled(id, true);
    expect((await repo.listRecurringTodos()).single.enabled, isTrue);
  });

  test('跳过这一次：skipThrough 写成那天的 dayNumber', () async {
    final id = await addSeries();
    await repo.skipRecurringOccurrence(id, DateTime.utc(2026, 10, 14));
    expect((await repo.listRecurringTodos()).single.skipThrough,
        dayNumber(DateTime.utc(2026, 10, 14)));
  });

  test('删系列连带删它的行（历史与当前那条都不留）', () async {
    final id = await addSeries();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 14), seriesId: id);
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 7), seriesId: id);
    expect((await repo.listEvents()).length, 2);

    await repo.deleteRecurringTodo(id);
    expect(await repo.listRecurringTodos(), isEmpty);
    expect(await repo.listEvents(), isEmpty, reason: '系列没了，它的行也该走');
  });

  test('**「以后不再重复」（unlink）把行留着、只解绑并删系列**', () async {
    final id = await addSeries();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 14), seriesId: id);
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 7), seriesId: id);

    await repo.unlinkRecurringSeries(id);

    expect(await repo.listRecurringTodos(), isEmpty, reason: '系列定义该没了');
    final rows = await repo.listEvents();
    expect(rows.length, 2,
        reason: '待办一条都不许删 —— 用户说的是「别再自动出现」，'
            '而正在编辑的那条就在这两条里');
    expect(rows.every((e) => e.seriesId == null), isTrue, reason: '都解绑了');
  });

  test('删系列不动别人的行', () async {
    final id = await addSeries();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 14), seriesId: id);
    await repo.addEvent(title: '交体检报告', date: DateTime.utc(2026, 10, 15));
    await repo.deleteRecurringTodo(id);
    final left = await repo.listEvents();
    expect(left.length, 1);
    expect(left.single.title, '交体检报告');
  });

  test('待办能挂上系列、也能摘下来', () async {
    final id = await addSeries();
    await repo.addEvent(
        title: '周三例会', date: DateTime.utc(2026, 10, 14), seriesId: id);
    var e = (await repo.listEvents()).single;
    expect(e.seriesId, id);

    await repo.updateEvent(e, title: e.title, date: e.date, seriesId: null);
    e = (await repo.listEvents()).single;
    expect(e.seriesId, isNull, reason: '「以后不再重复」= 解绑');
  });

  test('setEventDate 只改日期，不动时间 / 提醒 / 联动闹钟', () async {
    // 这一条钉的是「别用 updateEvent 去改日期」：那个是全字段覆盖，只传日期会把
    // 另外三个字段一起抹成默认值，而界面上看不出来（弹窗里那几行还是旧值，
    // 直到用户再打开一次）。
    final id = await addSeries();
    final rowId = await repo.addEvent(
      title: '周三例会',
      date: DateTime.utc(2026, 10, 14),
      timeMinute: 9 * 60,
      advanceRemindMinutes: 15,
      alarmEnabled: true,
      seriesId: id,
    );
    await repo.setEventDate(rowId, DateTime.utc(2026, 10, 16));

    final e = (await repo.listEvents()).single;
    expect(dayNumber(e.date), dayNumber(DateTime(2026, 10, 16)));
    expect(e.timeMinute, 9 * 60);
    expect(e.advanceRemindMinutes, 15);
    expect(e.alarmEnabled, isTrue);
    expect(e.seriesId, id);
  });

  test('clearAll 把新表也清掉', () async {
    await addSeries();
    await repo.clearAll();
    expect(await repo.listRecurringTodos(), isEmpty);
  });
}
