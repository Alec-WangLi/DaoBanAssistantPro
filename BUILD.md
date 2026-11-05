# 倒班助手Pro · 构建与运行指南

## 产物

| 文件 | 大小 | 说明 |
|---|---|---|
| `app/build/app/outputs/flutter-apk/app-debug.apk` | 85.2 MB | 调试版（全 ABI + 调试符号） |
| `app/build/app/outputs/flutter-apk/app-release.apk` | 22.0 MB | 发布版（arm64-v8a 单 ABI + AOT + tree-shake，**推荐分发用**） |

## 技术栈

- Flutter 3.47.2 · Dart 3.13.2
- 包名 / applicationId：`com.daoban.shiftassistantpro`
- minSdk 26（Android 8.0）；31+ 真模糊、26–30 假玻璃降级
- 数据：Drift（SQLite，纯本地离线，无账号/后端）

## 第一次跑测试（克隆之后 5 分钟）

仓库里**只有源码与文档**。`toolchain/`、`tools/`、`dist/`、`work/` 都不入库（见 `.gitignore`），
所以第一次得自己装 SDK。好消息是**跑测试不需要 Android SDK，也不需要 JDK** —— 只有出 APK 才要。

### 1. 装 Flutter，版本别换

本项目在 **Flutter 3.47.2 stable（Dart 3.13.2）** 上验证与量数。`app/pubspec.yaml` 只写了
`sdk: '>=3.4.0 <4.0.0'`，但视觉工装里那些「某字号档下不截断」的断言是按上面这一版量出来的，
换版本等于换字体度量与布局默认值 —— 引擎不同、断言的语义就变了。

### 2. 拉依赖、跑测试

```bash
cd app
flutter pub get
flutter test          # 1242 条
flutter analyze       # 必须 No issues found
```

参考耗时（Windows，冷编译）：`flutter test` **43 秒**、`flutter analyze` **8 秒**。
所以「跑一遍全套」比刷一次手机还快，改完就跑，别只跑自己动过的那一个文件。

**在本项目的沙箱里别直接敲 `flutter`**：那里 Dart/Flutter 进程建符号链接会被拒
（`ERROR_PRIVILEGE_NOT_HELD 1314`，开发者模式其实是开的）。不设 `PUB_CACHE` 直接跑，
`flutter` 会用默认 pub 缓存重新解析、把 `app/.dart_tool/.flutter-plugins-dependencies`
指过去，下一次运行就判定要重建插件符号链接 —— 而链接建不出来，
`app/windows/flutter/ephemeral/.plugin_symlinks` 会被清空，随后报
`Building with plugins requires symlink support`（2026-11-05 实测）。走包装脚本就不会：

```bash
bash tools/flutter-test.sh        # 全套测试
bash tools/flutter-analyze.sh     # 静态分析
```

`dart run build_runner build` **只在改了 Drift 表之后要跑**（别再带 `--delete-conflicting-outputs`，
build_runner 2.15.1 起这个参数已被移除，传了会被静默忽略）；
生成物 `app/lib/data/app_database.g.dart` 是入库的，CI 会比对它有没有落后于表定义。
⚠️ 受限环境（本项目的沙箱）里它和 `flutter test` 是同一个毛病 —— 建临时目录失败：
```bash
cd app
PUB_CACHE=$PWD/../toolchain/pub-cache TMP=$PWD/../work/tmp TEMP=$PWD/../work/tmp \
  dart run build_runner build
```

### 3. 视觉工装（可选，出图用）

```bash
cd app
flutter test tool/visual/     # 1284 条
```

它把每个界面按屏单渲成 PNG 到 `app/build/visual/`，**只看不出图、不比对基线**；唯一的断言是
「渲染期间没有布局溢出、没有静默截断」。参考耗时 **57 秒**。

**字体是入库资产，不再靠系统找**：`app/test/fonts/` 里放着三份
（`NotoSansSC-Regular.otf` 2.86MB、`materialicons-regular.otf` 1.6MB、`roboto-regular.ttf` 172KB），
工装按仓库相对路径加载；缺任何一份直接 `StateError` 报出缺哪个文件，**不会再静默渲成方块**。
所以 Windows / macOS / Linux / CI 量的是同一把尺子 —— 2026-11-05 CI 上一度有 8 条用例因为这把尺子
不同而红（本地量等线、CI 量 Noto，行盒高度差 2dp）。要临时换字体：

```bash
VISUAL_CJK_FONT=/path/to/your-font.ttf bash tools/flutter-test.sh tool/visual/
```

