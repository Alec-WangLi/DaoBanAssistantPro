# 正式版独立审查 · v0.14.0

## 0. 审查范围

- 版本：v0.14.0（上一个正式版 tag `v0.13.0` → 本次 `25dce5c`）
- 提交范围：`git log --oneline v0.13.0..HEAD` 共 **83 条**（v0.13.1~v0.13.27 二十七个测试版 + 收尾 / 发布准备提交）
- 审查时间：2026-11-25 21:10–21:55（+08:00）
- 审查者：独立 Claude Code subagent，未参与本版开发，只读代码、文档与提交记录
- 审查对象：提交 **`25dce5c`（工作区干净）** + `dist/倒班助手Pro-v0.14.0.apk`（构建于 21:19:57）
- 过程说明：审查期间开发方仍在收尾（21:14–21:18 改过 `AGENTS.md` / `app_dialogs.dart` / `v0.14.md` / `site/index.html` / `build_site.py`），21:31 提交为 `25dce5c`。本报告以该提交为准；关键文件 SHA-256 前 12 位如下，若之后再改，本报告需重跑。

```
99b473b75054  app/pubspec.yaml
009fae1ad4da  app/lib/core/app_info.dart
ef7849058e1c  app/lib/features/profile/app_dialogs.dart
2a0925390491  app/lib/features/profile/help_content.dart
28735780cefc  app/test/changelog_dialog_test.dart
86bc368b07b7  app/tool/promo/render_promo_test.dart
e62ced9b8a2f  README.md
4faa099b94dc  PRODUCT_SPEC.md
b58549816c48  site/index.html
88399bcd6697  scripts/build_site.py
7bdb1f1310c8  docs/changelog/v0.14.md
f4e1c2404728  docs/changelog/releases.md
5f0fbcc77b80  docs/changelog/version-history.md
70a7b3529896  docs/coolapk-post.md
55e4b6f9df4b  docs/v0.14.0-update-post.md
```

- APK：包名 `com.daoban.shiftassistantpro`，`versionName=0.14.0`、`versionCode=215`、minSdk 26、`arm64-v8a` only；SHA-256 `4509995757E062741F19BECF440A63E634BAD56FB1ECD3D9B8DE4AF1833889C8`。

## 1. 必查项（逐条给结论 + 证据）

