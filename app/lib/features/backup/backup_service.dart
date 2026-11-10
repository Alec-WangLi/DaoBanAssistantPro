// app/lib/features/backup/backup_service.dart
//
// 备份的读写盘部分：
//   · 导出：`VACUUM INTO` 一致性快照 + prefs + 自选铃声 → zip
//   · 导入：先解到 `pending_restore/` 暂存；**下次启动时**才原子替换数据库
//
// 为什么导入要等重启：Drift 的连接在 App 生命周期里一直开着，运行中换库文件
// 会留下 WAL 与旧连接，轻则读到半截数据，重则库损坏。暂存 + 重启是唯一稳妥的
// 做法；`main()` 在任何数据库打开之前调用 [applyPendingRestore]。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_info.dart';
import '../../core/clock.dart';
import '../../data/app_database.dart';
import 'backup_format.dart';

/// 备份文件上限：正常备份通常 < 5 MB；200 MB 足够挡住误选的大文件。
const int kMaxBackupBytes = 200 * 1024 * 1024;

/// 单个铃声上限（与原生选择器一致）。
const int kMaxRingtoneBytes = 50 * 1024 * 1024;

/// Drift 默认库文件名（`driftDatabase(name: 'shiftassistantpro')`）。
const String kDatabaseFileName = 'shiftassistantpro.sqlite';

class BackupService {
  BackupService({
    required AppDatabase db,
    Future<SharedPreferences> Function()? prefsLoader,
    Future<Directory> Function()? supportDirLoader,
    DateTime Function()? now,
    String appVersionOverride = appVersion,
  })  : _db = db,
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
        _supportDirLoader =
            supportDirLoader ?? getApplicationSupportDirectory,
        _now = now ?? (() => appNow()),
        _appVersion = appVersionOverride;

  final AppDatabase _db;
  final Future<SharedPreferences> Function() _prefsLoader;
  final Future<Directory> Function() _supportDirLoader;
  final DateTime Function() _now;
  final String _appVersion;

  /// 生成备份字节。数据库用 `VACUUM INTO` 取一致快照（连同 WAL）。
  Future<Uint8List> createBackup() async {
    final Directory support = await _supportDirLoader();
    final File temp = File(p.join(support.path, 'backup_vacuum.sqlite'));
    if (await temp.exists()) {
      await temp.delete();
    }

    try {
      await _db.customStatement('VACUUM INTO ?', <Object?>[temp.path]);
    } catch (_) {
      // 少数 SQLite 版本不接受参数绑定，退回转义字面量。
      if (await temp.exists()) await temp.delete();
      final String escaped = temp.path.replaceAll("'", "''");
      await _db.customStatement("VACUUM INTO '$escaped'");
    }

    final Uint8List database = await temp.readAsBytes();
    await temp.delete();

    final SharedPreferences sp = await _prefsLoader();
    final Map<String, dynamic> prefs = encodePrefs(sp);

    Uint8List? ringtone;
    String? ringtoneName;
    final String? ringtoneUri = sp.getString('ringtoneUri');
    if (ringtoneUri != null && ringtoneUri.isNotEmpty) {
      final Uri? uri = Uri.tryParse(ringtoneUri);
      if (uri != null && uri.scheme == 'file') {
        final File file = File.fromUri(uri);
        if (await file.exists() && await file.length() <= kMaxRingtoneBytes) {
          ringtone = await file.readAsBytes();
          ringtoneName = _safeName(p.basename(file.path));
        }
      }
    }

    final BackupManifest manifest = BackupManifest(
      format: kBackupFormatVersion,
      appId: kBackupAppId,
      appVersion: _appVersion,
      schemaVersion: AppDatabase.schemaVersionNumber,
      exportedAt: _now(),
    );

    return encodeBackup(
      manifest,
      BackupPayload(
        database: database,
        prefs: prefs,
        ringtone: ringtone,
        ringtoneName: ringtoneName,
      ),
    );
  }

