# 参与开发

先说清楚这是个什么项目：一个人维护的 Android App（Flutter），无账号、无后端、纯本地离线。
欢迎 Issue 与 PR，但请接受两点现实 —— **没有回复时限**，以及**不是每个想法都会被做**。

## 提 Issue 之前

- 先升到最新版本再复现。旧版问题一律先升级再谈。
- 先搜一下 Issues，重复的直接在旧帖里补充。
- **「XX 功能没有」先看一遍 [README 的功能清单](../README.md#-功能特性)** —— 很多能力其实已经有了，
  只是入口不明显。这种情况更好的是提「入口不好找」，而不是提一个新功能。
- 安全漏洞**不要开 Issue**，走 [私密上报](../security/advisories/new)，见 [SECURITY.md](../SECURITY.md)。

闹钟类问题请附上诊断包（「我的 → 查看日志 → 导出诊断包」）。没有它基本只能靠猜：
它里面有日志、设备与权限快照、已排闹钟清单和未来 7 天计划，全部在本机生成，不会上传。

小米 / Redmi 用户请先确认「后台弹出界面」「锁屏显示」「自启动」三项都开了 ——
不开「后台弹出界面」时系统会静默拒绝 App 从后台拉起响铃界面，表现是「只响不弹」，
看起来完全像 bug。

## 环境

| | 版本 | 说明 |
|---|---|---|
| Flutter | **3.47.2 stable**（Dart 3.13.2） | 别换版本。视觉工装里那些「某字号下不截断」的断言是按这一版量的字体度量 |
| JDK | 17 | 只有出 APK 才要 |
| Android SDK | `platforms;android-35` + `build-tools;35.0.0` | 只有出 APK 才要 |

**跑测试不需要 Android SDK，也不需要 JDK。** 详细步骤、Windows 上的符号链接坑、
以及六条最贵的踩坑记录，都在 [BUILD.md](../BUILD.md) 的「第一次跑测试」一节。

## 分支纪律

```
main    ← 只有正式版（版本号末位为 0）才收一次 --no-ff 合并
beta    ← 日常开发与测试版发布都在这里
```

- **PR 一律提到 `beta`。** 提到 `main` 的 PR 会被关掉重开。
- 从 `beta` 拉分支，别从 `main`。
- `main` 与 `beta` 的分叉是正常的：每个测试版都会在 `main` 上落一条「同步发布清单」的提交。

## 提交前必须过的检查

```bash
cd app
flutter analyze                 # 必须 No issues found!
flutter test                    # 全绿；条数认 ci.yml 的 EXPECTED_TESTS，只增不减
flutter test tool/visual/       # 动了界面才要跑，条数认尾行 +N
```

CI 会在 `beta` 上跑同样的东西，另外还跑 Android Lint（`NewApi` 等 API 等级检查）。
本地等价命令：

```bash
cd app/android && ./gradlew :app:lintDebug
```

> 同一台机器上**不要同时跑两份 `flutter test`** —— 两个进程抢同一个 `app/build/test_cache/`，
> 表现不是报错，而是某几条用例莫名其妙地红。

## 代码约定（摘要）

完整规范在 [`docs/standards/`](../docs/standards/README.md)，这里只列最容易踩的几条：

1. **界面上的钟点一律 24 小时制。** `TimeOfDay.hourOfPeriod` 会把 20:10 写成「08:10」。
2. **用例里的日期与时钟走 `appNow()` + `kAnchor`，不直接 `DateTime.now()`。**
   依赖真实「现在几点」的用例是定时炸弹 —— 有一条在 23:55–23:59 之间必红。
3. **颜色与间距只写角色名**（`core/design_tokens.dart`），不写字面值。
4. **触觉统一走 `core/haptics.dart`**，别处不许直接调 `HapticFeedback.*`。
5. **改了 Drift 表要跑 `dart run build_runner build`**，生成物是入库的，CI 会比对是否落后。
6. **不要跑 `dart format`。** 工具链是新版 tall style 格式化器，一跑就重排整个文件、
   制造几百行无关 diff。只跑 `analyze`。

## 版本号

形如 `X.Y.Z+build`。**`X.Y` 只有维护者能定，PR 里不要改**；
需要发新版时维护者统一改，改的时候 `app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处必须同步
（`app/test/app_info_test.dart` 会拦）。

## 许可

提交即表示同意以 [MIT](LICENSE) 许可发布。