| # | 检查项 | 命令 / 依据 | 结论 |
|---|---|---|---|
| 1 | 版本号两处一致 | `app/pubspec.yaml` → `version: 0.14.0+215`；`app/lib/core/app_info.dart` → `const String appVersion = '0.14.0';`；`bash tools/flutter-test.sh test/app_info_test.dart` 通过。模板写的是 `app/core/app_info.dart`，实际路径是 `app/lib/core/app_info.dart` | ✅ 一致 |
| 2 | 用例基线 | CI run 45606064539（commit 661349f）日志：`+1429: All tests passed!`、`用例数 1429（期望 1429）`；`.github/workflows/ci.yml:29` → `EXPECTED_TESTS: '1429'`。`25dce5c` 相对 661349f 只改文案 / 版本号 / 用例断言，本机在该提交上跑定向用例 14 条全过（`app_info` / `changelog_dialog` / `changelog_window` / `site_copy` / `help_content`）。本机另尝试重跑全套，flutter 的 frontend_server 卡住（22 分钟仅 4s CPU、0 输出），已停止并清理 3 个残留 dart 进程 —— 全量数字以 CI 为准 | ✅ 基线一致（注：25dce5c 尚未推送，CI 还没在它上面跑过） |
| 3 | analyze 干净 | CI 日志 `No issues found! (ran in 12.9s)`；本机在 25dce5c 上 `flutter analyze` → `No issues found! (ran in 12.7s)` | ✅ 0 issue |
| 4 | Kotlin / 清单改动 | `git diff --stat v0.13.0..HEAD -- app/android` = 12 files, +2001/−148（闹钟链、Haptics、诊断包、watchdog）；`gh run list --workflow=android-lint.yml` 最近一次 beta push（commit 661349f）run 45606064440 **success**；25dce5c 无 Kotlin / 清单改动；APK 内 `AlarmWatchdogReceiver exported=false`（aapt2 xmltree 实测） | ✅ 有改动，已过 Android Lint |
| 5 | 迁移 / 表结构 | `app_database.dart:381` → `schemaVersionNumber = 18`；`onUpgrade` 有 `<18`（`shift_day_notes`）、`<17`（extras 加 `leave_kind`/`note`）、`<16`（`shift_day_extras` + `isNight`）三段；`app/test/migration_v15_to_v16_test.dart`、`migration_v16_to_v17_test.dart`、`migration_v17_to_v18_test.dart` 均在 1429 内 | ✅ 覆盖 |
| 6 | 用户可见文案走 L10n（E12） | 新增 / 修改的帮助两条走 `L10nText`（`help_content.dart:139-145`、`281-286`）；更新日志是产品既有的中英双常量；`changelog_window_test` 机械校验「10 条 / 首条=appVersion / 中英版本号列表一致 / 无 markdown」，本次通过 | ✅ 合规 |
| 7 | 日期 / 时钟走 `appNow()`（E5） | `holiday_sync.dart:80`、`stats_screen.dart:65/107/149`、`alarm_screen.dart:88` 均走 `appNow()`；`grep DateTime.now()\\|TimeOfDay.now()` 在 `app/lib` 只剩注释与响铃屏显示当前时钟 | ✅ 合规 |
| 8 | 未提交的临时改动 | 审查开始时 29 项，21:31 已全部进入 25dce5c；现在 `git status --short` 为空；无 `.orig` / `.rej` / `debugPrint` 残留；三件 untracked（`v0.14.md`、`shot-stats.png`、`update-post`）均已入库 | ✅ 干净 |
| 9 | 文档同步 | `site/index.html:177` 更新日志有 v0.14.0 正式版；`PRODUCT_SPEC.md:1/19/147` 抬头、§2、schema 18；`docs/changelog/` 的 v0.14.md / releases.md / version-history.md 都已补；酷安稿与 update-post 已升版。**README 下载行的测试版版本号写错**（见发现 1） | ⚠️ 除 1 处外同步 |
| 10 | 发版资产 | `aapt2 dump badging`：包名 / 0.14.0 / 215 / minSdk 26 / arm64-v8a 全对；`apksigner verify --print-certs` 的证书 SHA-256 `265d09b2…ce893` 与 `keytool -list -v release.jks` **逐位一致**；APK 的 SHA-256 与 `tools/gh/release-notes-v0.14.0.md:53` 一致；23.45 MiB < 站点 25 MiB 硬闸；`latest.json` 仍是 0.13.0 / 0.13.27（发布脚本第 8 步更新，预期内）。GitHub 仓库描述未刷新（见发现 7） | ⚠️ 资产正确，流程项待办 |

本次实际跑过的检查命令（节选）：

```bash
git log --oneline v0.13.0..HEAD            # 83 条
git status --short                         # 空（25dce5c）
bash tools/flutter-test.sh test/app_info_test.dart test/changelog_dialog_test.dart \
  test/changelog_window_test.dart test/site_copy_test.dart test/help_content_test.dart
  # → 00:00 +14: All tests passed!
flutter analyze                            # → No issues found! (ran in 12.7s)
gh run view 45606064539 --log | grep …     # → +1429 All tests passed / 用例数 1429（期望 1429）
gh run list --workflow=android-lint.yml    # → run 45606064440 success (beta push)
aapt2 dump badging "dist/倒班助手Pro-v0.14.0.apk"
apksigner verify --print-certs "dist/倒班助手Pro-v0.14.0.apk"
keytool -list -v -keystore app/android/keystore/release.jks
sha256sum "dist/倒班助手Pro-v0.14.0.apk"
file docs/images/*.png ; wc -c docs/changelog/*.md
gh repo view --json description,repositoryTopics
```

## 2. 风险面（本版改了什么，可能漏什么）

