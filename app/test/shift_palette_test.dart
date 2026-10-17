// app/test/shift_palette_test.dart
//
// 班次可选颜色的**盘**与它要过的那条线。纯函数，不碰界面。
//
// 这一条是这个仓库里少见的「**先有判据、再挑颜色**」的护栏：规格 §4 把「淡染 +
// 描边」那套配方在三处卡底上逐颗算了一遍，现有八个的下界就是门槛，新加的每一颗
// 都必须不低于它。谁往盘里塞一个漂亮的浅色，这里当场红。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/shift_palette.dart';

void main() {
  test('盘是 16 颗、互不相同、第一颗是白班蓝', () {
    expect(kShiftPalette, hasLength(16));
    expect(kShiftPalette.toSet(), hasLength(16), reason: '不许有重复色');
    expect(kShiftPalette.first, 0xFF4C8DFF,
        reason: '新建班次是循环取色的，顺序一动就换色（Task 5 钉着它）');
  });

  test('原班底那八颗一颗都没动（内置模板烘着其中 7 个）', () {
    const old = <int>[
      0xFF4C8DFF, 0xFF7A5CFF, 0xFF9AA0B4, 0xFF5A5F73,
      0xFF34C759, 0xFFFF9F0A, 0xFFFF375F, 0xFF00C7BE,
    ];
    for (final c in old) {
      expect(kShiftPalette, contains(c));
    }
    expect(kShiftPalette.take(8).toList(), old,
        reason: '前八颗就是原来那八个，顺序也别动');
  });

  test('16 颗 × 四处卡底：描边对卡底全部过线', () {
    for (final c in kShiftPalette) {
      for (final card in kShiftCardSurfaces) {
        final v = shiftChipStrokeContrast(c, card);
        expect(v, greaterThanOrEqualTo(kShiftColorBar),
            reason: '#${c.toRadixString(16)} 压在 '
                '#${card.toRadixString(16)} 上只有 ${v.toStringAsFixed(3)}');
      }
    }
  });

  test('那条线就是现有八个在四处卡底上的下界', () {
    // 定住它的那颗是 #FF9F0A，压在最暗的那处小组件卡上（浅色卡 + 黑壁纸）。
    // **这个数是拿实现算出来的**（每通道取整到 8 位）：规格里先写 1.34906，
    // 那是浮点混合的结果，差在 249.5 取整成 250 那一点点上。
    // **这条不是凑数**：谁改了卡底常量、或动了现有某颗色，这个数就会漂 ——
    // 让它当场红，而不是悄悄把门槛放宽（门槛的意思是「不比现在差」，漂了就没了）。
    expect(shiftChipStrokeContrast(0xFFFF9F0A, kShiftCardWidgetLight),
        closeTo(1.350188, 0.00001));

    var worst = 99.0;
    for (final c in kShiftPalette.take(8)) {
      for (final card in kShiftCardSurfaces) {
        final v = shiftChipStrokeContrast(c, card);
        if (v < worst) worst = v;
      }
    }
    expect(kShiftColorBar, closeTo(worst, 0.0005),
        reason: '门槛必须等于「现有八个的下界」，不能是一个更大的手写数');
  });

  test('合成算式的边界：α=1 就是原色、α=0 就是卡底', () {
    expect(compoundOver(0xFF123456, 0xFFFFFFFF, 1.0), 0xFF123456);
    expect(compoundOver(0xFF123456, 0xFFFFFFFF, 0.0), 0xFFFFFFFF);
    expect(compoundOver(0xFF000000, 0xFFFFFFFF, 0.5), 0xFF808080);
  });
}
