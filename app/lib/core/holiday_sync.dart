// app/lib/core/holiday_sync.dart
//
// 法定节假日数据的「自动更新」：拉远程 `holidays.json` → 校验 → 缓存 → 装进
// `lunar_info.dart` 的生效表。
//
// 三条硬约束（每一条都对应一个真实的失败模式）：
//   1. **不拖启动**：启动时只读本地缓存（同步、零网络），联网刷新在后台跑。
//      离线 / 被墙 / 服务器挂了，界面一切照旧走内置表 —— 本 App 是离线优先的。
//   2. **坏数据不许进**：解析失败、日期越界、区间重叠 → 整份丢弃，保留旧的
//      （校验在 `HolidayTable.parse`，这里只管「不覆盖好数据」）。
//   3. **换了数据要让界面知道**：`LunarInfo` 带缓存，装新表时会清；界面侧听
//      [holidayDataRevision] 重建（日历 + 桌面小组件快照）。
//
// 通道顺序与更新检查一致：官网（Cloudflare Pages）→ 仓库 raw。两个域名都留着，
// 是因为国内只有其中一个可能被挡。
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/holiday_table.dart';
import '../domain/lunar_info.dart';
import 'clock.dart';
import 'net.dart';
import 'update_checker.dart';

/// 节假日表换了之后 +1。日历与桌面小组件听它重建。
///
/// **用 ValueNotifier 而不是通知整个 App 重建**：换数据一年只有一两次，
/// 但一旦发生，读 `lunarOf()` 的每一处都得重新算一遍。挂在页面级监听上
/// （`calendar_screen.dart` / `home_shell.dart`）比在根部重建整棵树便宜，
/// 也不会把正在编辑的表单掀掉。
final ValueNotifier<int> holidayDataRevision = ValueNotifier<int>(0);

/// 一次刷新的结果（界面与日志据此说人话）。
enum HolidayRefreshResult {
  /// 拿到了新数据并已装上。
  updated,

  /// 通道通了、数据没变（或远程数据比本地旧）。
  unchanged,

  /// 三条通道都没拿到，或者拿到的数据不能信。
  failed,
}

/// 节假日数据的同步与缓存。
class HolidaySync {
  HolidaySync._();

  static const _cacheKey = 'holidayTable.v1';
  static const _checkedDayKey = 'holidayTableCheckedDay';

  /// 5 秒：比更新检查的 8 秒短 —— 它只是后台锦上添花，不该在弱网下久占。
  static const timeout = Duration(seconds: 5);

  static final siteUri = Uri.parse('${UpdateChecker.siteBase}/holidays.json');
  static final repoUri = UpdateChecker.repoRaw('holidays.json');

  /// 取数的接缝：测试换成假的就能完全脱离网络。
  @visibleForTesting
  static Future<({int status, String body})?> Function(
      Uri uri, Duration timeout) fetch = httpGetText;

  /// 启动时调：把上次缓存下来的远程数据装上去（**同步、不联网**）。
  ///
  /// 缓存坏了就当没有 —— 下次刷新会覆盖它，不必在这里报错。
  static void installCached(SharedPreferences sp) {
    final body = sp.getString(_cacheKey);
    if (body == null) return;
    try {
      installHolidayTable(
          builtinHolidayTable.mergedWith(HolidayTable.parse(body)));
    } catch (e) {
      debugPrint('HolidaySync: 本地缓存的节假日数据不可用：$e');
    }
  }

  /// 启动后调：同一天最多刷一次（与更新检查同一套「一天一次」的口径）。
  static Future<HolidayRefreshResult> refreshIfStale(
      SharedPreferences sp) async {
    final now = appNow();
    final today = now.year * 10000 + now.month * 100 + now.day;
    if (sp.getInt(_checkedDayKey) == today) return HolidayRefreshResult.unchanged;
    // 先落标记再请求：网络差的时候一天重试几十次没有意义。
    await sp.setInt(_checkedDayKey, today);
    return refresh(sp);
  }

  /// 立即刷新（手动入口也走这里）。
  static Future<HolidayRefreshResult> refresh(SharedPreferences sp) async {
    final fetched = await _fetchFirst();
    if (fetched == null) return HolidayRefreshResult.failed;
    final body = fetched.body;
    final remote = fetched.table;

    if (body == sp.getString(_cacheKey)) return HolidayRefreshResult.unchanged;

    await sp.setString(_cacheKey, body);
    installHolidayTable(builtinHolidayTable.mergedWith(remote));
    holidayDataRevision.value++;
    return HolidayRefreshResult.updated;
  }

  /// 官网 → 仓库 raw，**取第一份「能解析」的**。
  ///
  /// ⚠️ 判据必须是「解析得通」，不能只看 200：Cloudflare Pages 对不存在的路径
  /// 会回 `200 + index.html`（2026-11-15 真机实测踩到 —— 站点还没重新部署时，
  /// 官网通道回来的是一整页 HTML）。只看状态码的话，第一条通道就把后面那条
  /// 兜底通道挡死了，而且报出来的错是「数据不合法」，指向错误的方向。
  static Future<({String body, HolidayTable table})?> _fetchFirst() async {
    for (final uri in <Uri>[siteUri, repoUri]) {
      ({int status, String body})? res;
      try {
        // **两个超时都要有**：`httpGetText` 里那个 `connectionTimeout` 只管
        // TCP 建连，**管不住 DNS 解析**。2026-11-15 真机实测：国内网络上
        // `raw.githubusercontent.com` 的解析能卡住一分钟以上，界面上就是
        // 「正在更新…」一直转。外面这层 `timeout` 才是真正的闸门。
        res = await fetch(uri, timeout).timeout(timeout);
      } catch (_) {
        res = null;
      }
      if (res == null || res.status != 200 || res.body.trim().isEmpty) continue;
      try {
        return (body: res.body, table: HolidayTable.parse(res.body));
      } catch (e) {
        debugPrint('HolidaySync: $uri 的内容不可用，换下一条通道：$e');
      }
    }
    return null;
  }
}
