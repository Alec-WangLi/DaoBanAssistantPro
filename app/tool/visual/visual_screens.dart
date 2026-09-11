// app/tool/visual/visual_screens.dart
//
// 「要渲染/审计哪些界面、各出哪些变体」只有一份定义，出图与对比度审计共用。
// 两边各写一份清单的话，迟早会有一边漏掉某屏，而漏掉是不会报错的。

import 'package:flutter/material.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/alarm/alarm_screen.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_editor_screen.dart';
import 'package:shiftassistantpro/features/calendar/schedule_management_screen.dart';
import 'package:shiftassistantpro/features/calendar/shift_template_picker_screen.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:shiftassistantpro/features/profile/profile_screen.dart';
import 'package:shiftassistantpro/features/schedule/schedule_screen.dart';

import 'visual_harness.dart';

/// 一屏的渲染参数。`build` 是异步的，因为编辑器要先把 id 从库里查出来。
typedef VisualScreen = ({
  String slug,
  String title,
  Future<Widget> Function(AppDatabase db) build,
  bool needsOnboardingPrefs,
});

final List<VisualScreen> visualScreens = [
  (
    slug: '00_home_shell',
    title: '主壳',
    build: (db) async => const HomeShell(),
    // 首启弹「使用帮助」、版本变了弹「更新简介」——不置这两个标记，
    // 弹窗会把整个界面盖住，拍到的就不是壳了。
    needsOnboardingPrefs: true,
  ),
  (
    slug: '01_calendar',
    title: '日历',
    build: (db) async => const CalendarScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '02_editor',
    title: '排班编辑器',
    build: (db) async =>
        ScheduleEditorScreen(scheduleId: await currentScheduleId(db)),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '03_management',
    title: '排班管理',
    build: (db) async => const ScheduleManagementScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '04_template_picker',
    title: '倒班方式选择',
    build: (db) async => const ShiftTemplatePickerScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '05_todos',
    title: '待办事项',
    build: (db) async => const ScheduleScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '06_alarm',
    title: '闹钟',
    build: (db) async => const AlarmScreen(),
    needsOnboardingPrefs: false,
  ),
  (
    slug: '07_profile',
    title: '我的',
    build: (db) async => const ProfileScreen(),
    needsOnboardingPrefs: false,
  ),
];

/// 每个界面要出的变体。
///
/// 英文那张不是凑数：文案漏翻、英文顶到边、日期格式在英文下串成
/// 「2026 9」这类问题，只有在英文界面上才看得见。
///
/// 横屏与小窗两张同样不是凑数：它们的尺寸正是用户反馈「几乎无法使用」的
/// 那两种形态 —— 工装过去只拍 420×900，所以那些缺陷一张图都拍不到。
final List<
    ({
      String suffix,
      String label,
      Brightness brightness,
      String language,
      Size size,
    })> visualVariants = [
  (
    suffix: 'light',
    label: '浅色',
    brightness: Brightness.light,
    language: 'zh',
    size: kVisualSize,
  ),
  (
    suffix: 'dark',
    label: '深色',
    brightness: Brightness.dark,
    language: 'zh',
    size: kVisualSize,
  ),
  (
    suffix: 'en',
    label: '英文',
    brightness: Brightness.light,
    language: 'en',
    size: kVisualSize,
  ),
  (
    suffix: 'landscape',
    label: '横屏 900×420',
    brightness: Brightness.light,
    language: 'zh',
    size: const Size(900, 420),
  ),
  (
    suffix: 'small',
    label: '小窗 360×360',
    brightness: Brightness.light,
    language: 'zh',
    size: const Size(360, 360),
  ),
];
