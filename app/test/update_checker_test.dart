import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/update_checker.dart';

/// 发布清单（仓库根目录 latest.json）的典型内容。
const _manifestJson = '''
{
  "stable": {
    "version": "0.9.0",
    "url": "https://github.com/x/y/releases/download/v0.9.0/a.apk",
    "prerelease": false,
    "asset": "a.apk"
  },
  "prerelease": {
    "version": "0.9.3",
    "url": "https://github.com/x/y/releases/download/v0.9.3/b.apk",
    "prerelease": true,
    "asset": "b.apk"
  },
  "updatedAt": "2026-09-21T06:18:12Z"
}
''';

/// GitHub `/releases` 列表的典型内容（含一个正式版、一个预发布版）。
const _releasesJson = '''
[
  {
    "tag_name": "v0.9.3",
    "prerelease": true,
    "draft": false,
    "html_url": "https://github.com/x/y/releases/tag/v0.9.3",
    "assets": [{
      "name": "b.apk",
      "browser_download_url": "https://github.com/x/y/releases/download/v0.9.3/b.apk"
    }]
  },
  {
    "tag_name": "v0.9.0",
    "prerelease": false,
    "draft": false,
    "html_url": "https://github.com/x/y/releases/tag/v0.9.0",
    "assets": [{
      "name": "a.apk",
      "browser_download_url": "https://github.com/x/y/releases/download/v0.9.0/a.apk"
    }]
  }
]
''';

void main() {
  // 被换掉的真取数函数，tearDown 里装回去。
  late Future<({int status, String body})?> Function(Uri, Duration) realFetch;
  // 每次取数命中哪个通道，用来断言「清单优先」。
  late List<String> hits;

  setUp(() {
    realFetch = UpdateChecker.fetch;
    hits = [];
  });

  tearDown(() => UpdateChecker.fetch = realFetch);

  /// 装一个假的取数接缝。传 null 表示该通道不通（网络异常）。
  void serve({
    String? manifest,
    String? releases,
    int manifestStatus = 200,
  }) {
    UpdateChecker.fetch = (uri, timeout) async {
      final isManifest = uri.host == 'raw.githubusercontent.com';
      hits.add(isManifest ? 'manifest' : 'api');
      if (isManifest) {
        if (manifest == null) return null;
        return (status: manifestStatus, body: manifest);
      }
      if (releases == null) return null;
      return (status: 200, body: releases);
    };
  }

  group('parseManifest', () {
    test('读出两个通道的版本、直链与资产名', () {
      final r = UpdateChecker.parseManifest(_manifestJson);
      expect(r.error, isFalse);
      expect(r.latestStable?.version, '0.9.0');
      expect(r.latestStable?.url, contains('v0.9.0/a.apk'));
      expect(r.latestStable?.assetName, 'a.apk');
      expect(r.latestStable?.isPrerelease, isFalse);
      expect(r.latestPrerelease?.version, '0.9.3');
      expect(r.latestPrerelease?.isPrerelease, isTrue);
    });

    test('节点缺失只当「该通道暂无」，不算错误', () {
      final r = UpdateChecker.parseManifest('{"stable": null}');
      expect(r.error, isFalse);
      expect(r.latestStable, isNull);
      expect(r.latestPrerelease, isNull);
    });

    test('版本号为空同样当暂无', () {
      final r = UpdateChecker.parseManifest('{"stable": {"version": ""}}');
      expect(r.latestStable, isNull);
    });

    test('内容不是 JSON 就抛，由调用方兜住', () {
      expect(() => UpdateChecker.parseManifest('<html>404</html>'),
          throwsA(isA<FormatException>()));
    });
  });

  group('parseReleases', () {
    test('各取最高的正式版与测试版', () {
      final r = UpdateChecker.parseReleases(_releasesJson);
      expect(r.latestStable?.version, '0.9.0');
      expect(r.latestPrerelease?.version, '0.9.3');
    });

    test('版本高低按数值比，不是按字符串比', () {
      final r = UpdateChecker.parseReleases('''
        [{"tag_name":"v0.10.0","prerelease":false,"assets":[]},
         {"tag_name":"v0.9.9","prerelease":false,"assets":[]}]
      ''');
      expect(r.latestStable?.version, '0.10.0');
    });

    test('草稿不参与，哪怕版本号更高', () {
      final r = UpdateChecker.parseReleases('''
        [{"tag_name":"v9.9.9","prerelease":false,"draft":true,"assets":[]},
         {"tag_name":"v0.9.0","prerelease":false,"assets":[]}]
      ''');
      expect(r.latestStable?.version, '0.9.0');
    });

    test('APK 资产优先于 Release 页面链接', () {
      final r = UpdateChecker.parseReleases(_releasesJson);
      expect(r.latestStable?.url, contains('/download/'));
      expect(r.latestStable?.assetName, 'a.apk');
    });

    test('没有 APK 资产时回退到 Release 页面链接', () {
      final r = UpdateChecker.parseReleases('''
        [{"tag_name":"v0.9.0","prerelease":false,
          "html_url":"https://github.com/x/y/releases/tag/v0.9.0","assets":[]}]
      ''');
      expect(r.latestStable?.url, 'https://github.com/x/y/releases/tag/v0.9.0');
      expect(r.latestStable?.assetName, isNull);
    });

    test('空列表两个通道都是空', () {
      final r = UpdateChecker.parseReleases('[]');
      expect(r.latestStable, isNull);
      expect(r.latestPrerelease, isNull);
    });
  });

  group('checkUpdates 通道顺序', () {
    test('清单通就用清单，不再打 API', () async {
      serve(manifest: _manifestJson, releases: _releasesJson);
      final r = await UpdateChecker.checkUpdates();
      expect(r.error, isFalse);
      expect(r.latestStable?.version, '0.9.0');
      expect(hits, ['manifest']);
    });

    test('清单不通才回退到 API', () async {
      serve(manifest: null, releases: _releasesJson);
      final r = await UpdateChecker.checkUpdates();
      expect(r.error, isFalse);
      expect(r.latestStable?.version, '0.9.0');
      expect(hits, ['manifest', 'api']);
    });

    test('清单返回非 200 也算不通', () async {
      serve(
        manifest: _manifestJson,
        releases: _releasesJson,
        manifestStatus: 403,
      );
      await UpdateChecker.checkUpdates();
      expect(hits, ['manifest', 'api']);
    });

    test('清单内容坏掉也回退到 API', () async {
      serve(manifest: '<html>', releases: _releasesJson);
      final r = await UpdateChecker.checkUpdates();
      expect(r.error, isFalse);
      expect(hits, ['manifest', 'api']);
    });

    test('两条都不通就是错误', () async {
      serve(manifest: null, releases: null);
      final r = await UpdateChecker.checkUpdates();
      expect(r.error, isTrue);
      expect(hits, ['manifest', 'api']);
    });

    test('取数抛异常也走回退，不把异常漏出去', () async {
      UpdateChecker.fetch = (uri, timeout) async => throw Exception('boom');
      final r = await UpdateChecker.checkUpdates();
      expect(r.error, isTrue);
    });
  });
}
