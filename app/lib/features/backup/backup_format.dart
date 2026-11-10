// app/lib/features/backup/backup_format.dart
//
// 备份文件的容器格式：一个 zip，里面固定放
//   · manifest.json —— 格式版本、App 版本、Drift schemaVersion、导出时刻
//   · data.sqlite   —— `VACUUM INTO` 出来的一致性快照
//   · prefs.json    —— SharedPreferences 的类型化快照
//   · ringtone/…    —— 用户自选铃声（可选）
//
// 这一层是纯函数：不碰文件系统、不碰插件，方便单测。
// 真正的读写盘与选择器在 `backup_service.dart` / `backup_io.dart`。

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 备份容器格式版本。容器结构发生变化时才 +1。
const int kBackupFormatVersion = 1;

/// 备份文件扩展名（自定义，避免被文件管理器当成 zip 直接打开）。
const String kBackupExtension = 'dshbackup';

/// 备份只允许在本 App 与它的后继包名之间流通。
const String kBackupAppId = 'com.daoban.shiftassistantpro';

class BackupFormatException implements Exception {
  const BackupFormatException(this.code, [this.detail]);

  /// `invalid_archive` / `bad_manifest` / `format_too_new` /
  /// `schema_too_new` / `missing_database` / `bad_prefs`
  final String code;
  final String? detail;

  @override
  String toString() =>
      'BackupFormatException($code${detail == null ? '' : ': $detail'})';
}

class BackupManifest {
  const BackupManifest({
    required this.format,
    required this.appId,
    required this.appVersion,
    required this.schemaVersion,
    required this.exportedAt,
  });

  final int format;
  final String appId;
  final String appVersion;
  final int schemaVersion;
  final DateTime exportedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'format': format,
        'appId': appId,
        'appVersion': appVersion,
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
      };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final int? format = json['format'] as int?;
    final String? appId = json['appId'] as String?;
    final String? appVersion = json['appVersion'] as String?;
    final int? schemaVersion = json['schemaVersion'] as int?;
    final String? exportedAt = json['exportedAt'] as String?;
    if (format == null ||
        appId == null ||
        appVersion == null ||
        schemaVersion == null ||
        exportedAt == null) {
      throw const BackupFormatException('bad_manifest');
    }
    final DateTime? when = DateTime.tryParse(exportedAt);
    if (when == null) {
      throw const BackupFormatException('bad_manifest');
    }
    return BackupManifest(
      format: format,
      appId: appId,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      exportedAt: when,
    );
  }
}

class BackupPayload {
  const BackupPayload({
    required this.database,
    required this.prefs,
    this.ringtone,
    this.ringtoneName,
  });

  final Uint8List database;
  final Map<String, dynamic> prefs;
  final Uint8List? ringtone;
  final String? ringtoneName;
}

/// 把 SharedPreferences 全部键值编码成可 JSON 化的结构。
///
/// 每个值带一个类型标签：`s` 字符串、`b` 布尔、`i` 整数、`d` 浮点、
/// `ls` 字符串数组。遇到未知类型直接跳过（宁可不备份，也不猜）。
Map<String, dynamic> encodePrefs(SharedPreferences sp) {
  final Map<String, dynamic> out = <String, dynamic>{};
  for (final String key in sp.getKeys()) {
    final Object? value = sp.get(key);
    if (value is String) {
      out[key] = <String, dynamic>{'t': 's', 'v': value};
    } else if (value is bool) {
      out[key] = <String, dynamic>{'t': 'b', 'v': value};
    } else if (value is int) {
      out[key] = <String, dynamic>{'t': 'i', 'v': value};
    } else if (value is double) {
      out[key] = <String, dynamic>{'t': 'd', 'v': value};
    } else if (value is List<String>) {
      out[key] = <String, dynamic>{'t': 'ls', 'v': value};
    }
  }
  return out;
}

