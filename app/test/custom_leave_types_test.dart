// app/test/custom_leave_types_test.dart
//
// 自定义请假类型：脏数据清洗 + 持久化。名字是用户数据，读不懂的一条不该让
// 整个请假弹层打不开。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/state/app_settings.dart';

void main() {
  test('parseCustomLeaveTypes 保序去重、丢掉脏数据', () {
    expect(parseCustomLeaveTypes(null), isEmpty);
    expect(parseCustomLeaveTypes(''), isEmpty);
    expect(parseCustomLeaveTypes('not json'), isEmpty);
    expect(parseCustomLeaveTypes('{"a":1}'), isEmpty);
    expect(
      parseCustomLeaveTypes('["育儿假"," 育儿假 ","","工伤假",3]'),
      ['育儿假', '工伤假'],
    );
  });

  test('setCustomLeaveTypes 写进 prefs，重启后读得回来', () async {
    SharedPreferences.setMockInitialValues({});

    final n = AppSettingsNotifier();
    await n.setCustomLeaveTypes(['育儿假', '  ', '育儿假', '照护假']);
    expect(n.state.customLeaveTypes, ['育儿假', '照护假']);

    final sp = await SharedPreferences.getInstance();
    expect(parseCustomLeaveTypes(sp.getString('customLeaveTypes')),
        ['育儿假', '照护假']);

    final restarted = AppSettingsNotifier();
    await pumpEventQueue();
    expect(restarted.state.customLeaveTypes, ['育儿假', '照护假']);
  });

  test('白名单之外的旧数据不影响默认值', () async {
    SharedPreferences.setMockInitialValues({'customLeaveTypes': 'oops'});
    final n = AppSettingsNotifier();
    await pumpEventQueue();
    expect(n.state.customLeaveTypes, isEmpty);
  });
}
