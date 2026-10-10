// app/test/todo_archive_test.dart
//
// 待办归档那两件事的纯/近纯部分：
//   ① 把一个列表拆成「主列表」与「折叠区」（`splitTodos`，纯函数）—— 本文件；
//   ② 归档超上限时丢最旧的那几条（`pruneArchivedTodos`，要一个真库）—— 下面那组。
//
// 界面怎么摆（折叠区收起 / 展开、勾完先划掉再收走）在 `todo_archive_screen_test.dart`。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_database.dart';
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
}
