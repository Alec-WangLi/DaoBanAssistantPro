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
}
