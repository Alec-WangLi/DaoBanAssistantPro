// app/test/migration_v11_to_v13_test.dart
//
// v11 → **最新**（中间跨了 v12 的「加时段两列」与 v13 的「段搬进独立的表、
// 那两列删掉」）。
//
// 为什么这条值得留着：**迁移分支按倒序跑**，`from < 13` 那段在 v11 库上会先执行，
// 而它要读的两列**那时候还不存在**（是 `from < 12` 那段加的，排在后面）。
// 所以这段代码里必须按版本判断再读列 —— 漏了就会在从 v11 升上来的**真机**上
// 抛 `no such column: effective_from`（只在长链升级上现形，单测不跑就发现不了）。
//
// 断言：老方案一条不丢；**段表建了、而且是空的**（v11 从来没有过时段）。
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v11 形态的 `shift_schedule_rows`（DDL 与 v11 生成代码逐列一致）：
/// 没有 v12 加的那两列，也没有 v13 的段表。
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
  test('v11 → 最新：老方案原样、段表建了但是空的', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute(_v11ScheduleTable);
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

    // ① 老方案一条不丢、值原样
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

    // ② 段表建出来了，而且**是空的** —— v11 库从来没有过时段，
    //    `from < 13` 那段必须跳过搬数据（那时候两列还不存在）。
    expect(await db.select(db.scheduleSpanRows).get(), isEmpty);

    // ③ 段表现在可写可读
    final spanId = await db.into(db.scheduleSpanRows).insert(
          ScheduleSpanRowsCompanion.insert(
            scheduleId: 2,
            startDate: Value(DateTime.utc(2026, 7, 1)),
          ),
        );
    final span = (await db.select(db.scheduleSpanRows).getSingle());
    expect(span.id, spanId);
    expect(span.scheduleId, 2);
    expect(dayNumber(span.startDate!), dayNumber(DateTime(2026, 7, 1)));
    expect(span.endDate, isNull, reason: '只设起点 = 一直持续');
  });
}
