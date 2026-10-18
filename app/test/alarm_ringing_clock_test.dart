// app/test/alarm_ringing_clock_test.dart
//
// 响铃界面正中那台「时钟」的时刻格式。
//
// 用户 2026-10-18 真机反馈：「新建了一个 20:10 的闹钟，到点确实响了，但界面显示
// 的是 8:10」。根因是那里用的是 `TimeOfDay.hourOfPeriod`（12 小时制的 0..11）
// 却不带 AM/PM —— 20:10 被写成 08:10。全 app 其余钟点（闹钟列表、编辑页、信息卡）
// 都是 24 小时制，这里必须一致。
//
// 边界逐条钉住：午夜不能塌成 00（12 小时制的 0）、正午不能变成 00。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/features/alarm/alarm_ringing_screen.dart';

void main() {
  test('晚上 20:10 显示 20:10，不是 12 小时制的 08:10', () {
    expect(ringClockText(const TimeOfDay(hour: 20, minute: 10)), '20:10');
  });

  test('午夜 / 正午 / 深夜边界都不塌', () {
    expect(ringClockText(const TimeOfDay(hour: 0, minute: 5)), '00:05',
        reason: '12 小时制里午夜的小时是 0，但钟面上要写 00');
    expect(ringClockText(const TimeOfDay(hour: 12, minute: 0)), '12:00');
    expect(ringClockText(const TimeOfDay(hour: 23, minute: 59)), '23:59');
  });

  test('分钟补两位', () {
    expect(ringClockText(const TimeOfDay(hour: 7, minute: 0)), '07:00');
  });
}
