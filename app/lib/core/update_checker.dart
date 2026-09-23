import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
/// 仓库为公开，无需鉴权。**主通道是仓库根目录的 `latest.json` 发布清单**
/// （`raw.githubusercontent.com` 静态直读，不占任何限额，且由
/// `scripts/release.ps1` 每次发版后自动同步到 main）；GitHub API 只作兜底。
///
/// 为什么不是 API 优先：未认证的 `/releases` 限 60 次/小时/IP，共享出口很容易
/// 耗尽（实测常年 403），拿它当主通道等于大部分时间都在走回退。反过来之后，
/// 两条通道还留在**不同的域名**上 —— 只被墙了一个的网络也是有的，都留着才兜得住。
class UpdateChecker {
  UpdateChecker._();

  static const _owner = 'Alec-WangLi';
  static const _repo = 'DaoBanAssistantPro';
  static const _timeout = Duration(seconds: 8);

  static final _manifestUri = Uri.parse(
      'https://raw.githubusercontent.com/$_owner/$_repo/main/latest.json');
  static final _releasesUri = Uri.parse(
      'https://api.github.com/repos/$_owner/$_repo/releases?per_page=100');

  /// 取数的接缝：测试换成假的就能完全脱离网络。返回 null 表示网络异常。
  @visibleForTesting
  static Future<({int status, String body})?> Function(
      Uri uri, Duration timeout) fetch = _httpGetText;

  /// 检查最新版本：先读发布清单，不通或内容坏了再走 GitHub API。
  static Future<UpdateCheckResult> checkUpdates() async {
    final viaManifest = await _checkViaManifest();
    if (!viaManifest.error) return viaManifest;
    return _checkViaApi();
  }

  /// 主通道：读发布清单。
  static Future<UpdateCheckResult> _checkViaManifest() async {
    final body = await _fetchBody(_manifestUri);
    if (body == null) return const UpdateCheckResult(error: true);
    try {
      return parseManifest(body);
    } catch (_) {
      return const UpdateCheckResult(error: true);
    }
  }

  /// 兜底通道：拉取所有 Release。
  static Future<UpdateCheckResult> _checkViaApi() async {
    final body = await _fetchBody(_releasesUri);
    if (body == null) return const UpdateCheckResult(error: true);
    try {
      return parseReleases(body);
    } catch (_) {
      return const UpdateCheckResult(error: true);
    }
  }

  /// 取 [uri] 的正文；网络异常、非 200 或取回途中出错都返回 null。
  static Future<String?> _fetchBody(Uri uri) async {
    ({int status, String body})? res;
    try {
      res = await fetch(uri, _timeout);
    } catch (_) {
      return null;
    }
    if (res == null || res.status != HttpStatus.ok) return null;
    return res.body;
  }

  /// 真实取数：GET [uri]，返回状态码与正文。
  ///
  /// 两个通道共用这一个函数，因此不设通道专属请求头 —— 发往
  /// `raw.githubusercontent.com` 的请求头越干净越不容易被挡。
  static Future<({int status, String body})?> _httpGetText(
      Uri uri, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'DaoBanAssistantPro');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return (status: res.statusCode, body: body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 解析发布清单：`stable` / `prerelease` 两个节点各取版本号、直链与资产名。
  ///
  /// 通道身份由**它在哪个键下面**决定，不看节点里的 `prerelease` 字段。
  /// 节点缺失或版本号为空一律当「该通道暂无」，不算错误 —— 清单是发布脚本
  /// 写的，取不到内容才是错误。
  @visibleForTesting
  static UpdateCheckResult parseManifest(String body) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    return UpdateCheckResult(
      latestStable: _manifestChannel(m['stable'], prerelease: false),
      latestPrerelease: _manifestChannel(m['prerelease'], prerelease: true),
    );
  }

  static UpdateInfo? _manifestChannel(Object? node,
      {required bool prerelease}) {
    if (node is! Map<String, dynamic>) return null;
    final v = (node['version'] as String?) ?? '';
    if (v.isEmpty) return null;
    return UpdateInfo(
      version: v,
      url: (node['url'] as String?) ?? '',
      isPrerelease: prerelease,
      assetName: _manifestAsset(node),
    );
  }

  /// 解析 `/releases` 列表：跳过草稿，按语义版本号自己算出两个「最新」，
  /// 不依赖 latest 标志（避免缓存/滞后）。
  @visibleForTesting
  static UpdateCheckResult parseReleases(String body) {
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
  }

  /// 从清单节点取 APK 资产名（非空字符串才返回）。
  static String? _manifestAsset(Map<String, dynamic> node) {
    final a = node['asset'];
    return a is String && a.isNotEmpty ? a : null;
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
