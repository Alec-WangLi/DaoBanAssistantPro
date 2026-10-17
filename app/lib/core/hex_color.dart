// app/lib/core/hex_color.dart
//
// 十六进制色值的解析与格式化 —— 自我取色那一层里那个输入框全靠它。
//
// ## 为什么只收 6 位 / 3 位、不收 alpha
//
// 这不是省事，是两条硬约束逼出来的（规格 §1）：
//
//   1. 桌面小组件的 `WidgetChip.tintedChip` 里 `Paint.setAlpha` 会**覆盖**颜色自带的
//      alpha 字节 —— 一个带透明度的自定义色，在桌面上会渲成一道实心描边环，
//      而不是更淡的一层。
//   2. `widget_snapshot.dart` 用 `color: 0` 当「这天没班」的哨兵。
//
// 所以这里解析出来的颜色**一律补成不透明的 `0xFF……`**；八位（带 alpha）判非法。
//
// ## 非法输入一律返回 null
//
// 不抛异常、不进位、不「猜」一个近似的颜色 —— 调用点据此**什么都不改**（保留上一次
// 的有效色），这条在 `shift_color_picker_test.dart` 里有用例钉着。
library;

/// `#RRGGBB` / `RRGGBB` / `#RGB` / `RGB`（大小写都收、前后空白容忍）→ 不透明的 ARGB。
///
/// **`0x` / `0X` 前缀也收**（可以跟在 `#` 后面）：设计稿与代码里到处写着
/// `0xFF4C8DFF` 这种，用户从别处复制过来会带着它 —— 不收的话那个输入框会「看着
/// 像是对的、一敲确定什么也没变」（非法输入按约定什么都不改，见文件头）。
/// `0x` 后面什么都不剩仍判非法（**不是** 0：0 是桌面小组件「这天没班」的哨兵）。
///
/// 非法返回 `null`。
int? parseHexColor(String input) {
  var s = input.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length > 2 && (s.startsWith('0x') || s.startsWith('0X'))) {
    s = s.substring(2);
  }

  if (s.length == 3) {
    // 三位缩写：每一位翻倍（#ABC → #AABBCC）。
    s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
  } else if (s.length != 6) {
    return null;
  }

  // **先逐字符验是不是十六进制数字，再交给 `int.parse`。**
  // 直接 `int.tryParse(s, radix: 16)` 会吃下 `+4C8DF` / `-4C8DF` 这种带正负号的
  // 六字符串 —— 长度检查拦不住它们，结果是一个完全不相干的颜色。
  if (!_isHexDigits(s)) return null;

  final v = int.parse(s, radix: 16);
  return 0xFF000000 | v;
}

/// 不透明 ARGB → `#RRGGBB`（大写）。**alpha 不进这一串**。
String formatHexColor(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

bool _isHexDigits(String s) {
  for (final r in s.codeUnits) {
    final digit = r >= 0x30 && r <= 0x39; // 0-9
    final upper = r >= 0x41 && r <= 0x46; // A-F
    final lower = r >= 0x61 && r <= 0x66; // a-f
    if (!digit && !upper && !lower) return false;
  }
  return s.isNotEmpty;
}
