# 体积与性能优化方案（2026-11-10）

> **状态：方案待拍板，本轮没有改任何源码。**
> 所有数字均为本机实测：Flutter 3.47.2 / AGP 9.1.0 / release / arm64-v8a。
> 三份测量用 APK 已删除，`app/build/app/outputs/flutter-apk/app-release.apk` 已还原为 v0.13.3 原件
> （md5 `397ca32102e8ed5a0778a8701f9ac698`，与 `dist/倒班助手Pro-v0.13.3.apk` 一致）。

## 0. 先回答「有没有那种框架 / 算法」

**没有能把体积和流畅度同时「大幅」改善的现成框架。**

原因在构成里：22.35 MiB 中 **20.48 MiB（解压总量的 88%）是 Flutter 引擎 `libflutter.so` + Dart AOT 快照 `libapp.so`**。
这两块是 Flutter 的固定成本，换状态管理、换数据库、换 UI 库都不会动它们；真要动只能重建引擎或换技术栈，
成本与收益完全不成比例。

真正有效的只有三类手段：**打包开关**、**删没用到的资产**、**启动/渲染的定点优化**。
下面每一条都标了「实测」或「估算」，没有实测支撑的数字不会写成结论。

## 1. 实测构成（v0.13.3 现包）

| 文件 / 类别 | 大小 | 占解压总量 |
|---|---:|---:|
| `libflutter.so` | 11.20 MB | 48.2% |
| `libapp.so`（Dart AOT） | 7.69 MB | 33.1% |
| `libsqlite3.so`（drift 依赖） | 1.46 MB | 6.3% |
| `classes.dex` | 1.21 MB | 5.2% |
| `res/` | 0.60 MB | 2.6% |
| `assets/flutter_assets/` | 0.58 MB | 2.5% |
| 其它（`libdartjni.so`、`resources.arsc`、`META-INF` 等） | 0.36 MB | 1.5% |
| **合计** | **23.25 MB 解压 / 22.35 MiB（23,439,672 B）落盘** | 100% |

> 解压总量 23.25 MB、APK 22.35 MiB 的差额来自 dex 与少量资源被 zip 压缩；
> 三个 `.so` 全是 method=0（未压缩存储），所以引擎与快照的大小几乎 1:1 进 APK。

关键事实：

- **三个 `.so` 全部是 method=0（未压缩存储）**，所以 APK 大小 ≈ 解压总量。这是第 3 节 B1 的前提。
- `MaterialIcons-Regular.otf` 已被 tree-shake：构建日志原文
  `reducing it from 1645184 to 11436 bytes (99.3% reduction)`。
- 单 ABI（arm64）已经在用——这本来就是最大的一刀（全 ABI 约 60 MB），已经吃掉了。
- 22 MB 对一个带本地数据库、通知、桌面小组件、自绘玻璃效果的 Flutter release 包来说属于正常区间。

## 2. 三条路线（同一台机器实测）

| 路线 | 做法 | APK 实测 | 相对现状 |
|---|---|---:|---:|
| 现状 | v0.13.3 | 23,439,672 B / 22.35 MiB | — |
| **A** | 构建加 `--split-debug-info` | **22,260,024 B / 21.23 MiB** | **−1.12 MiB（−5.0%）** |
| **B** | A + 删无用资产（A2–A4，估算） | 约 20.9 MiB | 约 −1.4 MiB（−6.3%） |
| **C** | B + 压缩 native 库 | **10,868,656 B / 10.37 MiB** | **−12.0 MiB（−53.6%）** |

两条补充实测，用来判断「要不要混淆」：

- `--split-debug-info` **再加** `--obfuscate`：22,128,952 B（21.10 MiB），
  比只分离符号**只再省 0.13 MiB**。
- 压缩 + 混淆：10,819,968 B（10.32 MiB），比压缩 + 只分离**再省 0.05 MiB**。

**结论：混淆不值得。** 它只值 0.13 MiB，却要求把 3 处 `enum.name` 落盘改成稳定字符串
（`app/lib/state/app_settings.dart` 两处、`app/lib/features/widget/widget_service.dart` 一处），
而原生 `WidgetRenderer.kt` 还按 `"light"` / `"dark"` / `"system"` 字面比较；同时全 App 的日志堆栈会变得更难读。

## 3. 逐项清单

### A1 `--split-debug-info`（推荐，已实测）

- **改法**：release 构建命令加 `--split-debug-info=build/symbols`，产物是
  `app/build/symbols/app.android-arm64.symbols`（约 3.8 MB）。
- **收益（实测）**：`libapp.so` 7.69 → 6.56 MB（`.rodata` 3090 → 1967 KB），APK −1.12 MiB。
- **代价**：官方文档要求用 `flutter symbolize -i <日志> -d <符号文件>` 才能把堆栈还原成可读。
  实测里部分内部符号名消失，**一律按「需要 symbolicate」对待**；「我的 → 查看日志」里的堆栈会变短。
  → 每版必须把符号文件归档（见 §6），否则那一版的堆栈永久丢失。