/// 用备份里的 prefs 覆盖当前 prefs。**会先 `clear()`** —— 备份就是完整状态。
Future<void> applyPrefs(
  SharedPreferences sp,
  Map<String, dynamic> data, {
  String? ringtoneUriOverride,
}) async {
  await sp.clear();
  for (final MapEntry<String, dynamic> entry in data.entries) {
    final Object? raw = entry.value;
    if (raw is! Map) {
      throw const BackupFormatException('bad_prefs');
    }
    final String? type = raw['t'] as String?;
    final Object? value = raw['v'];
    switch (type) {
      case 's':
        if (value is String) await sp.setString(entry.key, value);
        break;
      case 'b':
        if (value is bool) await sp.setBool(entry.key, value);
        break;
      case 'i':
        if (value is int) await sp.setInt(entry.key, value);
        break;
      case 'd':
        if (value is num) await sp.setDouble(entry.key, value.toDouble());
        break;
      case 'ls':
        if (value is List) {
          await sp.setStringList(
              entry.key, value.whereType<String>().toList(growable: false));
        }
        break;
      default:
        // 未知类型忽略，兼容未来新增的类型。
        break;
    }
  }
  if (ringtoneUriOverride != null) {
    await sp.setString('ringtoneUri', ringtoneUriOverride);
  }
}

/// 打包成备份字节。
Uint8List encodeBackup(BackupManifest manifest, BackupPayload payload) {
  final Archive archive = Archive();
  final List<int> manifestBytes =
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
  final List<int> prefsBytes = utf8.encode(jsonEncode(payload.prefs));

  archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  archive.addFile(
      ArchiveFile('data.sqlite', payload.database.length, payload.database));
  archive.addFile(ArchiveFile('prefs.json', prefsBytes.length, prefsBytes));

  final Uint8List? ringtone = payload.ringtone;
  final String? ringtoneName = payload.ringtoneName;
  if (ringtone != null && ringtoneName != null && ringtoneName.isNotEmpty) {
    archive.addFile(
        ArchiveFile('ringtone/$ringtoneName', ringtone.length, ringtone));
  }

  return ZipEncoder().encodeBytes(archive);
}

/// 解包并校验。`maxSchemaVersion` 由调用方传当前 App 的 Drift schemaVersion。
BackupArchive decodeBackup(Uint8List bytes, {required int maxSchemaVersion}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw BackupFormatException('invalid_archive', e.toString());
  }
  if (archive.files.isEmpty) {
    throw const BackupFormatException('invalid_archive', 'empty archive');
  }

  final ArchiveFile? manifestFile = archive.findFile('manifest.json');
  final ArchiveFile? dataFile = archive.findFile('data.sqlite');
  final ArchiveFile? prefsFile = archive.findFile('prefs.json');
  if (manifestFile == null) {
    throw const BackupFormatException('bad_manifest');
  }
  if (dataFile == null) {
    throw const BackupFormatException('missing_database');
  }
  if (prefsFile == null) {
    throw const BackupFormatException('bad_prefs');
  }

  final Map<String, dynamic> manifestJson;
  final Map<String, dynamic> prefsJson;
  try {
    manifestJson =
        jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
    prefsJson =
        jsonDecode(utf8.decode(prefsFile.content)) as Map<String, dynamic>;
  } catch (e) {
    throw BackupFormatException('bad_manifest', e.toString());
  }

  final BackupManifest manifest = BackupManifest.fromJson(manifestJson);
  if (manifest.format > kBackupFormatVersion) {
    throw const BackupFormatException('format_too_new');
  }
  if (manifest.appId != kBackupAppId) {
    throw const BackupFormatException('bad_manifest', 'appId mismatch');
  }
  if (manifest.schemaVersion > maxSchemaVersion) {
    throw BackupFormatException(
        'schema_too_new', '${manifest.schemaVersion} > $maxSchemaVersion');
  }

  Uint8List? ringtone;
  String? ringtoneName;
  for (final ArchiveFile file in archive.files) {
    if (file.name.startsWith('ringtone/') && file.size > 0) {
      final String name = file.name.substring('ringtone/'.length);
      if (name.isNotEmpty && !name.contains('/') && !name.contains('\\')) {
        ringtone = file.content;
        ringtoneName = name;
      }
      break;
    }
  }

  return BackupArchive(
    manifest: manifest,
    database: dataFile.content,
    prefs: prefsJson,
    ringtone: ringtone,
    ringtoneName: ringtoneName,
  );
}

class BackupArchive {
  const BackupArchive({
    required this.manifest,
    required this.database,
    required this.prefs,
    this.ringtone,
    this.ringtoneName,
  });

  final BackupManifest manifest;
  final Uint8List database;
  final Map<String, dynamic> prefs;
  final Uint8List? ringtone;
  final String? ringtoneName;
}
