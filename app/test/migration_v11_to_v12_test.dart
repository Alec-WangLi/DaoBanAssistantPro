// app/test/migration_v11_to_v12_test.dart
//
// v11 → v12：给 `shift_schedule_rows` 加两个**可空**的生效时段列
// （`effective_from` / `effective_to`），多排班表按日期衔接用。
//
// 这一版是「老库行为一字不变」的全部依据，所以点比正例多：老方案的行数与
// isCurrent 原样、两列都是 null（= 不参与衔接，于是每天都落到当前方案那条兜底
// 路上）、能写能读、**而且能把设好的时段清回 null**。
//
// 与 v10→v11（纯新增一张表 + 加一列）不同的一点：这次那两列加在
// **v1 起就存在**的表上。所以本文件只抄这一张表 —— 但连带结果是**所有更早的
// fixture 都得有这张表**（迁移分支一律按倒序执行，`if (from < 12)` 排在所有
// 更早分支之前，从任何老版本升上来都会跑到它）。v6→v7 与 v10→v11 两份 fixture
// 本轮已因此补上了 DDL。
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v11 形态的 `shift_schedule_rows`（DDL 与 v11 生成代码逐列一致）：
/// **没有** `effective_from` / `effective_to`。
///
/// drift 默认把 `DateTime` 存成 **unix 秒**，`boolean()` 落成 `INTEGER`。
const _v11ScheduleTable = '''
CREATE TABLE shift_schedule_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  anchor_date INTEGER NOT NULL,
  is_current INTEGER NOT NULL DEFAULT 0,
  team_count INTEGER NOT NULL DEFAULT 4,
  team_names TEXT NOT NULL DEFAULT '一班,二班,三班,四班',
  our_team_index INTEGER NOT NULL DEFAULT 0,
  team_offsets TEXT NOT NULL DEFAULT ''
)
''';

void main() {
  test('v11 → v12：老方案原样、两列为 null、能写能读、能清回 null', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute(_v11ScheduleTable);
    // 两套老方案：一套当前、一套不是。值都写全（迁移把值吞了才看得出来）。
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (1, ?, ?, 1, 4, ?, 1, ?)',
      [
        '炼油三部 · 四班三倒',
        DateTime.utc(2026, 1, 6).millisecondsSinceEpoch ~/ 1000,
        '一班,二班,三班,四班',
        '0,2,4,3',
      ],
    );
    raw.execute(
      'INSERT INTO shift_schedule_rows '
      '(id, name, anchor_date, is_current, team_count, team_names, '
      'our_team_index, team_offsets) VALUES (2, ?, ?, 0, 2, ?, 0, ?)',
      [
        '备选 · 12 天长周期',
        DateTime.utc(2025, 12, 1).millisecondsSinceEpoch ~/ 1000,
        '甲班,乙班',
        '0,6',
      ],
    );
    raw.execute('PRAGMA user_version = 11');

    // `NativeDatabase.opened` 把「已经建好 v11 表、user_version 也是 11」的句柄
    // 交给 drift —— 迁移在打开时跑。（与 v9→v10、v10→v11 同一套。）
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // ① 老方案一条不丢、值原样，两列取到 null
    final rows = await (db.select(db.shiftScheduleRows)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    expect(rows.length, 2);
    expect(rows[0].name, '炼油三部 · 四班三倒');
    expect(rows[0].isCurrent, isTrue);
    expect(rows[0].ourTeamIndex, 1);
    expect(rows[0].teamOffsets, '0,2,4,3');
    // 比日期一律走 `dayNumber`：drift 读回来的是**本地** DateTime，存进去的是
    // UTC 纯日期 —— 直接比 DateTime 在东八区就差 8 小时。
    expect(dayNumber(rows[0].anchorDate), dayNumber(DateTime(2026, 1, 6)));
    expect(rows[1].name, '备选 · 12 天长周期');
    expect(rows[1].isCurrent, isFalse);
    for (final r in rows) {
      expect(r.effectiveFrom, isNull, reason: '老方案不该凭空带上生效时段');
      expect(r.effectiveTo, isNull);
    }

    // ② 新列可写、可读
    await (db.update(db.shiftScheduleRows)..where((t) => t.id.equals(2))).write(
      ShiftScheduleRowsCompanion(
        effectiveFrom: Value(DateTime.utc(2026, 7, 1)),
        effectiveTo: Value(DateTime.utc(2026, 12, 31)),
      ),
    );
    var row = await (db.select(db.shiftScheduleRows)
          ..where((t) => t.id.equals(2)))
        .getSingle();
    expect(dayNumber(row.effectiveFrom!), dayNumber(DateTime(2026, 7, 1)));
    expect(dayNumber(row.effectiveTo!), dayNumber(DateTime(2026, 12, 31)));

    // ③ **显式 Value(null) 能清回 null** —— 这正是「把时段改回不限」那条路径
    //    要的。写成 `Value.absent()` 的话这里会静默保留旧值，而界面上会以为
    //    自己清掉了（`setScheduleSpan` 因此显式构造 `Value`，理由同此）。
    await (db.update(db.shiftScheduleRows)..where((t) => t.id.equals(2))).write(
      const ShiftScheduleRowsCompanion(
        effectiveFrom: Value(null),
        effectiveTo: Value(null),
      ),
    );
    row = await (db.select(db.shiftScheduleRows)
          ..where((t) => t.id.equals(2)))
        .getSingle();
    expect(row.effectiveFrom, isNull);
    expect(row.effectiveTo, isNull);
  });
}
