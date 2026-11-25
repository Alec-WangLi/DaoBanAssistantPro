---
name: release
description: '倒班助手Pro 的发版流程：版本号双写、测试基线、签名校验、beta/main 分支纪律、latest.json 双通道、Cloudflare Pages 官网部署。Use when 用户说发版 / 发布 / 出包 / 打 tag / 发正式版 / release / 更新 latest.json.'
---

# 发版

> 只在用户明确说「发版 / 发布 / 打 tag / 按这个来」时执行。**说「先列一下」只输出清单，不动手**（AGENTS.md「方案闸门」）。
> 发版前置：本回合已按 AGENTS.md 开工 SOP 拿过现场（`git log` / `git tag` / `git status` / `pubspec.yaml` 的 `version:`）。

## 0. 先判定通道

| 版本号末尾 `Z` | 通道 | 分支 | tag 打在哪 | Release 标记 |
|---|---|---|---|---|
| `Z ≠ 0` | 测试版 | `beta` | beta 的提交 | 自动标「预发布」 |
| `Z = 0` | 正式版 | `beta` → `main`（`--no-ff`） | `main` | Latest |

**`X.Y` 只能由用户定，AI 只改 `Z` 并把 `build` 同步 +1**（E1）。

## 1. 落地改动（发版前）

- [ ] `app/pubspec.yaml` 的 `version:` 与 `app/lib/core/app_info.dart` 的 `appVersion` 同步 ——
      `app/test/app_info_test.dart` 盯着两处一致。
- [ ] 更新日志按 `changelog` 技能改（`_changelogZh` / `_changelogEn`）。
- [ ] 辅助信息随版本走：`site/index.html`、`README.md`、`PRODUCT_SPEC.md` 抬头、
      `docs/changelog/` 当版一条；`app/test/site_copy_test.dart` 会查版本号是否漏同步。
- [ ] 动过 UI → 重跑视觉工装并重出 promo 图（见 `visual-triage` 技能）。

## 2. 门禁（必须看到原始输出，不接受「我记得跑过了」）

```bash
bash scripts/verify-done.sh --full
```

- `flutter analyze` 0 error / 0 warning；`flutter test` 全绿。
- 用例条数与 `.github/workflows/ci.yml` 的 `EXPECTED_TESTS` 一致；**只增不减**，
  改基线要和用例改动同一个提交（E11）。数字以本机实跑尾行为准，不要推算。
- 改过 Kotlin / 清单 → 本地等价跑一次 Android Lint：
  `cd app/android && ./gradlew :app:lintDebug`。
- 改过 Drift 表 → `dart run build_runner build`（**不要加 `--delete-conflicting-outputs`**）。

## 3. 正式版专属：仓库门面 + 独立审查

`Z = 0` 时，在第 2 步之后、打 tag 之前，额外做两件事：

- [ ] 门面四件套：README 文案逐条对实现核、README 配图重出、GitHub 仓库描述与 topics、
      `docs/coolapk-post.md` 同步。
- [ ] **独立审查**：起一个只读的 subagent（或另起一轮全新上下文），按
      `docs/release/REVIEW-TEMPLATE.md` 审这一版的全部提交，产出
      `docs/release/vX.Y.Z/review.md`。**它没写出来就不许发正式版** —— 这条是自守，机器不拦。
      审查结论里出现的「未修」项，必须由用户拍板才能带进正式版。

## 4. 提交与发布

```bash
git tag vX.Y.Z
git push origin <分支>
git push origin vX.Y.Z
```

- 测试版：`git checkout beta` → 提交 → 推 beta → 打 tag → 推 tag。
- 正式版：beta 合 main（`--no-ff`）→ 在 main 上打 tag。
- ⚠️ **要发的 APK 只能在主 checkout 里构建**：`tools/`、`toolchain/`、`key.properties`、
  `release.jks` 都不进仓库，worktree 里构建会静默用 debug 证书签名（v0.11.16 真踩过）。

发布说明先写到 `tools/gh/release-notes-vX.Y.Z.md`，然后用：

```powershell
scripts\release.ps1 -SkipConfirm
```

**别加 `-SkipSignCheck`**：签名摘要对不上任何情况都不放行，工具不全时默认硬拦是刻意的。

## 5. 发完必须核对（脚本说成功只覆盖上传那一步）

- [ ] `latest.json` **两条通道都要 curl 回来核**：官网 `https://daoban-shift.pages.dev/latest.json`
      与仓库根 `raw.githubusercontent.com/Alec-WangLi/DaoBanAssistantPro/main/latest.json`。
      只改本次发布那一个通道的节点（+ `updatedAt`），**不要整份覆盖**。
- [ ] 官网：`release.ps1` 第 9 步负责 `build_site.py` + `wrangler pages deploy`。
      它失败只告警 —— 看到告警就手动补，否则下载页停在旧 APK。
- [ ] 国内用户主通道是官网清单；GitHub API 是第三条兜底，不要当主通道。

## 6. 常见故障

| 现象 | 处置 |
|---|---|
| 装机报 `Couldn't install (-7)` | APK 被 debug 证书签了名 → 回主 checkout 重建 |
| wrangler 报「非交互环境需要 CLOUDFLARE_API_TOKEN」 | `build-env.ps1` 把 `APPDATA` 重定向了，要临时指回真实 `%APPDATA%` |
| `Another git process seems to be running` | 先确认没有 git.exe，再删 `.git/AUTO_MERGE.lock`、`.git/packed-refs.lock` |
| beta 的 CI 红但本地绿 | 先看是不是 `EXPECTED_TESTS` 没同步（守卫本身红了），再按真 bug 查 |

## 7. 不要做

- 不跑 `dart format`（E10）；不并发跑 `flutter test`（会抢 `work/tmp`）。
- 不在 worktree 里构建要发的包；`dist/` 只留在主 checkout。
- 不擅自升 `X.Y`，不擅自改 `EXPECTED_TESTS` 去迁就红的结果。
