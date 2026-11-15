// app/test/support/migration_fixtures.dart
//
// 迁移 fixture 的共享 DDL。
//
// `shift_class_rows` 从 v10 起不再有 `alarm_minute`。所有 `from >= 6` 且
// `< 16` 的 fixture 都必须建这张表：`from < 16` 会给它加 `is_night`，而迁移
// 分支按**倒序**跑 —— 只建「本条迁移要碰的表」会在 `ALTER TABLE` 上抛
// `no such table: shift_class_rows`（真机不会，只有这个仓库的最小 fixture 会）。
//
// 5 个 fixture 共用这一份，避免把同一段 DDL 抄五遍。
const String v10ShiftClassRowsDdl = '''
CREATE TABLE shift_class_rows (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  schedule_id INTEGER NOT NULL,
  "order" INTEGER NOT NULL,
  name TEXT NOT NULL,
  abbr TEXT,
  start_minute INTEGER,
  end_minute INTEGER,
  is_rest INTEGER NOT NULL DEFAULT 0,
  color INTEGER NOT NULL DEFAULT 4284186623,
  alarm_enabled INTEGER NOT NULL DEFAULT 0
)
''';
