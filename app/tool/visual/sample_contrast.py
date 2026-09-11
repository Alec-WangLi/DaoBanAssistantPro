#!/usr/bin/env python3
"""在渲染图上采样一小块区域，算出「最深的那几个颜色」之间的对比度。

为什么需要它：`contrast_audit_test.dart` 用的 `textContrastGuideline` 是启发式的
（取区域内颜色直方图的两个众数），对 12–13px 的小字常常取到的是抗锯齿边缘或
底色，**会高报**。确认一条告警到底成不成立，唯一的办法是去看真实像素。

用法：
    python tool/visual/sample_contrast.py build/visual/01_calendar_light.png 100 1460 540 1525

参数是 `图片 x1 y1 x2 y2`（像素坐标，出图是 2 倍图）。不加坐标时，列出一张图的
尺寸就退出。

输出：该区域里出现次数超过阈值的最暗的几个颜色，以及它们彼此的对比度。
"""

import sys
from collections import Counter
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install Pillow")


def _channel(v: float) -> float:
    v /= 255.0
    return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4


def luminance(c) -> float:
    """WCAG 相对亮度。"""
    r, g, b = c[:3]
    return 0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b)


def contrast(a, b) -> float:
    """WCAG 对比度（1:1 ~ 21:1）。"""
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hexc(c) -> str:
    return "#%02X%02X%02X" % c[:3]


def main() -> None:
    if len(sys.argv) not in (2, 6):
        sys.exit(__doc__)

    path = Path(sys.argv[1])
    if not path.exists():
        sys.exit(f"找不到 {path}（先跑 render_screens_test.dart 出图）")

    im = Image.open(path).convert("RGB")
    if len(sys.argv) == 2:
        print(f"{path}  {im.size[0]}x{im.size[1]}")
        return

    x1, y1, x2, y2 = (int(v) for v in sys.argv[2:6])
    crop = im.crop((x1, y1, x2, y2))
    histogram = Counter(crop.getdata())

    # 出现次数太少的颜色多半是抗锯齿过渡，滤掉再找「最暗的实心色」。
    solid = [(c, n) for c, n in histogram.items() if n > 12]
    if not solid:
        sys.exit("这个区域几乎没有实心颜色，坐标可能选偏了")

    solid.sort(key=lambda cn: luminance(cn[0]))
    print(f"{path.name} 区域 ({x1},{y1})-({x2},{y2})  最暗的实心颜色：")
    for c, n in solid[:6]:
        print(f"  {hexc(c)}  x{n:<6d} 相对亮度 {luminance(c):.3f}")

    if len(solid) >= 2:
        # 第一暗通常是字，第二暗通常是它压着的底 —— 但不总是，所以要人工看一眼。
        print(f"\n  第 1 暗 vs 第 2 暗：{contrast(solid[0][0], solid[1][0]):.2f}:1")
        print("  第 1 暗 vs 最亮（底色）："
              f"{contrast(solid[0][0], max(histogram, key=luminance)):.2f}:1")


if __name__ == "__main__":
    main()
