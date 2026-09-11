// app/test/seed_locale_test.dart
//
// 落库路径的语言必须跟着用户的语言走。
//
// `defaultSchedule()` 一旦按当前语言生成，就暴露出一条竞态：
// `activeScheduleProvider` 首启播种时，语言可能还没从 SharedPreferences
// 读回来，于是英文用户的第一套排班是中文的。本文件同时守着「生成」与
// 「落库」两段。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_database.dart';
import 'package:shiftassistantpro/data/seed.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/cjk.dart';

void main() {
  setUpAll(() {
    // 每个用例各建一个内存库做隔离，drift 会为「同名库建了多次」刷警告。
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test('英文 locale 下 defaultSchedule() 不产出中文', () {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';

    final s = defaultSchedule();
    expect(hasCjk(s.name), isFalse, reason: '方案名含中文：${s.name}');
    for (final n in s.teamNames) {
      expect(hasCjk(n), isFalse, reason: '班组名含中文：$n');
    }
    for (final c in s.classes) {
      expect(hasCjk(c.name), isFalse, reason: '班次名含中文：${c.name}');
      expect(hasCjk(c.abbr!), isFalse, reason: '班次简称含中文：${c.abbr}');
    }
  });

  test('中文 locale 下 defaultSchedule() 保持原样', () {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'zh';

    final s = defaultSchedule();
    expect(s.name, '四班两倒');
    expect(s.teamNames, ['一班', '二班', '三班', '四班']);
    expect(s.classes.map((c) => c.name).toList(),
        ['白班', '上夜班', '下夜班', '大休']);
  });

  test('英文 locale 下首启播种写进库里的不是中文', () async {
    final previous = L10n.locale;
    addTearDown(() => L10n.locale = previous);
    L10n.locale = 'en';

    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await seedIfEmpty(db);

    final sched = (await db.select(db.shiftScheduleRows).get()).single;
    expect(hasCjk(sched.name), isFalse,
        reason: '落库的方案名含中文：${sched.name}');
    expect(hasCjk(sched.teamNames), isFalse,
        reason: '落库的班组名含中文：${sched.teamNames}');

    final classes = await db.select(db.shiftClassRows).get();
    expect(classes, isNotEmpty);
    for (final c in classes) {
      expect(hasCjk(c.name), isFalse, reason: '落库的班次名含中文：${c.name}');
      expect(hasCjk(c.abbr!), isFalse, reason: '落库的简称含中文：${c.abbr}');
    }
  });

  test('首启播种只在空库上发生', () async {
    // 已有方案时不该再塞一份默认的进去（迁移与老用户升级路径依赖这点）。
    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await seedIfEmpty(db);
    await seedIfEmpty(db);

    expect((await db.select(db.shiftScheduleRows).get()).length, 1);
  });
}
