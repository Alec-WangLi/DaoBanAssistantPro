// 桌面小组件布局的 RemoteViews 白名单守门测试。
//
// 为什么需要它：`RemoteViews` 的视图白名单是靠 `@RemoteView` 注解做 LayoutInflater
// 的 filter 的，用了白名单外的类（最典型的是想用 `<View>` 画一条 1dp 分隔线），宿主
// 会在 apply() 阶段抛 `InflateException: Class not allowed to be inflated ...`，
// **整张卡片渲染不出来** —— 不是只丢那一个视图。
//
// 而这类缺陷在开发期几乎不可能被发现：XML 合法、编译通过、资源 id 全都解析得到、
// Dart 侧测试全绿、logcat 里链路也通。只有真机上真的渲染那一刻才炸。Task 3 实做时
// 正是这样踩中的（分隔线用了 `<View>`），差点带着它跑到发布。
//
// 所以把它变成一条会失败的测试。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `RemoteViews` 允许 inflate 的类。来源是 Google 文档「Create a simple widget」
/// 与 `android.widget.RemoteViews` 的 `@RemoteView` 注解清单。
///
/// ⚠️ 这份清单**只有文档在维持**，没有编译期保护。加新布局时若用到没列在这里的类，
/// 先在本仓 `toolchain/android-sdk/platforms/android-36/android.jar` 上跑
/// `javap -v -classpath android.jar <全限定类名> | grep -c RemoteView` 确认它确实带
/// 注解，再补进这里。
const _allowed = {
  // 布局
  'FrameLayout', 'LinearLayout', 'RelativeLayout', 'GridLayout',
  'ListView', 'GridView', 'StackView', 'AdapterViewFlipper', 'ViewFlipper',
  // 控件
  'TextView', 'ImageView', 'Button', 'ImageButton', 'ProgressBar',
  'Chronometer', 'TextClock', 'AnalogClock',
  // API 31+
  'CheckBox', 'RadioButton', 'RadioGroup', 'Switch',
};

/// XML 里长得像视图元素、但不是视图的东西 —— 免得将来用了它们被误伤。
/// `layout_*` 这类属性不会命中（正则要求 `<` 紧跟字母）。
const _nonView = {'include', 'merge', 'requestFocus'};

void main() {
  test('小组件布局里不得出现 RemoteViews 白名单之外的视图类', () {
    final dir = Directory('android/app/src/main/res/layout');
    expect(dir.existsSync(), true,
        reason: '找不到 ${dir.path} —— 测试的工作目录应当是 app/');

    final offenders = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.xml')) continue;
      if (!f.path.contains('widget')) continue; // 只管小组件的布局

      // **先剥 XML 注释再扫，但必须「等长替换」**：所有规则都靠「命中偏移 → 行号」
      // 定位，把注释**删掉**会让后面所有偏移一起前移、报出来的行号偏小（而且每个
      // 文件偏的量还不同 —— 正比于那个文件的多行头注释长度，人脑修不了）。换成等长
      // 空格则偏移与行号纹丝不动 —— 这正是 `test/support/source_scan.dart` 给 Dart
      // 源码那套做法讲的道理，XML 这边照抄。
      final raw = f.readAsStringSync();
      final src = raw.replaceAllMapped(
        RegExp(r'<!--.*?-->', dotAll: true),
        (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
      );

      for (final m in RegExp(r'<([A-Za-z][A-Za-z0-9_.]*)').allMatches(src)) {
        final name = m.group(1)!;
        final simple = name.split('.').last; // 带包名前缀的取最后一段
        if (_allowed.contains(simple)) continue;
        if (_nonView.contains(simple)) continue;
        final line = src.substring(0, m.start).split('\n').length;
        offenders.add('${f.path}:$line  <$name>');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些类不在 RemoteViews 白名单里，宿主 inflate 时会抛 '
          'InflateException、导致整张卡片渲染不出来：\n${offenders.join('\n')}\n'
          '想画分隔线/占位，用 ImageView 或 TextView。',
    );
  });
}
