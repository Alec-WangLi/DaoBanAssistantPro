// app/test/migration_v12_to_v13_test.dart
//
// v12 → v13：把方案行上的时段两列，按**旧解析结果等价**重放成一张段表。
//
// 规则是 v0.9.12 的「覆盖那天的段里起点最晚的赢」（并列按 id 大者胜）。**每条用例
// 都先按旧规则手算一遍期望值再写断言** —— 用户已经在用那个版本，升级后日历上
// 一天都不能变。
//
// 这一版最要紧的一条是**「外段被内段截断之后接着用」**：它一套方案会产生两段，
// 也正是「段为什么必须独立成表」的理由。
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v12 形态的 `shift_schedule_rows`：v11 那份 DDL + 时段两列。
const _v12ScheduleTable = '''
CREATE TABLE shift_schedule_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  anchor_date INTEGER NOT NULL,
  is_current INTEGER NOT NULL DEFAULT 0,
  team_count INTEGER NOT NULL DEFAULT 4,
  team_names TEXT NOT NULL DEFAULT '一班,二班,三班,四班',
  our_team_index INTEGER NOT NULL DEFAULT 0,
  team_offsets TEXT NOT NULL DEFAULT '',
  effective_from INTEGER,
  effective_to INTEGER
)
''';

/// 开一个 v12 库并种方案 —— **列表顺序就是 id 顺序**（第一个 id = 1）。
///
/// 元组是 `(名字, 起, 止, 是不是其余时间)`，`null` 表示那一端留空。
Future<AppDatabase> _openV12(
    List<(String, DateTime?, DateTime?, bool)> rows) async {
  final raw = sqlite3.sqlite3.openInMemory();
  raw.execute(_v12ScheduleTable);
  for (final (name, from, to, current) in rows) {
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(name, anchor_date, is_current, effective_from, effective_to) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        name,
        DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
        current ? 1 : 0,
        from == null ? null : from.millisecondsSinceEpoch ~/ 1000,
        to == null ? null : to.millisecondsSinceEpoch ~/ 1000,
      ],
    );
  }
  raw.execute('PRAGMA user_version = 12');
  return AppDatabase.forTesting(NativeDatabase.opened(raw));
}

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

/// 迁移后的段表，按 id 升序 —— 每项是 `(方案 id, 起的天数, 止的天数)`，两端为
/// null 表示留空。**比日期一律走 `dayNumber`**（drift 读回来是本地 DateTime）。
Future<List<(int, int?, int?)>> _spans(AppDatabase db) async {
  final rows = await (db.select(db.scheduleSpanRows)
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();
  return [
    for (final s in rows)
      (
        s.scheduleId,
        s.startDate == null ? null : dayNumber(s.startDate!),
        s.endDate == null ? null : dayNumber(s.endDate!),
      ),
  ];
}

void main() {
  test('A 一直持续 + B 从 7/1 起 → A 截到 6/30', () async {
    final db = await _openV12([
      ('A', _d(2026, 1, 1), null, true),
      ('B', _d(2026, 7, 1), null, false),
    ]);
    addTearDown(db.close);
    // 旧规则：1/1–6/30 只有 A；7/1 起两段都覆盖 → 起点晚的 B 赢
    expect(await _spans(db), [
      (1, dayNumber(_d(2026, 1, 1)), dayNumber(_d(2026, 6, 30))),
      (2, dayNumber(_d(2026, 7, 1)), null),
    ]);
  });

  test('B 起得更早但排在后面 → 7/1–7/31 仍归 B', () async {
    final db = await _openV12([
      ('A', _d(2026, 8, 1), null, true),
      ('B', _d(2026, 7, 1), null, false),
    ]);
    addTearDown(db.close);
    // 旧规则：7/1–7/31 只有 B；8/1 起两段都覆盖 → 起点晚的 A 赢
    expect(await _spans(db), [
      (2, dayNumber(_d(2026, 7, 1)), dayNumber(_d(2026, 7, 31))),
      (1, dayNumber(_d(2026, 8, 1)), null),
    ]);
  });

  test('起点相同、id 大的赢 → 小的那段一段都不产生', () async {
    final db = await _openV12([
      ('B', _d(2026, 1, 1), _d(2026, 6, 30), false), // id 1
      ('A', _d(2026, 1, 1), _d(2026, 6, 30), true), // id 2，起点并列 → 它赢
    ]);
    addTearDown(db.close);
    expect(await _spans(db), [
      (2, dayNumber(_d(2026, 1, 1)), dayNumber(_d(2026, 6, 30))),
    ]);
  });

  test('外段被内段截断之后接着用 → **同一套方案产生两段**', () async {
    final db = await _openV12([
      ('B', _d(2026, 7, 1), null, true), // 7/1 起一直持续
      ('C', _d(2026, 9, 1), _d(2026, 9, 30), false), // 9 月临时换成 C
    ]);
    addTearDown(db.close);
    // 旧规则：7/1–8/31 归 B；9/1–9/30 两段都覆盖 → 起点晚的 C 赢；
    //         10/1 起只有 B（C 到 9/30 为止）→ **又归 B**
    expect(await _spans(db), [
      (1, dayNumber(_d(2026, 7, 1)), dayNumber(_d(2026, 8, 31))),
      (2, dayNumber(_d(2026, 9, 1)), dayNumber(_d(2026, 9, 30))),
      (1, dayNumber(_d(2026, 10, 1)), null),
    ], reason: 'B 出现两次 —— 这正是「段独立成表」的理由');
  });

  test('没人覆盖的区间**不产生段**（那些天本来归「其余时间」）', () async {
    final db = await _openV12([
      ('A', _d(2026, 1, 1), _d(2026, 3, 31), true),
      ('B', _d(2026, 7, 1), _d(2026, 9, 30), false),
    ]);
    addTearDown(db.close);
    // 4/1–6/30 与 10/1 起都没人覆盖 —— 旧规则下它们归 isCurrent（A），
    // 而现在 A 是「其余时间」，所以那里**不需要段**，行为一样。
    expect(await _spans(db), [
      (1, dayNumber(_d(2026, 1, 1)), dayNumber(_d(2026, 3, 31))),
      (2, dayNumber(_d(2026, 7, 1)), dayNumber(_d(2026, 9, 30))),
    ]);
  });

  test('本来就没有时段的库 → 段表是空的，方案一条不丢', () async {
    final db = await _openV12([
      ('A', null, null, true),
      ('B', null, null, false),
    ]);
    addTearDown(db.close);
    expect(await _spans(db), isEmpty);
    final rows = await (db.select(db.shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(rows.map((r) => r.name), ['A', 'B']);
    expect(rows.first.isCurrent, isTrue);
  });
}
