---
name: coolapk-post
description: '倒班助手Pro 的酷安发帖：正文结构、配图编号、dist/coolapk 素材、视频与平台规格导出。Use when 写酷安稿 / 发帖 / 更新公告 / 配图 / 宣传素材 / coolapk / 小红书.'
---

# 酷安发帖稿与素材

## 文件在哪

| 东西 | 位置 | 说明 |
|---|---|---|
| 发帖稿 | `docs/coolapk-post.md` | **直接拿去发帖的草稿**，正文是酷安编辑器能吃的纯文本 |
| 发帖图 | `dist/coolapk/01-cover.png …` | 已按图序编号，**不入库** |
| 原始生成物 | `work/promo-out/` | 不入库，由 `python scripts/make_promo_images.py` 生成 |
| README 用图 | `docs/images/shot-*.png` | 同一批界面的带机身外框版 |
| 每版归档 | `docs/release/vX.Y.Z/` | 该版的酷安稿与配图 |

## 正文结构（照既有稿写）

1. **标题**：一句人话 + 竖线 + 三个卖点（例：「无广告 · 无账号 · 纯本地」）。
2. **开头痛点**：倒班人的具体场景，不写功能列表。
3. **分节正文**：每节对应一个能力，标题里带【图 N】，与图序表一一对应。
4. **更新说明**：正式版用归纳版，测试版只写本版。
5. **结尾**：下载方式、官网、开源地址。

## 图序纪律

- 稿子里开头的「图序」表就是唯一出处：`【图 N】` ↔ `dist/coolapk/NN-*.png`。
- 新增图要同时改三处：稿子的图序表、正文里的【图 N】、`make_promo_images.py` 的输出。
- 少一张就是线上裂图；多一张就是白传。
- GIF 沿用编号小数（`06.2-xxx.gif`），不要重排已有编号。

## 视频（ffmpeg-skill）

酷安与小红书都吃视频，比 GIF 清晰、体积也可控。素材先用本地截图/录屏，再用
`.claude/skills/ffmpeg-skill` 处理（**本机用 `python`，不要用 `python3`**）：

```bash
# 9:16 竖屏：--aspect 只改形状、不放大，要成片尺寸再加 --width
python .claude/skills/ffmpeg-skill/scripts/fit.py in.mp4 --aspect 9:16 --fit crop --width 1080 --json

# 交付检查：工具里没有小红书/酷安预设，短视频用 tiktok 这套 9:16 规格最接近
python .claude/skills/ffmpeg-skill/scripts/check.py out.mp4 --platform tiktok --json

# 响度归一（平台普遍按 -14 LUFS）
python .claude/skills/ffmpeg-skill/scripts/loudness.py in.mp4 -I -14 --tp -1 --json
```

- 先 `probe.py` 看真实参数，再动手；写完用 `check.py` 核，**以 `--json` 的数字为准**。
- 原片不覆盖；产物放 `work/promo-out/`，发布用的放 `dist/coolapk/` 并编号。
- 视频文件不要进仓库（`dist/` 已 gitignore）。

## 发布后

- 酷安帖子里的版本号、图序、下载链接要与 `latest.json` 当前版本一致。
- 发完把该版稿子留档到 `docs/release/vX.Y.Z/`。