- **改动模块**：未提交 / 本次提交层面只有三处非文档代码改动 —— `app_dialogs.dart` 的更新日志、`help_content.dart` 的两条帮助、promo 工装（新增 `11_stats`）。但 v0.14.0 是 v0.13.0 以来二十七个测试版的收口，随版实际交付的代码包括：统计页（新屏）、请假 / 加班（新表 schema 16→18）、数据备份、闹钟原生链路大改（12 个 Kotlin 文件，+2001 行）、触觉原生通道、节假日自动更新、选择器 / 弹层、日志整页 + 诊断包、按品牌权限。
- **这类改动的历史踩坑**：`docs/decisions/alarm.md`（三档落点、改排班后必须重排）、`data.md`（迁移只能加不能删）、`ui-rules.md`（`viewInsets` 顶整块面板、状态栏样式）、`glass.md`（shader uniform）、`widget.md`（RemoteViews 只 inflate 一次）；发布侧：worktree 构建会丢签名、`latest.json` 只能改本次通道、Pages 单文件 25 MiB。
- **本次最可能漏测的路径**：
  1. 真机 OEM 权限行为（三星「休眠应用」、一加 / OPPO「自启动」）只能上真机看；
  2. `AlarmWatchdog` 的非精确 6 小时巡检在 Doze / 各家 ROM 上的实际触发；
  3. CSV 的 `endMinute = 1440` 与回绕形态 —— 现有用例只断言了 `20:30–08:30`，**没断言「次日」后缀本身**（见发现 10）；
  4. 备份导入在「删旧库」与「rename」之间失败（无用例覆盖，见发现 9）；
  5. 老机型的 Impeller 字形图集问题：v0.13.27 是缓解不是根治，用户 2026-11-25 已拍板保留 Vulkan、等上游修。
- **归纳版取舍**：正式版条目从 16 条压到 9 条（`docs/changelog/v0.14.md` §⑩ 有记录），代价是两条用户可见项没进正式版条目（见发现 13）。

## 3. 发现

| 级别 | 位置 | 问题 | 处置 |
|---|---|---|---|
| 阻断 | `README.md:170` | 「最新 **正式版 v0.14.0**、**测试版 v0.14.0**」——**没有 v0.14.0 测试版**。`latest.json:9` 的 prerelease 仍是 `0.13.27`；`scripts/release.ps1:401/412` 对 `Z=0` 只更新 `stable` 通道，`prerelease` 不会跟着变。仓库门面是正式版清单第 1 项，写错版本会误导下载。改 `测试版 v0.14.0` → `测试版 v0.13.27`（或删掉测试版半句）即可 | 修完再发（纯文案，一改即可，不必重跑代码门禁） |
| 建议 | `docs/changelog/v0.14.md:8` | 同文件第 7 行写「二十七个测试版」，第 8 行却写「**七个测试版**的细节读 `v0.13.md`」—— 漏了「二十」 | 由用户决定是否带进本版（1 字修正） |
| 建议 | `PRODUCT_SPEC.md:63`（§2 第 19 条） | 日志描述仍是旧版：「只记录错误 / 崩溃（普通信息走 Logcat）…可查看 / 复制 / 清空」。v0.13.18/0.13.20 起已是按天归档、保留 7 天、搜索、诊断包；同文件 `113` 行和 `README.md:111` 都已是新行为。规格自称「现状」，这条已过时 | 由用户决定（建议改写第 19 条，或加「见 §v0.13.1~0.13.27」指针） |
| 建议 | `help_content.dart:143` | 英文帮助说跨午夜班次被标为 `"next day"`，CSV 实际写的是 ` (+1d)`（`stats_export.dart:179`）；中文 `142` 行的「次日」与实际 `（次日）` 一致。英文用户会照着找不存在的字符串 | 由用户决定（改英文文案为 `(+1d)`，或把导出标记统一成 `next day`） |
| 建议 | `README.md:15-17` | README 的四张动图仍是 `v0130-*.gif`（本版未重出）；本版改过选择器把手 / 深色图标 / 滑块，`docs/coolapk-post.md:9-12` 自己也写着 GIF 要按 `tool/gif/` 重出。静态图（hero + 10 张 shot）已重出，GIF 未动 | 由用户决定是否本轮重出 |
| 建议 | `tools/gh/release-notes-v0.14.0.md:52-53` | 现在的 SHA256 / 大小与当前 `dist` APK 完全一致（已核对）。但正式版发布前要在 main 合并且**重建**（`release.ps1:150-166` 的 mtime 闸门会把 beta 上构建的 APK 拦下），重建后 SHA 必变，而脚本对已存在的 notes 只复用不更新（`release.ps1:269-290`）。重建后必须手工改这两行 | 由用户决定（发版步骤，非代码问题） |
| 建议 | GitHub 仓库描述 / topics（`gh repo view` 实测） | 描述仍停在 v0.8 时代的功能清单，没有统计、请假加班、数据备份；topics 也没有 `statistics` / `backup`。正式版清单第 3 项要求刷新 | 由用户决定（发版前 `gh repo edit`） |
| 记录 | `docs/changelog/README.md:8-15` | 索引表的「字节」列已过时：`releases.md` 记 3910 / 实 5192，`version-history.md` 记 61830 / 实 69817，`v0.14.md` 记 5080 / 实 5562（21:17 又加了 §⑩），`v0.11/v0.10/v0.9` 也各差 50–254 B | 转下个版本（或去掉「字节」列） |
| 记录 | `backup_service.dart:153-197`、`docs/coolapk-post.md:228`、`docs/changelog/v0.14.md:12` | 「中途失败旧库仍在 / 原子替换」不完全成立：`195` 行先删旧库，`197` 行才 rename；这两行之间失败会留下 `.restore` 且旧库已删（`pending_restore` 仍在，下次启动会重试，通常可恢复）。更稳的顺序是 old→`.bak`、new→db、成功后再删 `.bak` | 转 `docs/decisions/` 或下个版本 |
| 记录 | `app/test/stats_export_test.dart:90-121` | 用例名是「跨午夜班次标『次日』」，但断言只有 `contains('20:30–08:30')`，没断言 `（次日）` / `(+1d)` 后缀 —— 标记被改坏这条用例照样绿 | 转下个版本（补一条断言即可） |
| 记录 | `app/tool/promo/render_promo_test.dart:241` | 统计页宣传图（420×1000）底部把「出勤亮点」卡片切在半行，`docs/images/shot-stats.png`（564×1172）在 README / 官网可见。可接受为「下面还有内容」的暗示；若要更干净，画布加到 ~1100 或在卡片缝处收边 | 转下个版本 |
| 记录 | `app/test/changelog_dialog_test.dart:25` | `_visibleLog` 的过滤词从 `'v0.13.'` 换成 `'v0.1'`，下一轮升到 v0.2.0 时又会失效；建议用 `RegExp(r'^v\d+\.\d+\.\d+')` 或复用 `splitChangelogVersions` | 转下个版本 |
| 记录 | `app/lib/features/profile/app_dialogs.dart:49-72` | 9 条归纳版（`v0.14.md` §⑩ 说明是为压字形量）没有覆盖两条用户可见项：「调整班次」备注（v0.13.20）、「关于」页手动刷新节假日（v0.13.12）。按「正式版归纳全部测试版内容」的长期规则算轻微缺口；若用户认可这个取舍，保留即可 | 由用户确认取舍 |
| 记录 | `AGENTS.md:3` | 文件 37,683 B，超过自己写的「目标体积 ≤35KB」（本版之前已是 37,253 B，本次 +430 B）。离 harness 的 64KB 截断线还远，但已越过自设预算 | 转下个版本（压旧条目） |
| 记录 | `dist/倒班助手Pro-v0.14.0.apk` | 23.45 MiB，距 Cloudflare Pages 单文件 25 MiB 硬闸只剩约 1.55 MiB（`build_site.py` 有硬闸，超了会直接退出）。下个版本继续长大就会顶到 | 转下个版本（必要时转 R2） |