  /// 校验并暂存。真正的替换发生在下次启动的 [applyPendingRestore]。
  Future<BackupManifest> stageRestore(Uint8List bytes) async {
    if (bytes.length > kMaxBackupBytes) {
      throw const BackupFormatException('invalid_archive', 'too large');
    }
    final BackupArchive archive = decodeBackup(
      bytes,
      maxSchemaVersion: AppDatabase.schemaVersionNumber,
    );

    final Directory support = await _supportDirLoader();
    final Directory pending = Directory(p.join(support.path, 'pending_restore'));
    final Directory staging =
        Directory(p.join(support.path, 'pending_restore.tmp'));
    // 先写到临时目录，整套写完再 rename —— 中途失败不会留下半套暂存。
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    await File(p.join(staging.path, 'data.sqlite'))
        .writeAsBytes(archive.database, flush: true);
    await File(p.join(staging.path, 'prefs.json'))
        .writeAsString(jsonEncode(archive.prefs), flush: true);

    final Uint8List? ringtone = archive.ringtone;
    final String? rawName = archive.ringtoneName;
    if (ringtone != null && rawName != null) {
      final String name = _safeName(rawName);
      final Directory dir = Directory(p.join(staging.path, 'ringtone'));
      await dir.create(recursive: true);
      await File(p.join(dir.path, name)).writeAsBytes(ringtone, flush: true);
      await File(p.join(staging.path, 'ringtone_name.txt'))
          .writeAsString(name, flush: true);
    }

    if (await pending.exists()) {
      await pending.delete(recursive: true);
    }
    await staging.rename(pending.path);
    return archive.manifest;
  }

  /// 在 App 启动、任何数据库打开之前调用。
  ///
  /// 返回 true 表示这次启动完成了一次导入。替换顺序刻意做成「先写好新库、
  /// 再删旧库与 WAL、最后 rename」——中途失败时旧库仍在，下次还能重试。
  static Future<bool> applyPendingRestore({
    Future<Directory> Function()? documentsDirLoader,
    Future<Directory> Function()? supportDirLoader,
  }) async {
    final Future<Directory> Function() docsLoader =
        documentsDirLoader ?? getApplicationDocumentsDirectory;
    final Future<Directory> Function() supportLoader =
        supportDirLoader ?? getApplicationSupportDirectory;

    final Directory support = await supportLoader();
    final Directory pending = Directory(p.join(support.path, 'pending_restore'));
    final File pendingDb = File(p.join(pending.path, 'data.sqlite'));
    final File prefsFile = File(p.join(pending.path, 'prefs.json'));
    // 库和 prefs 缺一不可：缺任何一件都说明暂存不完整，直接丢掉，
    // **绝对不能**先把库换上去再说。
    if (!await pendingDb.exists() || !await prefsFile.exists()) {
      if (await pending.exists()) {
        await pending.delete(recursive: true);
      }
      return false;
    }

    final Directory docs = await docsLoader();
    final String dbPath = p.join(docs.path, kDatabaseFileName);
    final File restored = File('$dbPath.restore');
    if (await restored.exists()) {
      await restored.delete();
    }
    await pendingDb.copy(restored.path);

    // 旧库的 WAL / SHM 必须先删，否则它们会被当成新库的日志重放。
    for (final String suffix in const <String>['-wal', '-shm']) {
      final File sidecar = File('$dbPath$suffix');
      if (await sidecar.exists()) {
        await sidecar.delete();
      }
    }
    final File oldDb = File(dbPath);
    if (await oldDb.exists()) {
      await oldDb.delete();
    }
    await restored.rename(dbPath);

    final Map<String, dynamic> prefs =
        jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;

    String? ringtoneUri;
    final File ringtoneNameFile =
        File(p.join(pending.path, 'ringtone_name.txt'));
    if (await ringtoneNameFile.exists()) {
      final String name = _safeName(await ringtoneNameFile.readAsString());
      final File source = File(p.join(pending.path, 'ringtone', name));
      if (await source.exists()) {
        final Directory dir = Directory(p.join(support.path, 'ringtone'));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
        await dir.create(recursive: true);
        final File dest = File(p.join(dir.path, name));
        await source.copy(dest.path);
        ringtoneUri = Uri.file(dest.path).toString();
      }
    }

    final SharedPreferences sp = await SharedPreferences.getInstance();
    await applyPrefs(sp, prefs, ringtoneUriOverride: ringtoneUri);

    if (ringtoneUri == null) {
      // 备份里没有铃声，但 prefs 里可能留着一条指向旧文件的路径：
      // 留着它，闹钟到点会静默失声。清掉，回落到内置铃声。
      final String? uriStr = sp.getString('ringtoneUri');
      final Uri? uri = uriStr == null ? null : Uri.tryParse(uriStr);
      if (uri == null ||
          uri.scheme != 'file' ||
          !File.fromUri(uri).existsSync()) {
        await sp.remove('ringtoneUri');
        await sp.remove('ringtoneTitle');
      }
    }

    // 导入后排班全变了，系统里旧闹钟必须按新库重排（由 HomeShell 消费）。
    await sp.setBool('needsAlarmReplan', true);
    await pending.delete(recursive: true);
    return true;
  }

  static String _safeName(String raw) {
    final String base = p.basename(raw.trim());
    final String safe = base.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return safe.isEmpty ? 'ringtone' : safe;
  }
}
