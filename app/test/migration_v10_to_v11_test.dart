// app/test/migration_v10_to_v11_test.dart
//
// v10 → v11：新增一张 `recurring_todos`（重复待办的系列定义），并给
// `schedule_events` 加一列可空的 `series_id`。
//
// 这是一次**纯新增**的迁移（createTable + addColumn），没有重建表、没有搬数据，
// 所以 fixture 只需要抄 `schedule_events` 一张表的 v10 形态 —— 与 v8→v9 那条
// 「纯新增一张表」的判断一致（v9→v10 那种 alterTable 重建才要抄全套）。
//
// 但「纯新增」不等于「不会丢数据」：addColumn 写歪了、或者新表的 DDL 与生成代码
// 对不上，都是**跑起来才发现**。所以老行要逐条断言还在、值还对。
//
// 这一条**只碰 schema 与生成的表 API**（不走 `AppRepository`）：仓库层的那些方法
// 是下一轮才加的，本轮的迁移要能单独验。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// v10 形态的 `schedule_events`（DDL 与 v10 生成代码逐列一致）。
/// drift 默认把 `DateTime` 存成 **unix 秒**，所以时间列都是整数。
const _v10ScheduleEvents = '''
CREATE TABLE schedule_events (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  date INTEGER NOT NULL,
  time_minute INTEGER,
  advance_remind_minutes INTEGER,
  is_completed INTEGER NOT NULL DEFAULT 0,
  alarm_enabled INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
)
''';

/// 排班方案表 —— 本条迁移**不碰它**，但 v11→v12 会给它加两列，而迁移分支一律按
/// **倒序**跑（先 `if (from < 12)`、再 `if (from < 11)`），所以从 v10 升上来时
/// 那一对 `addColumn` 同样会执行。真实 v10 库一定有这张表，fixture 就得有 ——
/// 这与 v10→v11 当初给更早的 fixture 补 `schedule_events` 是同一条。
/// 列是 v10 形态（只差 v12 那两列）。
const _v10ScheduleTable = '''
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
  test('v10 → v11：老待办一条不丢、series_id 为空、新表能写能读', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute(_v10ScheduleEvents);
    raw.execute(_v10ScheduleTable);
    // 两条老待办：一条未完成、一条已完成，值都写全（迁移把值吞了才看得出来）
    raw.execute(
      'INSERT INTO schedule_events '
      '(id, title, date, time_minute, advance_remind_minutes, is_completed, '
      'alarm_enabled, created_at) VALUES (1, ?, ?, ?, ?, 0, 1, ?)',
      [
        '交体检报告',
        DateTime.utc(2026, 10, 2).millisecondsSinceEpoch ~/ 1000,
        17 * 60,
        60,
        DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    raw.execute(
      'INSERT INTO schedule_events '
      '(id, title, date, is_completed, created_at) VALUES (2, ?, ?, 1, ?)',
      [
        '上个月总结',
        DateTime.utc(2026, 9, 1).millisecondsSinceEpoch ~/ 1000,
        DateTime.utc(2026, 8, 30).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    raw.execute('PRAGMA user_version = 10');

    // `NativeDatabase.opened` 把「已经建好 v10 表、user_version 也是 10」的句柄
    // 交给 drift —— 迁移在打开时跑。（与 `migration_v9_to_v10_test.dart` 同一套。）
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    // 从 v10 升上来会一路跑到**最新**的 schema（迁移分支按倒序全部执行），
    // 所以这里跟的是当前的 `schemaVersion`，不是 11 —— 每加一版 schema 都要回来改。
    expect(db.schemaVersion, 13);

    // ① 老待办原样保留，且新列取到的是 null
    final events = await db.select(db.scheduleEvents).get();
    expect(events.length, 2);
    final report = events.firstWhere((e) => e.title == '交体检报告');
    // 比日期一律走 `dayNumber`（自 epoch 天数）：drift 读回来的是**本地** DateTime，
    // 而存进去的是 UTC 纯日期 —— 直接比 DateTime 在东八区就会差 8 小时。
    // 这也是全仓比「同一天」的既有约定（`isSameDay` / `dayNumber`）。
    expect(dayNumber(report.date), dayNumber(DateTime(2026, 10, 2)));
    expect(report.timeMinute, 17 * 60);
    expect(report.advanceRemindMinutes, 60);
    expect(report.alarmEnabled, isTrue);
    expect(report.isCompleted, isFalse);
    expect(report.seriesId, isNull, reason: '老待办不该凭空挂上系列');
    expect(events.firstWhere((e) => e.title == '上个月总结').isCompleted, isTrue);

    // ② 新表在，且能写能读（用生成的表 API，不经仓库层）
    final id = await db.into(db.recurringSeriesRows).insert(
          RecurringSeriesRowsCompanion.insert(
            title: '周三例会',
            startDate: DateTime.utc(2026, 10, 14),
            weekdays: const Value(1 << 2),
            timeMinute: const Value(9 * 60),
            advanceRemindMinutes: const Value(0),
            createdAt: DateTime.now(),
          ),
        );
    final series = await db.select(db.recurringSeriesRows).getSingle();
    expect(series.id, id);
    expect(series.title, '周三例会');
    expect(series.weekdays, 1 << 2);
    expect(dayNumber(series.startDate), dayNumber(DateTime(2026, 10, 14)));
    // 带默认值的几列要真的落到默认值上（DDL 写歪了这里就会红）
    expect(series.repeatType, 0, reason: '默认「每天」');
    expect(series.monthDay, 1);
    expect(series.enabled, isTrue);
    expect(series.alarmEnabled, isFalse);
    expect(series.skipThrough, isNull);

    // ③ 新列可写
    await (db.update(db.scheduleEvents)..where((e) => e.id.equals(1)))
        .write(ScheduleEventsCompanion(seriesId: Value(id)));
    final after = await (db.select(db.scheduleEvents)
          ..where((e) => e.id.equals(1)))
        .getSingle();
    expect(after.seriesId, id);
  });
}