⚠️ 它们是**许可资产**：Noto 走 SIL OFL 1.1（子集，未声明 Reserved Font Name），Roboto 与
Material Icons 走 Apache 2.0，全文与来源说明在 `app/test/fonts/README.md` 同目录。删之前先想清楚。

**它不进 CI 主流程，只有一条每日巡场。** `.github/workflows/visual.yml` 每天 02:00（北京时间，
cron 写的是 UTC `0 18 * * *`）跑一次，也可以在 Actions 页手动触发：出图 356 张/627MB 整个上传成
artifact（留 7 天），job summary 里写出图张数、体积、耗时和日志末行 —— **结论永远是绿的**
（`continue-on-error: true` 是刻意的）。理由与本地跑法一样直接：图是字体画的，字体换一版、字距
微调几百分之一，图就变而 App 一个像素都没坏；拿它当红灯，假红会把真红一起淹掉，几次之后所有人
学会无视它。它只回答「今天画得出来、画出来几张」，与上一版比像素是下一步的事。

### 4. 出 APK

见下一节。要分发的那一份**只能在主 checkout 里构建**，理由见末尾第 ② 条。

### 5. 七条最贵的坑

| 现象 | 真正的原因 | 怎么办 |
|---|---|---|
| `git clean -xdf` 之后什么都跑不动 | `tools/`、`toolchain/`、`dist/` 是 gitignore 的本机资产，clean 会连它们一起删 | 用 `git clean -xdf -e tools -e toolchain -e dist -e work`，或者干脆别 clean |
| 发出去的包用户一装就报 `Conflicting app signatures` | 在 `git worktree` 里构建：那里没有 `key.properties`，`build.gradle.kts` **静默**回退 debug 证书 | 只在主 checkout 构建；`scripts/release.ps1` 已带签名校验 |
| 编译过了，运行时报「列不存在」 | 改了 Drift 表没重生成 `app_database.g.dart` | 改表后跑 `dart run build_runner build`，CI 也会拦 |
| `flutter test` 一条用例都跑不到，报 `null. The flutter tool cannot access the file or directory.` | 受限环境（本项目的沙箱）里 `%TEMP%` 不可写，而 `flutter test` 开场就要建临时目录 | 只在受限环境需要，且**先 `cd app`**（文档前文的命令都在这层）：`mkdir -p "$PWD/../work/tmp" && export TMP="$PWD/../work/tmp" TEMP="$TMP"`（见 `tools/flutter-test.sh`）。普通电脑别抄 |
| 视觉工装报 `字体资产缺 …`，或 CI 上只有和文字尺寸有关的用例红 | 量文字宽高的用例读的是真实字形；字体换一把尺子，2dp 的行盒差就能让布局溢出 | 三份字体在 `app/test/fonts/` 入库，别删；要换就 `VISUAL_CJK_FONT` 显式指 |
| 沙箱里跑过 `flutter` 之后，构建报 `Building with plugins requires symlink support` | 直接跑 `flutter` 会用默认 pub 缓存、改写 `.flutter-plugins-dependencies`，而本沙箱建不了符号链接，`.plugin_symlinks` 被清空 | 一律走 `bash tools/flutter-test.sh` / `tools/flutter-analyze.sh`（它们设了 `PUB_CACHE` 与 `TMP`） |
| 每天 23:55–23:59 之间跑全套，会有一条谁都没碰过的用例红（2026-11-06 前：`app/test/alarm_screen_test.dart:178`） | 那条用例拿「现在 + 5 分钟」当样本；跨过午夜后 24 小时值班把它锚在当天、那个时刻已经过去，行被 `alarm_screen.dart:99` continue 掉 | 2026-11-06 已把用例钉到固定时钟。**记住这一类**：任何依赖真实「现在几点」的用例都是定时炸弹 —— 新写用例一律 `useFixedNow()`；出包前碰上一次莫名其妙红，先看表 |

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
dart run build_runner build   # 生成 Drift 代码（首次/改表后）
flutter build apk --release                                  # 或 --debug
```

## 首次运行注意

App 内置 20 种常见倒班方式模板，**新建排班时选一个最接近你的倒班方式即可**（如「白夜休休」「白白夜夜休休」「四班三倒」「五班三倒（10 天一轮）」「上 24 休 24」……）；自己调好的那套还能「存为模板」，下次新建时从「我的模板」里直接选。

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

## 文档链接校验

改完 `docs/` 里的文档跑一下 `python scripts/link_check.py`：它扫 `docs/` 下所有 `.md`（外加 `AGENTS.md` / `README.md` / `BUILD.md`）里的相对链接与图片，按「链接所在文件所在目录」解析，`文件:行号` 这种引用会先去掉尾部行号再试一次；退出码 0 = 无断链，1 = 有断链并逐条打印来源与目标。

**它会先剥掉围栏代码块与反引号内容** —— 那里的 `[文字](链接)` 是给人看的举例，不是链接（少了这一步就会误报，见 `AGENTS.md`「关键决策与坑」第 10 条）。现状基线（2026-11-06）：118 个文件 / 105 条链接，图片 **0 断**；另有 34 条「文件:行号」式相对路径断在 `docs/superpowers/plans|specs`，那是历史 plan 目录，按原样保留不修。

## 目录结构

```
app/lib/
  main.dart               入口（初始化闹钟服务、液态玻璃着色器预热）
  app.dart                根 Widget（跟随系统深浅主题；字号自管那一层也在这里）
  core/
    app_info.dart         版本号（与 pubspec 同步，由 test/app_info_test.dart 把关）
    design_tokens.dart    设计语言唯一来源（按角色命名的排版 / 明度 / 间距 / 圆角 / 时长）
    l10n.dart             中英双语 t(zh,en)
    layout.dart           悬浮控件 / 导航胶囊的底部留白常量
    theme/                深空蓝紫配色 + 深浅两套主题 + 状态栏判据 statusBarStyleFor()
    glass/                标准档 glass.dart · 液态档 liquid_lens.dart · 真折射 glass_refraction.dart
    widgets/              共享件（GlassSegment / GlassSwitch / GlassDialog / GlassButton / GlassPill /
                          GlassField / GlassValueRow / GlassSheetHeader / EmptyState / LoadingState /
                          glass_pickers / glass_snackbar …）
    haptics.dart · motion.dart · frame_notifier.dart · hex_color.dart · shift_palette.dart
  domain/                 纯 Dart 领域层（可单测，不碰 UI）
    shift_rotation.dart   轮换引擎 + dayNumber() / dateOnly()
    schedule_chain.dart   多套方案按日期衔接的解析（shiftOn / hasScheduleOn / classChoicesFrom）
    monthly_pattern.dart  按月排班
    recurring_todo.dart   重复待办（四种规则 + 按班次匹配 + upcomingFireTimes）
    lunar_info.dart       农历 / 节气 / 法定节假日表
  data/
    app_database.dart     Drift 表 + 迁移（schemaVersion 15）
    app_repository.dart   仓库（读写 + 重排入口）
    todo_archive.dart     待办归档（上限 100，只裁已完成的行）
    seed.dart             默认「四班两倒」种子数据
  state/app_settings.dart 主题 / 主色调 / 语言 / 液态玻璃 / 触觉（Riverpod）
  features/
    schedule/             待办与日程（含系列编辑器 recurring_series_editor.dart）
    calendar/             月历 + 排班编辑器 + 排班管理（+ info_card_metrics：信息卡高度测算）
    alarm/                闹钟页 + AlarmService（原生联动）+ 响铃界面
    home/                 底部导航壳 + glass_nav_bar（两条档位各一棵树）
    profile/              我的页 + 权限卡 + app_dialogs（更新日志 / 使用引导 / 使用帮助）
    widget/               桌面小组件的快照生成与投递（快照协议 v2）
app/shaders/glass_refraction.frag    液态玻璃折射（Impeller 专用，Skia 自动回落）
app/android/app/src/main/kotlin/com/daoban/shiftassistantpro/
  MainActivity.kt         MethodChannel（openAppSettings / openUrl / installApk / startAlarm …）
  AlarmScheduler.kt · AlarmReceiver.kt · AlarmRingService.kt · AlarmStore.kt · AlarmSound.kt · AlarmLog.kt
  BootReceiver.kt · TodoReminderReceiver.kt
  ShiftWidgetBase.kt + WeekStripWidgetProvider / TodayCardWidgetProvider / MonthWidgetProvider
  WidgetRenderer.kt · WidgetChip.kt · WidgetStore.kt · WidgetVariant.kt · WidgetRefreshScheduler.kt
app/test/                 单测（只增不减）；app/tool/visual/ 是视觉工装（屏单 + 字号护栏）
```

完整版图（按模块说明与守卫用例）见 `AGENTS.md` 的「目录架构地图」。
