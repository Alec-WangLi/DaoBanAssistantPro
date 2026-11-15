// app/test/holiday_sync_test.dart
//
// 自动更新的**行为**（不是「有这段代码」）：
//   · 官网不通就走仓库 raw（两条通道，只挡一个也兜得住）；
//   · 拿到了就装表 + 写缓存 + bump 版本号；
//   · 第二次拿到同一份内容**不重复装**（否则每次冷启动都白重建一遍界面）；
//   · 线上数据坏了 → 保留旧表、什么都不装（宁可旧，也不能错）；
//   · 同一天只查一次（`refreshIfStale`）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/holiday_sync.dart';
import 'package:shiftassistantpro/core/net.dart';
import 'package:shiftassistantpro/domain/holiday_table.dart';
import 'package:shiftassistantpro/domain/lunar_info.dart';

String _body({String end = '2027-01-03'}) => jsonEncode({
      'schema': 1,
      'years': [
        {
          'year': 2027,
          'spans': [
            {'name': '元旦节', 'start': '2027-01-01', 'end': end},
          ],
          'makeup': <String>[],
        }
      ],
    });

void main() {
  late int fetchCount;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    fetchCount = 0;
    // 每个用例自己决定哪条通道通，默认只有仓库那条通。
    HolidaySync.fetch = (uri, timeout) async {
      fetchCount++;
      if (uri == HolidaySync.siteUri) return null;
      return (status: 200, body: _body());
    };
  });

  tearDown(() {
    HolidaySync.fetch = httpGetText;
    installHolidayTable(builtinHolidayTable);
  });

  test('官网不通 → 走仓库通道；装上 2027 并写缓存', () async {
    final sp = await SharedPreferences.getInstance();
    final before = holidayDataRevision.value;

    final r = await HolidaySync.refresh(sp);

    expect(r, HolidayRefreshResult.updated);
    expect(fetchCount, 2, reason: '第一条通道失败后必须还有一条');
    expect(holidayNameOf(DateTime(2027, 1, 1)), '元旦节');
    expect(sp.getString('holidayTable.v1'), isNotNull,
        reason: '不写缓存的话，下次冷启动又要等一次网络');
    expect(holidayDataRevision.value, before + 1,
        reason: '界面靠它重建 —— 不 bump 就等于没更新');
  });

  test('官网回 200 但内容不是 JSON（Pages 的 index.html）→ 继续试仓库通道', () async {
    // 2026-11-15 真机实测：站点还没部署 `holidays.json` 时，Cloudflare Pages 对
    // 这个路径回的是 `200 + index.html`。只看状态码会把后面那条兜底通道挡死。
    HolidaySync.fetch = (uri, timeout) async {
      fetchCount++;
      if (uri == HolidaySync.siteUri) {
        return (status: 200, body: '<!doctype html><html><body>404</body></html>');
      }
      return (status: 200, body: _body());
    };
    final sp = await SharedPreferences.getInstance();

    final r = await HolidaySync.refresh(sp);

    expect(r, HolidayRefreshResult.updated);
    expect(fetchCount, 2, reason: '第一条通道内容不可用时要接着试下一条');
    expect(holidayNameOf(DateTime(2027, 1, 1)), '元旦节');
  });

  test('同一份内容再刷一次：不重复装、不重复 bump', () async {
    final sp = await SharedPreferences.getInstance();
    await HolidaySync.refresh(sp);
    final rev = holidayDataRevision.value;
    fetchCount = 0;

    final r = await HolidaySync.refresh(sp);

    expect(r, HolidayRefreshResult.unchanged);
    expect(fetchCount, greaterThan(0));
    expect(holidayDataRevision.value, rev,
        reason: '内容没变还 bump，等于每次冷启动重建一次整页');
  });

  test('线上数据坏掉 → 保留旧表（不装、不写缓存）', () async {
    final sp = await SharedPreferences.getInstance();
    HolidaySync.fetch = (uri, timeout) async => (status: 200, body: '{oops');

    final r = await HolidaySync.refresh(sp);

    expect(r, HolidayRefreshResult.failed);
    expect(sp.getString('holidayTable.v1'), isNull);
    expect(holidayNameOf(DateTime(2027, 1, 1)), isNull,
        reason: '坏数据不许进 —— 这张表直接决定日历哪天标红');
  });

  test('两条通道都不通 → failed，内置表照常工作', () async {
    final sp = await SharedPreferences.getInstance();
    HolidaySync.fetch = (uri, timeout) async => null;

    final r = await HolidaySync.refresh(sp);

    expect(r, HolidayRefreshResult.failed);
    expect(holidayNameOf(DateTime(2026, 10, 1)), '国庆节');
  });

  test('refreshIfStale：同一天只查一次', () async {
    final sp = await SharedPreferences.getInstance();
    await HolidaySync.refreshIfStale(sp);
    fetchCount = 0;

    final r = await HolidaySync.refreshIfStale(sp);

    expect(r, HolidayRefreshResult.unchanged);
    expect(fetchCount, 0, reason: '一天一次的意义就在这儿：不要每次冷启动都请求');
  });

  test('启动时读缓存：不联网也能拿到上次的数据', () async {
    final sp = await SharedPreferences.getInstance();
    await HolidaySync.refresh(sp);
    // 模拟下次冷启动：先把生效表退回来，再走 installCached。
    installHolidayTable(builtinHolidayTable);
    expect(holidayNameOf(DateTime(2027, 1, 1)), isNull);

    HolidaySync.installCached(sp);

    expect(holidayNameOf(DateTime(2027, 1, 1)), '元旦节');
    expect(fetchCount, 2, reason: 'installCached 不许联网');
  });

  test('缓存坏掉不会拖垮启动（当没有，继续用内置表）', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('holidayTable.v1', 'not json');

    HolidaySync.installCached(sp);

    expect(holidayNameOf(DateTime(2026, 10, 1)), '国庆节');
  });
}
