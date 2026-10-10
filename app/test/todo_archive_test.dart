// app/test/todo_archive_test.dart
//
// 待办归档那两件事的纯/近纯部分：
//   ① 把一个列表拆成「主列表」与「折叠区」（`splitTodos`，纯函数）—— 本文件；
//   ② 归档超上限时丢最旧的那几条（`pruneArchivedTodos`，要一个真库）—— 下面那组。
//
// 界面怎么摆（折叠区收起 / 展开、勾完先划掉再收走）在 `todo_archive_screen_test.dart`。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/data/todo_archive.dart';

ScheduleEvent _e(int id, DateTime date, {bool done = false}) => ScheduleEvent(
      id: id,
      title: 't$id',
      date: date,
      isCompleted: done,
      alarmEnabled: false,
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('splitTodos', () {
    test('未完成的全在主列表、顺序不变；已完成的进折叠区、按日期降序', () {
      final events = [
        _e(1, DateTime.utc(2026, 1, 1), done: true),
        _e(2, DateTime.utc(2026, 1, 2)),
        _e(3, DateTime.utc(2026, 1, 3), done: true),
        _e(4, DateTime.utc(2026, 1, 4)),
      ];
      final s = splitTodos(events, const {});
      expect(s.active.map((e) => e.id).toList(), [2, 4]);
      expect(s.archived.map((e) => e.id).toList(), [3, 1],
          reason: '折叠区是「回头看一眼」，最近做完的排最前');
    });

    test('本次刚勾的留在主列表里、且停在原来的位置', () {
      final events = [
        _e(1, DateTime.utc(2026, 1, 1), done: true),
        _e(2, DateTime.utc(2026, 1, 2)),
        _e(3, DateTime.utc(2026, 1, 3), done: true),
      ];
      final s = splitTodos(events, const {1});
      expect(s.active.map((e) => e.id).toList(), [1, 2],
          reason: '刚勾的那条还在主列表，且按日期排在 2 前面 —— 不能跳到末尾');
      expect(s.archived.map((e) => e.id).toList(), [3]);
    });

    test('同一天的两条：折叠区按 id 降序兜底，顺序是确定的', () {
      final d = DateTime.utc(2026, 1, 5);
      final s =
          splitTodos([_e(7, d, done: true), _e(9, d, done: true)], const {});
      expect(s.archived.map((e) => e.id).toList(), [9, 7]);
    });

    test('空表不炸', () {
      final s = splitTodos(const [], const {});
      expect(s.active, isEmpty);
      expect(s.archived, isEmpty);
    });
  });

  group('pruneArchivedTodos', () {
    late AppDatabase db;
    late AppRepository repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = AppRepository(db);
      await repo.ensureSeeded();
    });
    tearDown(() => db.close());

    test('上限就是 100（用户点名要的那个数）', () {
      expect(kArchivedTodoLimit, 100);
    });

    test('截断到 100：丢日期最旧的那些，一条未完成都不许少', () async {
      for (var i = 0; i < 105; i++) {
        await repo.addEvent(title: 'done$i', date: DateTime.utc(2026, 1, 1 + i));
      }
      // `addEvent` 回的是行 id，不是行 —— 勾选要一个 `ScheduleEvent`，读回来再勾。
      for (final e in await repo.listEvents()) {
        await repo.setEventCompleted(e, true);
      }
      for (var i = 0; i < 3; i++) {
        await repo.addEvent(title: 'open$i', date: DateTime.utc(2026, 6, 1 + i));
      }

      expect(await repo.pruneArchivedTodos(), 5);

      final all = await repo.listEvents();
      expect(all.where((e) => !e.isCompleted), hasLength(3),
          reason: '截断只许碰已完成的行');
      final done = all.where((e) => e.isCompleted).toList();
      expect(done, hasLength(100));
      expect(done.map((e) => e.title).contains('done0'), isFalse,
          reason: '丢的必须是日期最旧的那几条');
      expect(done.map((e) => e.title).contains('done104'), isTrue,
          reason: '最新的那条要留着');
    });

    test('截断绝不碰未完成的行 —— 哪怕它比所有已完成的行都旧', () async {
      await repo.addEvent(title: '很旧但没做', date: DateTime.utc(2020, 1, 1));
      for (var i = 0; i < 101; i++) {
        await repo.addEvent(title: 'd$i', date: DateTime.utc(2026, 1, 1 + i));
      }
      for (final e in await repo.listEvents()) {
        if (e.title == '很旧但没做') continue;
        await repo.setEventCompleted(e, true);
      }

      await repo.pruneArchivedTodos();

      final all = await repo.listEvents();
      expect(all.where((e) => !e.isCompleted).single.title, '很旧但没做');
      expect(all.where((e) => e.isCompleted), hasLength(100));
    });

    test('不够上限时什么都不删', () async {
      for (var i = 0; i < 3; i++) {
        await repo.addEvent(title: 'd$i', date: DateTime.utc(2026, 1, 1 + i));
      }
      for (final e in await repo.listEvents()) {
        await repo.setEventCompleted(e, true);
      }
      expect(await repo.pruneArchivedTodos(), 0);
      expect(
          (await repo.listEvents()).where((e) => e.isCompleted), hasLength(3));
    });
  });
}
