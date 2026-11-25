// app/test/backup_format_test.dart
//
// 备份容器格式的纯函数护栏：打包/解包、prefs 类型、版本与 schema 校验。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/features/backup/backup_format.dart';
import 'package:shared_preferences/shared_preferences.dart';

BackupManifest _manifest({int schemaVersion = 15}) => BackupManifest(
      format: kBackupFormatVersion,
      appId: kBackupAppId,
      appVersion: '0.13.4',
      schemaVersion: schemaVersion,
      exportedAt: DateTime.utc(2026, 11, 10, 12, 0, 0),
    );

BackupPayload _payload() => BackupPayload(
      database: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      prefs: <String, dynamic>{
        'language': <String, dynamic>{'t': 's', 'v': 'en'},
        'liquidGlass': <String, dynamic>{'t': 'b', 'v': true},
        'accentIndex': <String, dynamic>{'t': 'i', 'v': 3},
        'ratio': <String, dynamic>{'t': 'd', 'v': 1.5},
        'recent': <String, dynamic>{
          't': 'ls',
          'v': <String>['a', 'b'],
        },
      },
      ringtone: Uint8List.fromList(<int>[9, 8, 7]),
      ringtoneName: 'my_ring.ogg',
    );

void main() {
  test('manifest 往返', () {
    final BackupManifest before = _manifest();
    final BackupManifest after =
        BackupManifest.fromJson(jsonDecode(jsonEncode(before.toJson()))
            as Map<String, dynamic>);
    expect(after.format, before.format);
    expect(after.appId, before.appId);
    expect(after.schemaVersion, before.schemaVersion);
    expect(after.exportedAt.toUtc(), before.exportedAt.toUtc());
  });

  test('prefs 编码与恢复保留类型', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'language': 'en',
      'liquidGlass': true,
      'accentIndex': 2,
      'ratio': 0.75,
      'recent': <String>['a', 'b'],
    });
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final Map<String, dynamic> encoded = encodePrefs(sp);

    await sp.clear();
    await applyPrefs(sp, encoded);

    expect(sp.getString('language'), 'en');
    expect(sp.getBool('liquidGlass'), true);
    expect(sp.getInt('accentIndex'), 2);
    expect(sp.getDouble('ratio'), 0.75);
    expect(sp.getStringList('recent'), <String>['a', 'b']);
  });

  test('备份打包 / 解包往返', () {
    final Uint8List bytes = encodeBackup(_manifest(), _payload());
    final BackupArchive decoded = decodeBackup(bytes, maxSchemaVersion: 15);
    expect(decoded.manifest.schemaVersion, 15);
    expect(decoded.database, <int>[1, 2, 3, 4, 5]);
    expect(decoded.prefs['language'],
        <String, dynamic>{'t': 's', 'v': 'en'});
    expect(decoded.ringtone, <int>[9, 8, 7]);
    expect(decoded.ringtoneName, 'my_ring.ogg');
  });

  test('损坏的 zip 被拒绝', () {
    expect(
      () => decodeBackup(
          Uint8List.fromList(<int>[1, 2, 3, 4]), maxSchemaVersion: 15),
      throwsA(isA<BackupFormatException>()
          .having((e) => e.code, 'code', 'invalid_archive')),
    );
  });

  test('schema 比当前新时拒绝', () {
    final Uint8List bytes = encodeBackup(_manifest(schemaVersion: 99), _payload());
    expect(
      () => decodeBackup(bytes, maxSchemaVersion: 15),
      throwsA(isA<BackupFormatException>()
          .having((e) => e.code, 'code', 'schema_too_new')),
    );
  });

  test('appId 不匹配时拒绝', () {
    final BackupManifest other = BackupManifest(
      format: kBackupFormatVersion,
      appId: 'com.example.other',
      appVersion: '1.0.0',
      schemaVersion: 15,
      exportedAt: DateTime.utc(2026, 11, 10),
    );
    final Uint8List bytes = encodeBackup(other, _payload());
    expect(
      () => decodeBackup(bytes, maxSchemaVersion: 15),
      throwsA(isA<BackupFormatException>()
          .having((e) => e.code, 'code', 'bad_manifest')),
    );
  });
}
