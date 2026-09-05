# 倒班助手Pro · 构建与运行指南

## 产物

| 文件 | 大小 | 说明 |
|---|---|---|
| `app/build/app/outputs/flutter-apk/app-debug.apk` | 153.7 MB | 调试版（全 ABI + 调试符号） |
| `app/build/app/outputs/flutter-apk/app-release.apk` | 57.6 MB | 发布版（AOT + tree-shake，**推荐分发用**） |

## 技术栈

- Flutter 3.47.2 · Dart 3.13.2
- 包名 / applicationId：`com.daoban.shiftassistantpro`
- minSdk 26（Android 8.0）；31+ 真模糊、26–30 假玻璃降级
- 数据：Drift（SQLite，纯本地离线，无账号/后端）

## 在你自己的电脑上构建（Windows）

> 说明：本仓库工作区内的 `toolchain/` 已自举完整工具链（Flutter + JDK17 + Android SDK），但那只适用于本会话的沙箱环境。你日常开发建议自己装一套。

前置：
1. Flutter SDK（stable）加入 PATH
2. JDK 17（设置 `JAVA_HOME`）
3. Android SDK（`ANDROID_HOME`；含 platform-tools、platforms;android-35、build-tools;35.0.0）
4. **Windows 开启「开发者模式」**（设置 → 隐私和安全性 → 开发者选项）——否则带插件的构建会因符号链接失败

步骤：
```powershell
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 Drift 代码（首次/改表后）
flutter build apk --release                                  # 或 --debug
```

## 首次运行注意

App 默认内置「四班两倒」配置（白班 → 上夜班 → 下夜班 → 大休，白班 8:30–20:30、上夜班 20:30–次日 8:30、闹钟白班 7:00 / 上夜班 19:30），**锚点日是占位值**。
请进入「日历 → 右上角 ⚙ 编辑排班」，把锚点日设成你实际「白班」的那一天，保存后自动重排未来 90 天闹钟。

## 权限（已在 AndroidManifest 配置）

- `POST_NOTIFICATIONS`（通知）
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`（精确闹钟）
- `RECEIVE_BOOT_COMPLETED`（开机重排闹钟）
- `VIBRATE` / `WAKE_LOCK`

## 签名

`release` 当前复用 **debug 证书**签名（可安装自用；如需正式分发请换成自己的 keystore，改 `android/app/build.gradle.kts` 的 `signingConfig`）。

## 目录结构

```
app/lib/
  main.dart               入口（初始化闹钟服务）
  app.dart                根 Widget（跟随系统深浅主题）
  core/theme/             深空蓝紫配色 + 深浅两套主题
  core/glass/             液态玻璃面板（BackdropFilter 模糊 + 高光描边 + 假玻璃降级）
  domain/shift_rotation.dart  轮换引擎（纯 Dart，可单测）
  data/                   Drift 表 + 仓库 + Riverpod providers + 种子数据
  features/calendar/      月历 + 排班方案编辑器
  features/alarm/         联动班次闹钟（精确通知 + 提前N + 贪睡）
  features/schedule/      日程（增删改 + 完成 + 提前提醒）
  features/home/          底部导航壳
```
