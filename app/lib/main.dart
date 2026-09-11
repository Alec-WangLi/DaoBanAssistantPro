import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/glass/glass.dart';
import 'core/l10n.dart';
import 'features/alarm/alarm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 关键：初始化 intl 中文 locale，否则 DateFormat(..., 'zh') 运行期抛异常导致整屏空白
  await initializeDateFormatting('zh');
  // 语言必须在**任何落库之前**定下来：首启播种（seedIfEmpty → defaultSchedule）
  // 会把方案名与班次名写进数据库，而这些文案是按当前语言生成的。若此时
  // L10n.locale 还是静态初值 'zh'，英文用户的第一套排班就是中文的。
  //
  // AppSettingsNotifier 稍后还会再读一次同一个键（它负责界面重建），
  // 两处取值一致，幂等。
  try {
    final sp = await SharedPreferences.getInstance();
    L10n.locale = sp.getString('language') ?? 'zh';
  } catch (_) {
    // 读取失败就用默认中文，与加这段之前的行为一致
  }
  await AlarmService.init();
  // 低端机（物理内存 < 4GB）关闭全局玻璃模糊，避免 BackdropFilter 拖垮 GPU。
  try {
    final ram = await AlarmService.getTotalRamBytes();
    if (ram > 0 && ram < 4 * 1024 * 1024 * 1024) {
      lowEndDevice = true;
    }
  } catch (_) {}
  recomputeGlassBlur();

  // 捕获 Flutter 框架错误 + 未处理异步错误，写入日志文件（「我的 → 查看日志」可看）
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AlarmService.appendLog(
        'FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack ?? ''}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AlarmService.appendLog('UNCAUGHT ERROR: $error\n$stack');
    return true;
  };

  runApp(const ProviderScope(child: ShiftAssistantApp()));
}