- **落点**：`AGENTS.md` 的构建命令、`scripts/release.ps1` 的报错提示、`BUILD.md`。
- **验证**：构建后比字节数；故意抛一次异常，用 `flutter symbolize` 还原一次。

### A2 删 `cupertino_icons`（估算 −0.11 MiB）

- **依据**：`grep -rn "cupertino_icons\|CupertinoIcons" app/lib app/test app/tool` 无命中，
  但 APK 里仍有 `CupertinoIcons.ttf` 250 KB（压缩后 110 KB）。
- **改法**：从 `pubspec.yaml` 删依赖。
- **风险**：低。`flutter analyze` 会立刻抓出任何漏网引用。
- **验证**：analyze 0 error；测试条数不变；APK 里不再有该字体。

### A3 打赏二维码 PNG → WebP（估算 −0.1 MiB）

- **现状**：`alipay.png` 120 KB、`wechat.png` 69 KB。
- **改法**：转无损 WebP（或 q90 有损）。
- **风险**：二维码识别率，必须真机各扫一次（支付宝 / 微信）。
- **落点**：`app/assets/donate/`；`test/donate_assets_test.dart` 若按扩展名断言需同步。

### A4 打开 `isShrinkResources`（估算 −0.05 ~ −0.2 MiB，必须实测）

- **现状**：`app/android/app/build.gradle.kts` 里明确写着「资源收缩会把按名字引用的
  `res/raw/alarm_beep.wav` 当未使用删掉，必须关掉」。
- **改法**：新增 `app/android/app/src/main/res/raw/keep.xml`：
  `<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@raw/alarm_beep" />`，
  再把 `isShrinkResources = true`。
- **验证**：真机响一次内置铃声；再比 APK 字节数。收益小，做不做都行。

### B1 压缩 native 库（体积优先，可选，已实测）

- **改法**：`packaging { jniLibs { useLegacyPackaging = true } }`。
- **收益（实测）**：22.35 → **10.37 MiB（−12.0 MiB，−53.6%）**。
  三个 `.so` 的压缩率：引擎 47%、快照 39%、sqlite 51%。
- **代价（Android 官方原文）**：`extractNativeLibs="false"`（现状）是「APK 更大，但库直接从 APK 加载、
  启动更快」；改成 `true` 就是反过来——**下载更小、安装时解压、占用空间更大、冷启动略慢**。
  安装后磁盘约 `10.4 + 20.4 ≈ 30.8 MiB`（现状约 21.1 MiB）。
- **建议**：先做一次真机 A/B 冷启动（同机、清后台、`adb shell am start -W` 各 3 次取中位数），
  差值 ≤ 50 ms 再收；超过就退回。
- **风险**：功能零影响；主要是观感（「安装包 10 MB、占用 31 MB」）与冷启动。

### 不推荐 / 不用试

| 项 | 为什么不做 |
|---|---|
| `--obfuscate` | 只比 A1 再省 0.13 MiB，却要改 enum 落盘、日志更难读 |
| 换状态管理 / 数据库 / UI 框架 | 动不了引擎与 AOT 快照（占解压总量 88%） |
| UPX / 强压 `.so` | Android 不支持这种加载方式，会直接崩 |
| 自定义 Flutter 引擎（去 Skia 等） | 要自己编引擎、失去 `flutter upgrade`，省 2–3 MB，维护成本不成比例 |
| App Bundle / deferred components | 都依赖 Google Play 分发；本项目走官网 / GitHub 直装 |
| R8 full mode / tree-shake-icons / 单 ABI | 已经在用，没有增量 |
| Baseline Profile | 它优化的是 Java/Kotlin 的解释/JIT 代码；Dart 已是 AOT，收益很小，侧载分发还要等 profile 安装 |

## 4. 性能与流畅度

**已经生效、不用再动的**：Impeller 默认（API 29+）、R8 minify、arm64 单 ABI、图标 tree-shake、
卡片不挂 `BackdropFilter`（作者实测编辑排班页 raster p90 13.10ms → 2.37ms）、<4GB 内存自动关模糊。

所以「换个框架大幅提升」没有空间。剩下的是定点优化，且必须先量后改：

