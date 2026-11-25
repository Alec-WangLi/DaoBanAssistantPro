// app/test/backup_service_test.dart
//
// 真实 SQLite 上的备份/恢复：导出 → 暂存 → 启动时替换。
// 覆盖「库、prefs、铃声」三样，以及没有暂存时不误动作。

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/data/app_database.dart';
import 'package:shiftassistantpro/data/seed.dart';
import 'package:shiftassistantpro/features/backup/backup_format.dart';
import 'package:shiftassistantpro/features/backup/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory docs;
  late Directory support;
  late AppDatabase db;
  late File ringtoneFile;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('backup_service_test');
    docs = Directory(p.join(temp.path, 'docs'))..createSync(recursive: true);
    support = Directory(p.join(temp.path, 'support'))
      ..createSync(recursive: true);
    db = AppDatabase.forTesting(
        NativeDatabase(File(p.join(docs.path, kDatabaseFileName))));
    await seedIfEmpty(db);

    final Directory ringtoneDir = Directory(p.join(support.path, 'ringtone'))
      ..createSync(recursive: true);
    ringtoneFile = File(p.join(ringtoneDir.path, 'my_ring.ogg'));
    await ringtoneFile.writeAsBytes(<int>[1, 2, 3, 4]);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'language': 'en',
      'themeMode': 'dark',
      'accentIndex': 2,
      'liquidGlass': true,
      'ringtoneUri': Uri.file(ringtoneFile.path).toString(),
      'ringtoneTitle': 'my_ring',
    });
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    await temp.delete(recursive: true);
  });

  BackupService service() => BackupService(
        db: db,
        supportDirLoader: () async => support,
        now: () => DateTime.utc(2026, 11, 10, 12),
      );

  test('导出包含库、prefs、manifest 与铃声', () async {
    final Uint8List bytes = await service().createBackup();
    final BackupArchive archive =
        decodeBackup(bytes, maxSchemaVersion: AppDatabase.schemaVersionNumber);

    expect(archive.manifest.schemaVersion, AppDatabase.schemaVersionNumber);
    expect(archive.manifest.appVersion, isNotEmpty);
    expect(archive.database, isNotEmpty);
    expect(archive.prefs['language'], <String, dynamic>{'t': 's', 'v': 'en'});
    expect(archive.ringtone, <int>[1, 2, 3, 4]);
    expect(archive.ringtoneName, 'my_ring.ogg');
  });

  test('暂存后启动时替换数据库、prefs 与铃声', () async {
    final Uint8List bytes = await service().createBackup();
    await db.close();

    final BackupManifest manifest = await service().stageRestore(bytes);
    expect(manifest.schemaVersion, AppDatabase.schemaVersionNumber);

    final bool restored = await BackupService.applyPendingRestore(
      documentsDirLoader: () async => docs,
      supportDirLoader: () async => support,
    );
    expect(restored, true);

    // 库换回来了，首启那套排班还在。
    final AppDatabase reopened = AppDatabase.forTesting(
        NativeDatabase(File(p.join(docs.path, kDatabaseFileName))));
    final rows = await reopened.select(reopened.shiftScheduleRows).get();
    expect(rows, isNotEmpty);
    await reopened.close();

    final SharedPreferences sp = await SharedPreferences.getInstance();
    expect(sp.getString('language'), 'en');
    expect(sp.getString('themeMode'), 'dark');
    expect(sp.getInt('accentIndex'), 2);
    expect(sp.getBool('liquidGlass'), true);
    expect(sp.getBool('needsAlarmReplan'), true);
    // 导入后的已读版本必须被写成当前版本，否则重启会先弹更新日志。
    expect(sp.getString('lastSeenVersion'), appVersion);
    expect(sp.getBool('onboarded'), true);

    final String? ringtoneUri = sp.getString('ringtoneUri');
    expect(ringtoneUri, isNotNull);
    expect(File.fromUri(Uri.parse(ringtoneUri!)).existsSync(), true);

    // 暂存目录必须清掉，否则每次启动都会再导一次。
    expect(
        Directory(p.join(support.path, 'pending_restore')).existsSync(), false);
  });

  test('没有暂存时 apply 返回 false 且不动数据库', () async {
    final bool restored = await BackupService.applyPendingRestore(
      documentsDirLoader: () async => docs,
      supportDirLoader: () async => support,
    );
    expect(restored, false);
    expect(File(p.join(docs.path, kDatabaseFileName)).existsSync(), true);
  });

  test('上次替换死在半路：残留的 .bak 先放回去，再被新暂存覆盖', () async {
    final Uint8List bytes = await service().createBackup();
    await db.close();
    await service().stageRestore(bytes);

    // 模拟「旧库已改名成 .bak、新库还没就位」那一刻的现场（旧实现里这一步
    // 是「旧库已删」，只能靠 pending_restore 下次启动重试；新实现能把 .bak 拾回来）。
    final File live = File(p.join(docs.path, kDatabaseFileName));
    final File bak = File('${live.path}.bak');
    expect(live.existsSync(), true);
    live.renameSync(bak.path);
    expect(live.existsSync(), false);

    final bool restored = await BackupService.applyPendingRestore(
      documentsDirLoader: () async => docs,
      supportDirLoader: () async => support,
    );
    expect(restored, true);
    expect(live.existsSync(), true, reason: '新库应当就位');
    expect(bak.existsSync(), false, reason: '换成了就该清场，别留 .bak');
  });

  test('旧库还在时，残留的 .bak 视为更早崩溃的残渣，以现存库为准', () async {
    final Uint8List bytes = await service().createBackup();
    await db.close();
    await service().stageRestore(bytes);

    final File live = File(p.join(docs.path, kDatabaseFileName));
    final File bak = File('${live.path}.bak');
    bak.writeAsBytesSync(const <int>[1, 2, 3]);

    final bool restored = await BackupService.applyPendingRestore(
      documentsDirLoader: () async => docs,
      supportDirLoader: () async => support,
    );
    expect(restored, true);
    expect(live.existsSync(), true);
    expect(bak.existsSync(), false, reason: '残渣要被清掉，不能挡着下一次 rename');
  });

  test('pending 丢失时，残留的 .bak 也要放回（不能开空库）', () async {
    await db.close();
    final File live = File(p.join(docs.path, kDatabaseFileName));
    final File bak = File('${live.path}.bak');
    live.renameSync(bak.path);

    final bool restored = await BackupService.applyPendingRestore(
      documentsDirLoader: () async => docs,
      supportDirLoader: () async => support,
    );
    // 没有暂存 → 不算完成一次导入；但「上次换库死在半路」的现场必须先收拾掉。
    expect(restored, false, reason: '没有暂存就不算一次导入');
    expect(live.existsSync(), true, reason: '旧库必须回来，哪怕 pending_restore 已经没了');
    expect(bak.existsSync(), false);
  });

  test('旧库的 -wal / -shm 跟着一起搬，成功后不留残渣', () async {
    final Uint8List bytes = await service().createBackup();
    await db.close();
    await service().stageRestore(bytes);

    final File live = File(p.join(docs.path, kDatabaseFileName));
    File('${live.path}-wal').writeAsBytesSync(const <int>[7, 7, 7]);
    File('${live.path}-shm').writeAsBytesSync(const <int>[8, 8]);

    final bool restored = await BackupService.applyPendingRestore(
      documentsDirLoader: () async => docs,
      supportDirLoader: () async => support,
    );
    expect(restored, true);
    // 组名必须成组消失：留在原名上会被新库当成自己的日志重放。
    for (final String suffix in const <String>['-wal', '-shm']) {
      expect(File('${live.path}$suffix').existsSync(), false);
      expect(File('${live.path}.bak$suffix').existsSync(), false);
    }
    expect(File('${live.path}.bak').existsSync(), false);
  });
}
