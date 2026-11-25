// app/test/shift_night_flag_test.dart
//
// 「夜班」是班次上的一个**显式标记**，不是从名字或「跨不跨午夜」猜出来的：
// 24 小时值班也跨午夜、早班也可能跨午夜，而用户口中的夜班是工作安排的一部分。
// 这里钉住三条链：内置模板按角色自动标、模板 JSON 往返、copyWith / == 不丢字段。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/schedule_template.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';

void main() {
  test('内置模板的夜班角色自动标 isNight，休息班不会标', () {
    final t = shiftTemplates.firstWhere((e) => e.id == 'day_night_rest_rest');
    expect(t.classes.any((c) => c.isNight), isTrue);
    expect(t.classes.where((c) => c.isNight).every((c) => !c.isRest), isTrue);
  });

  test('模板 JSON 往返保留 isNight；旧数据缺字段按 false', () {
    final raw = encodeTemplateClasses(const [
      ShiftClass(
          name: '夜', startMinute: 1230, endMinute: 510, isNight: true),
    ]);
    expect(decodeTemplateClasses(raw).single.isNight, isTrue);

    const legacy =
        '[{"name":"夜","startMinute":1230,"endMinute":510,"isRest":false}]';
    expect(decodeTemplateClasses(legacy).single.isNight, isFalse);
  });

  test('copyWith 与 == 带上 isNight', () {
    const a = ShiftClass(name: 'x');
    expect(a.copyWith(isNight: true).isNight, isTrue);
    expect(a == a.copyWith(isNight: true), isFalse);
  });
}
