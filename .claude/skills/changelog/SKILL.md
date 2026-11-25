---
name: changelog
description: '倒班助手Pro 的更新日志写法：_changelogZh/_changelogEn 的 10 条窗口、正式版归纳、测试版原样、docs/changelog 版本流水。Use when 写更新日志 / 改更新弹窗 / 归纳正式版条目 / 版本记录 / changelog.'
---

# 更新日志

## 两个落点，别混

| 落点 | 是什么 | 谁看 |
|---|---|---|
| `app/lib/features/profile/app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` | App 内「更新日志」弹窗，**只留最近 10 条** | 用户 |
| `docs/changelog/v0.X.md` + `version-history.md` | 仓库里按大版本的完整流水 | 开发 / 判重 |

## App 内更新日志的三条长期规则

1. **窗口固定 10 条**：prepend 新版本，删最旧一条。
2. **正式版（`Z = 0`）的条目必须是「归纳总结版」**：合并自上一个正式版以来所有测试版的内容，
   不是只写自己这版改了什么。
3. **测试版条目原样保留**，只写自己这版改了什么。

> 例：v0.4.0 条目归纳 0.3.1~0.4.0 全部更新；v0.3.0 归纳 0.2.1~0.3.0；
> 测试版 0.2.4 的条目至今保留。中英两份要一一对应，不能只改中文。

## 写法

- 面向用户，写「能看见的变化」：什么场景、原来怎样、现在怎样。
- 一条一件事，不要把三处修复塞进一句。
- 带口径的变化要写清（例：「跨月夜班归上班开始那天」），否则用户会当成 bug 报。
- 不写内部实现词（Riverpod、Drift、MethodChannel），除非用户能感知到。

## 流程

1. 看本版实际改动：`git log --oneline <上一个 tag>..HEAD`。
2. 中文条目写好 → 同步英文条目。
3. prepend 到 `_changelogZh` / `_changelogEn`，保持长度 10。
4. `docs/changelog/v0.X.md` 补一条（正式版另在 `releases.md` 做归纳）。
5. `version-history.md` 补版本号链。
6. 跑 `app/test/` 相关用例 + `flutter analyze`。

## 与发版的联动

- `changelog` 改完，`site/index.html` 的更新日志段落要同步（正式版必须）。
- `app/test/site_copy_test.dart` 检查 site / README / SPEC 是否含当前版本号，漏了 CI 直接红。
- 正式版发布前，`docs/coolapk-post.md` 的「更新说明」段落按归纳版重写。
