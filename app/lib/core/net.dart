// app/lib/core/net.dart
//
// 最小 HTTP 取文本工具。**只有一处实现**：更新检查（`update_checker.dart`）与
// 法定节假日数据（`holiday_sync.dart`）都走它 —— 两条通道的失败口径
// （网络异常 / 非 200 / 超时一律当「没拿到」）必须一致，抄两份迟早走偏。
//
// 为什么不用 `package:http`：本项目只需要 GET 一段文本，`dart:io` 的 HttpClient
// 已经够用，少一个依赖就少一处升级风险（Web 端不发布，不需要那层的可移植性）。
import 'dart:convert';
import 'dart:io';

/// GET 一个 URL，返回 (状态码, 正文)。
///
/// 网络异常、DNS 失败、超时、正文解码失败一律返回 **null**（调用方按「这条通道
/// 不通」处理，去试下一条）；HTTP 状态码原样返回，由调用方判断。
Future<({int status, String body})?> httpGetText(
  Uri uri,
  Duration timeout,
) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(uri);
    // 发往 `raw.githubusercontent.com` 的请求头越干净越不容易被挡。
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
