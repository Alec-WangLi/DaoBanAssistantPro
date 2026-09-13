# 倒班助手Pro · 构建与运行指南

## 产物

| 文件 | 大小 | 说明 |
|---|---|---|
| `app/build/app/outputs/flutter-apk/app-debug.apk` | 153.7 MB | 调试版（全 ABI + 调试符号） |
| `app/build/app/outputs/flutter-apk/app-release.apk` | 21.7 MB | 发布版（arm64-v8a 单 ABI + AOT + tree-shake，**推荐分发用**） |

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

App 内置 19 种常见倒班方式模板，**新建排班时选一个最接近你的倒班方式即可**（如「白夜休休」「白白夜夜休休」「四班三倒」「上 24 休 24」……）。

请进入「我的 → 排班管理 → 新增排班」，先选择你的倒班方式，再按需要微调班次时间、周期表与你的班组起始日；保存后自动重排未来 60 天闹钟。

## 权限（已在 AndroidManifest 配置）

- `POST_NOTIFICATIONS`（通知）
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`（精确闹钟）
- `RECEIVE_BOOT_COMPLETED`（开机重排闹钟）
- `VIBRATE` / `WAKE_LOCK`

## 签名

`release` 走 **独立正式签名**（v0.4.1 起，不再是 debug 证书）：`app/android/app/build.gradle.kts`
在检测到 `app/android/key.properties` 时读取它指向的 keystore，**缺失则回退 debug 证书**，
方便别人克隆后本机调试。

keystore 与口令不入库（见 `.gitignore` 的 `key.properties` / `keystore/`），自己构建正式分发版
时请生成一套并写好 `key.properties`。注意**换签名后旧版必须卸载重装**。

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
