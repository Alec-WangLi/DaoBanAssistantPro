---
name: visual-triage
description: '倒班助手Pro 的视觉工装排障：本地重跑 tool/visual、按日志数图、区分真红与字体假红、重出 promo 图。Use when 视觉巡场红了 / 出图数量不对 / 截图差异 / visual.yml / 界面画崩 / 重出 promo 图.'
---

# 视觉工装排障

## 先分清两件事

| 你面对的东西 | 它回答什么 | 结论怎么用 |
|---|---|---|
| `flutter test tool/visual/`（本地） | 每个屏单能不能画出来、画出来几张 | **硬门禁**：不通过就是真问题 |
| `.github/workflows/visual.yml`（每日 18:00 UTC） | 今天全库能不能画完 | **只报告不拦截**，`continue-on-error: true` 是刻意的，别改成 false |

所以：**visual.yml 的结论永远是 success，不能拿结论判绿**。判绿要数图。

## 本地重跑

```bash
. toolchain/flutter/bin/activate 2>/dev/null || true
cd app && flutter test tool/visual/
```

- 认尾行 `+N`，**不要写死数量**（随屏单增长）。
- 字体已经进仓库（`app/test/fonts/`），`ensureVisualFonts()` 缺一个就无条件抛错 ——
  看到 `Found 0 widgets with key` 这类报错，先怀疑字体没就位，而不是布局坏了。
- 输出图在 `app/build/visual/`，直接看图比读断言快。

## 用 CI 日志数图（不要下 89MB 的 artifact）

```bash
gh run list --workflow visual.yml --limit 3
gh run view <run-id> --log | grep -aoE 'build/visual/[^ ]+\.png' | sort -u | wc -l
```

- 数出来的图和上一次差很多（例如从 337 掉到个位数）→ 是工装没跑完，不是界面全坏了。
- 差一两张 → 去 artifact 看具体那几张，再决定是不是布局溢出 / 文字被裁。

## 真红 vs 假红

| 特征 | 判定 |
|---|---|
| 大量用例同时报 `Found 0 widgets` / 文字渲染成方块 | 假红：字体环境 |
| 少数用例、集中在某个屏单 | 真红：布局或断言 |
| 图生成了但和上一版差几个像素、字距变了 | 假红：字体版本 |
| 图生成了但某块区域空白 / 溢出条纹 | 真红：`RenderFlex overflowed` 之类 |

## 动过 UI 之后

1. 本地跑一遍 `tool/visual/`，看图确认没有视觉退化。
2. 重出 promo 图（README、官网、酷安都用这批）：

```bash
cd app && flutter test tool/promo/render_promo_test.dart
python scripts/make_promo_images.py
python scripts/make_gif.py
```

3. `docs/images/` 里 `hero.png` 与 `shot-*.png` **全是生成物**，改了 UI 不重跑就等于
   README 挂着几个版本前的界面（0.8.0 那轮漏过）。
4. 正式版还要同步 `docs/release/vX.Y.Z/` 的配图与 `docs/coolapk-post.md` 的图序表 ——
   `build_site.py` 的 `PNGS` / `SHOTS` 列表必须与 `site/index.html` 一致。

## 相关文件

- `app/tool/visual/visual_harness.dart` —— 文件头写了字体坑的完整经过，改工装前必读。
- `app/tool/visual/` —— 屏单定义；新增屏单会改变图数，别把它当回归。
- `docs/decisions/ui-rules.md` —— 颜色 / 布局 / 弹窗 / 字号的口径。
