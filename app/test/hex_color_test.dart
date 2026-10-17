// app/test/hex_color_test.dart
//
// 十六进制色值的解析与格式化。自我取色那一层的输入框全靠它 ——
// 用户会粘进来各种写法，而**非法输入绝不许改到任何状态**。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/hex_color.dart';

void main() {
  test('六位：带不带 #、大写小写都收', () {
    expect(parseHexColor('#4C8DFF'), 0xFF4C8DFF);
    expect(parseHexColor('4C8DFF'), 0xFF4C8DFF);
    expect(parseHexColor('  4c8dff  '), 0xFF4C8DFF);
    expect(parseHexColor('#000000'), 0xFF000000,
        reason: '全黑是合法的，且**不是** 0（0 是桌面小组件里「这天没班」的哨兵）');
    expect(parseHexColor('#FFFFFF'), 0xFFFFFFFF);
  });

  test('三位缩写：每一位翻倍', () {
    expect(parseHexColor('#ABC'), 0xFFAABBCC);
    expect(parseHexColor('f0a'), 0xFFFF00AA);
  });

  // 2026-10-15：`0x` 前缀也收。设计稿 / 代码里到处都写 `0xFF4C8DFF` 这种，
  // 用户从别处复制过来会带着它；只收 `#` 的话那个输入框会「看着像对的、
  // 一敲确定什么也没变」（非法输入按约定什么都不改）。
  test('0x / 0X 前缀也收（大小写都收，可以跟在 # 后面）', () {
    expect(parseHexColor('0x4C8DFF'), 0xFF4C8DFF);
    expect(parseHexColor('0X4C8DFF'), 0xFF4C8DFF);
    expect(parseHexColor('  0x4c8dff  '), 0xFF4C8DFF);
    expect(parseHexColor('#0x4C8DFF'), 0xFF4C8DFF);
    expect(parseHexColor('0xABC'), 0xFFAABBCC, reason: '三位缩写同样成立');
    // `0x` 后面什么都不剩 = 空串 = 非法（不是 0）。
    expect(parseHexColor('0x'), isNull);
    expect(parseHexColor('#0x'), isNull);
  });

  test('非法输入一律 null，不抛异常', () {
    for (final bad in <String>[
      '', '   ', '#', '#12', '#12345', '#1234567',
      '#GGGGGG', 'ff00zz', '#12 34 56', '红色', '#4C8DF',
      // 长度正好是 6、但带正负号 —— 这两条钉的是「先逐字符验、再交给 int.parse」：
      // `int.tryParse(s, radix: 16)` 会吃下它们，长度检查拦不住。
      '+4C8DF', '-4C8DF',
    ]) {
      expect(parseHexColor(bad), isNull, reason: '「$bad」应当被判非法');
    }
  });

  test('带 alpha 的八位不收（这一版自定义色一律不透明）', () {
    // 两条理由都在规格 §1：桌面小组件的 `WidgetChip.tintedChip` 里
    // `Paint.setAlpha` 会**覆盖**颜色自带的 alpha 字节；而 `widget_snapshot.dart`
    // 用 `color: 0` 当「这天没班」的哨兵。
    expect(parseHexColor('#804C8DFF'), isNull);
    expect(parseHexColor('804C8DFF'), isNull);
  });

  test('格式化：丢掉 alpha、补足六位、大写', () {
    expect(formatHexColor(0xFF4C8DFF), '#4C8DFF');
    expect(formatHexColor(0x004C8DFF), '#4C8DFF', reason: 'alpha 不进这一串');
    expect(formatHexColor(0xFF000102), '#000102');
  });

  test('格式化之后再解析回来是同一个不透明色', () {
    for (final c in <int>[0xFF4C8DFF, 0xFF000000, 0xFFFFFFFF, 0xFF7A5CFF]) {
      expect(parseHexColor(formatHexColor(c)), c);
    }
  });
}