- **P0 折射链与 #194832（已实测，结论：不是问题）**：`GlassRefraction.filter` 用的是
  `ImageFilter.compose(outer: shader, inner: blur)`，形式上与
  [flutter/flutter#194832](https://github.com/flutter/flutter/issues/194832) 的触发条件一致。
  2026-11-10 在小米 25102RKBEC（Android 16 / API 36 / 1200×2608 / 60Hz）上用 profile 包实测，
  **同一次运行内 A/B 交替**（折射开 → 关 → 关 → 开 → 开 → 关，抵消热漂移）：

  | 配置 | raster p90（三次） | 中位数 | >16ms 帧 |
  |---|---:|---:|---:|
  | 液态档 + 折射开 | 13.61 / 14.75 / 14.09 ms | **14.09 ms** | 9 / 15 / 9（每 199 帧） |
  | 液态档 + 折射关 | 13.22 / 14.01 / 14.23 ms | **14.01 ms** | 8 / 10 / 8 |
  | 标准档（不启用液态） | 3.99 / 4.59 ms | **4.29 ms** | 0 |

  **折射的代价是 0.08 ms，在噪声以内——不要关它。** 这条引擎回归在这台机器/这版 shader 上没有
  可测量的影响（之前一次 17.66ms 是首轮热漂移，配对测量后消失）。
  **真正的开销在液态档本身**：p90 比标准档高约 **10 ms（3.3×）**，p99 高到 20–24 ms。
  所以优化方向不是折射，而是透镜 / 轨道这一套的绘制。

  > 测量注意事项（血的教训）：**动 applicationId 做测量包之前必须先备份用户数据**。
  > 本次只改了 `applicationId` 而保留 `namespace`，`flutter drive` 收尾按 manifest 包名卸载，
  > 把手机上正式安装的 `com.daoban.shiftassistantpro` 一并卸掉了。
  > 正确做法：同时改 `namespace`，或复制一份独立工程，且先确认有备份。
- **P1 启动**：`main()` 里 `initializeDateFormatting('zh')` → `SharedPreferences` → `AlarmService.init()`
  → 读 RAM 是**串行 await**，全在首帧之前。可改成「先定语言，再 `Future.wait` 并行」，
  用 `flutter run --profile --trace-startup` 量首帧。预期几十到一百多毫秒，**以实测为准**。
- **P2 不要用 `BackdropFilter.grouped`**：同一 issue 里明确写了，共享 backdrop 的批处理在这条
  shader + blur 链上**并不更快**（和逐个画一样慢），而且重叠的滤镜本来就不该共享 key。
  ~~上一版方案里「用 BackdropGroup 合并」这条建议作废。~~
- **P3**：不建议 baseline profile（理由见上表）。
- **量化工具**：`--profile` + DevTools 帧图；`adb shell am start -W`；`flutter test tool/visual/` 出图逐屏比对。

### 官方 Liquid Glass 组件：目前用不上

- `flutter/packages` PR **#13454 已于 2026-11-06 合入 `flutter:liquid_glass` 专用分支**（不是 `main`），
  属于 `cupertino_ui`；自带三支 shader，另有 vendored 的 MIT 渲染器。
- issue [#170310](https://github.com/flutter/flutter/issues/170310) 仍是 **open（P3，无负责人）**，
  官方没有承诺发布时间；pub.dev 上查不到这个包。
- 它是 iOS 26 保真方向，**Android 未确认**；即便发布，也是 Dart 层的 shader + `BackdropFilter`，
  与现有实现用的是同一套 Impeller 原语，不会凭空更快。
- 我们的实现已经做了通用组件不会做的事：卡片不挂模糊、光晕低频驱动、交互时暂停、折射默认关、
  低端机整档降级。换过去只会丢掉这些定制。

## 5. 建议执行顺序

1. 先落 **A1–A4**，发一版测试版（v0.13.4），把「体积」这件事收口。
2. **P0（已完成测量）**：折射开/关 p90 差 0.08 ms，**保持现状，不关折射**。
   下一轮若继续压液态档，用 DevTools timeline 定位 `LiquidLens` / `CapsuleRimPainter` 的绘制开销，
   候选手段：透镜外层加 `RepaintBoundary`、减少 `saveLayer`/阴影层数、把液态档限制在高刷设备。
3. **P1** 启动优化单独一版，附 `--trace-startup` 前后数字。
4. **B1** 等真机冷启动对比结果，由你拍板。

## 6. 验收与归档

- `flutter analyze` 0 error / 0 warning。
- `flutter test` 全绿，条数与 `.github/workflows/ci.yml` 的 `EXPECTED_TESTS` 同步。
- `flutter test tool/visual/` 断言全过、出图数量与屏单一致；二维码真机各扫一次。
- APK 字节数记录在案（见 §2），官网 25 MiB 闸门保持余量。
- 符号文件归档到 `dist/symbols/vX.Y.Z/app.android-arm64.symbols`（`dist/` 已 gitignore，**需本地备份**）。

## 7. 回滚

- **A1**：去掉 `--split-debug-info` 即可，源码零改动。
- **A2 / A3 / A4**：单文件回退。
- **B1**：删掉 `useLegacyPackaging` 一行，重新构建。
