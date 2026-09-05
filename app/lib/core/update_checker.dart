import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 更新信息：版本号 + 下载直链 + 是否测试版（预发布）+ APK 资源文件名。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.isPrerelease,
    this.assetName,
  });

  final String version;
  final String url;
  final bool isPrerelease;

  /// GitHub Release 资产的 APK 文件名（仅用于本地保存命名）。
  final String? assetName;
}

/// 更新检查结果：最新正式版 + 最新测试版。
class UpdateCheckResult {
  const UpdateCheckResult({
    this.latestStable,
    this.latestPrerelease,
    this.error = false,
  });

  final UpdateInfo? latestStable;
  final UpdateInfo? latestPrerelease;
  final bool error;
}

/// 检查 GitHub 上的最新正式版（0.X.0）与最新测试版（预发布）。
///
/// 仓库为公开，无需鉴权即可拉取 `/releases` 全列表（未认证限 60 次/小时/IP，
/// 冷启动每日一次静默检查足够）。按语义版本号自己算出两个「最新」，
/// 不依赖 latest 标志（避免缓存/滞后）。
class UpdateChecker {
  UpdateChecker._();

  static const _owner = 'Alec-WangLi';
  static const _repo = 'DaoBanAssistantPro';

  /// 拉取所有 Release，算出最新正式版（非预发布）与最新测试版（预发布）。
  static Future<UpdateCheckResult> checkUpdates() async {
    final uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases?per_page=100');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(uri);
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'DaoBanAssistantPro')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        return const UpdateCheckResult(error: true);
      }
      final list = jsonDecode(body) as List<dynamic>;
      UpdateInfo? stable;
      UpdateInfo? prerelease;
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        if (m['draft'] == true) continue;
        final tag = (m['tag_name'] as String?) ?? '';
        final version = tag.startsWith('v') ? tag.substring(1) : tag;
        if (version.isEmpty) continue;
        final isPre = m['prerelease'] == true;
        final (url, assetName) = _apkAsset(m);
        final info = UpdateInfo(
          version: version,
          url: url,
          isPrerelease: isPre,
          assetName: assetName,
        );
        if (isPre) {
          if (prerelease == null ||
              compareVersion(version, prerelease.version) > 0) {
            prerelease = info;
          }
        } else {
          if (stable == null || compareVersion(version, stable.version) > 0) {
            stable = info;
          }
        }
      }
      return UpdateCheckResult(
        latestStable: stable,
        latestPrerelease: prerelease,
      );
    } catch (_) {
      return const UpdateCheckResult(error: true);
    } finally {
      client.close(force: true);
    }
  }

  /// 直接下载 APK 的 `browser_download_url`（公开仓库无需鉴权）到临时目录，
  /// 返回文件（失败返回 null）。
  ///
  /// [onProgress] 回传 0–100 的百分比；无法得知总量时回传 -1（表示不确定进度）。
  static Future<File?> downloadApk(
    UpdateInfo info, {
    void Function(int percent)? onProgress,
  }) async {
    final url = info.url;
    if (url.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'DaoBanAssistantPro');
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }

      final total = res.contentLength;
      if (total <= 0) onProgress?.call(-1);

      final dir = await getTemporaryDirectory();
      // 资产名只取 basename，剔除路径分隔/父目录，防恶意资产名造成路径穿越。
      final raw = (info.assetName ?? 'update-${info.version}.apk')
          .split(RegExp(r'[/\\]'))
          .last;
      final name = (raw.isEmpty || raw == '.' || raw == '..')
          ? 'update-${info.version}.apk'
          : raw;
      final file = File('${dir.path}/$name');
      final sink = file.openWrite();
      var received = 0;
      var lastPct = -1;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final pct = ((received * 100) ~/ total).clamp(0, 100).toInt();
            if (pct != lastPct) {
              lastPct = pct;
              onProgress?.call(pct);
            }
          }
        }
      } finally {
        await sink.close();
      }
      return file;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 优先返回 APK 的下载直链与资产文件名，否则回退到 Release 页面。
  static (String url, String? assetName) _apkAsset(Map<String, dynamic> m) {
    var url = (m['html_url'] as String?) ?? '';
    String? assetName;
    final assets = m['assets'] as List<dynamic>? ?? const [];
    for (final a in assets) {
      final am = a as Map<String, dynamic>;
      final name = (am['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        url = (am['browser_download_url'] as String?) ?? url;
        assetName = name;
        break;
      }
    }
    return (url, assetName);
  }

  /// 语义版本比较（X.Y.Z）：a>b 正数、相等 0、a<b 负数。
  static int compareVersion(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    for (var i = 0; i < 3; i++) {
      final d = pa[i] - pb[i];
      if (d != 0) return d;
    }
    return 0;
  }

  static List<int> _parse(String v) {
    final parts = v.split('.');
    final out = <int>[0, 0, 0];
    for (var i = 0; i < 3 && i < parts.length; i++) {
      out[i] = int.tryParse(parts[i]) ?? 0;
    }
    return out;
  }
}