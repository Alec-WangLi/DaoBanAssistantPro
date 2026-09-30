#!/usr/bin/env python3
"""逐像素比两组工装出图，把「哪些屏变了、变了多少」列出来。

为什么需要它：`app/tool/visual/` 那 197 条刻意**没有 golden 基线**（它的用途是「看」，
不是比对）。但有一类改动必须回答「**标准档一个像素都没变**」—— 液态玻璃那一档
（v0.10.x）和它后面所有迭代都属这一类。手工开图比是看不出来的：差 1/255 和差 200
在肉眼里都只是「差不多」。

所以流程固定成三步：**改之前先渲一遍存起来 → 改 → 再渲一遍 → 跑这个脚本**。
差异**不是失败**，是待解释项 —— 脚本只负责把它们按差异大小排出来，判断「可不可解释」
仍然是人（或 AI）的事。v0.10.1 那轮吃过两种假象，两种都记在这里：
  · 「响铃界面的时钟跳了一位」—— 两次渲染之间真的过了分钟，是**内容**变了；
  · 「`34_app_info` 的更新日志不一样」—— 基线本身早于目标版本，比的根本不是同一版。
两条都不是像素管线的问题，但都能让人以为改坏了。

用法：
    python scripts/diff_visual.py app/build/visual/baseline-v0102 app/build/visual
    python scripts/diff_visual.py A B --filter home_shell     # 只看名字含它的
    python scripts/diff_visual.py A B --threshold 0            # 严格逐位
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageChops

DEFAULT_THRESHOLD = 8


def compare(a: str, b: str, threshold: int) -> tuple[int, int, int] | None:
    """返回 (有差异的像素数, 总像素数, 单通道最大差)；尺寸不一致时返回 None。

    **取三通道的最大值再判阈值，不能先 `convert("L")`** —— 后者按亮度加权，
    只差在蓝通道上的 50 会被压成不到 4，整片漏报。
    """
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return None
    diff = ImageChops.difference(ia, ib)
    r, g, bl = diff.split()
    peak_img = ImageChops.lighter(ImageChops.lighter(r, g), bl)
    peak = peak_img.getextrema()[1]
    # `point` 把每个像素压成 0/255，再数直方图的最后一格 —— 比逐像素 Python
    # 循环快两个数量级。
    mask = peak_img.point(lambda v: 255 if v > threshold else 0)
    changed = mask.histogram()[255]
    return changed, ia.size[0] * ia.size[1], peak


def main() -> int:
    # Windows 控制台默认走 GBK，中文输出会变成乱码 —— 显式钉成 UTF-8。
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:  # noqa: BLE001 —— 老 Python 上没有 reconfigure，忽略即可
        pass

    ap = argparse.ArgumentParser()
    ap.add_argument("baseline", help="基线目录")
    ap.add_argument("current", help="当前目录")
    ap.add_argument("--filter", default=None, help="只比文件名含这个子串的")
    ap.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD,
                    help=f"单通道差多少才算变了（默认 {DEFAULT_THRESHOLD}）")
    ap.add_argument("--top", type=int, default=40, help="最多列多少张有差异的")
    args = ap.parse_args()

    names = sorted(f for f in os.listdir(args.baseline) if f.endswith(".png"))
    if args.filter:
        names = [n for n in names if args.filter in n]

    missing = [n for n in names if not os.path.exists(os.path.join(args.current, n))]
    identical: list[str] = []
    differing: list[tuple[int, int, str]] = []

    for n in names:
        if n in missing:
            continue
        r = compare(os.path.join(args.baseline, n), os.path.join(args.current, n),
                    args.threshold)
        if r is None:
            differing.append((-1, 0, n + "   （尺寸不一致！）"))
            continue
        changed, total, _ = r
        if changed == 0:
            identical.append(n)
        else:
            differing.append((changed, total, n))

    # 只在当前目录、不在基线里的（新增的屏）
    extra = sorted(f for f in os.listdir(args.current)
                   if f.endswith(".png") and f not in set(names))

    print(f"比了 {len(names) - len(missing)} 张：{len(identical)} 张逐像素相同，"
          f"{len(differing)} 张有差异")
    if missing:
        print(f"  基线里有、当前目录没有（{len(missing)}）：{missing[:5]}")
    if extra:
        print(f"  当前目录多出来的（{len(extra)}）：{extra[:5]}")
    if differing:
        print("\n差异（按变化像素数降序）：")
        for changed, total, n in sorted(differing, reverse=True)[: args.top]:
            if changed < 0:
                print(f"  {n}")
            else:
                pct = 100.0 * changed / total
                print(f"  {changed:>8} / {total}  ({pct:5.2f}%)  {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
