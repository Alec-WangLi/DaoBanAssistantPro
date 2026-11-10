// app/lib/features/backup/backup_io.dart
//
// 备份文件的系统交互：保存（SAF 创建文档）、选择（SAF 打开文档）、重启 App。
// 大块字节不进 MethodChannel —— Dart 先写临时文件，原生只负责复制。

import 'package:flutter/services.dart';

class BackupIo {
  static const MethodChannel _channel =
      MethodChannel('com.daoban.shiftassistantpro/settings');

  /// 让用户选保存位置并把 [sourcePath] 复制过去。
  /// 用户取消返回 null；失败抛 [PlatformException]。
  static Future<String?> save({
    required String suggestedName,
    required String sourcePath,
  }) async {
    final Map<dynamic, dynamic>? raw = await _channel.invokeMethod<Map>(
      'saveBackupFile',
      <String, Object?>{'name': suggestedName, 'sourcePath': sourcePath},
    );
    return raw?['uri'] as String?;
  }

  /// 让用户选一个备份文件；原生把它复制到缓存目录并返回本地路径。
  /// 用户取消返回 null；失败抛 [PlatformException]。
  static Future<String?> pick() async {
    final Map<dynamic, dynamic>? raw =
        await _channel.invokeMethod<Map>('pickBackupFile');
    return raw?['path'] as String?;
  }

  /// 冷重启 App。调用后进程会结束，导入的数据在下次 `main()` 里生效。
  static Future<void> restart() async {
    await _channel.invokeMethod<void>('restartApp');
  }
}