## 4. 结论

- [ ] 可以发正式版
- [x] 有阻断项，修完重审
- [ ] 有未修项，用户已拍板带进本版（记录原话）：

唯一阻断是 `README.md:170` 的一行文案（把「测试版 v0.14.0」改成「测试版 v0.13.27」）。这是纯文案修改，改完不需要重跑代码门禁；改完 grep 一次 `README.md` 的版本行即可。

已知未修项：老机型更新日志字形图集问题（v0.13.27 已缓解、未根治）。用户 2026-11-25 已拍板「保留 Vulkan、不换 Skia，等上游修」，不构成本版的新决定。

发版前流程提醒（不是代码问题）：

1. `25dce5c` 目前只在本地 beta（领先 origin/beta 1 个提交），先推 beta；正式版按纪律 `beta → main --no-ff`，tag 打在 main。
2. **APK 必须在合并后的 main 主 checkout 重建**：当前 APK 是在 beta 构建的，合并刷新 mtime 后 `release.ps1` 第 4 步会拦下；重建后同步更新 `tools/gh/release-notes-v0.14.0.md:52-53` 的 SHA / 大小。
3. 工作区必须干净（现在干净）；`latest.json` 的 `stable` 由脚本第 8 步更新，`prerelease` 保持 0.13.27 是对的。
4. 刷 GitHub 仓库描述与 topics；本文件随提交入库（`release` 技能会检查它存在）。

签名：独立审查者（Claude Code 独立 subagent，未参与本版开发）· 2026-11-25
