#!/usr/bin/env python3
"""把工装逐帧出的一串 PNG 合成 GIF。

为什么单独一个脚本：更新简介的配图一直是静态截图，而「这一版改了什么」里有一半的
东西是**动**的（滑块拖动的光的响应、换月动画、弹簧回弹）。静态图拍不出来，用户也
读不出来。GIF 是成本最低的补法 —— 不需要视频、不需要播放器、GitHub 的 README
直接就能播。

帧从哪来：`app/tool/gif/render_gifs_test.dart` 调 `renderFrames()`
（在 `app/tool/visual/visual_harness.dart` 里）逐帧出图，落到
`app/build/visual/frames/<prefix>NNN.png`。

**素材与护栏分开**：逐帧那条线放在 `tool/gif/` 而**不**放进 `tool/visual/` ——
后者那 270+ 条是回归护栏，前者是产出素材（更新简介、商店页），跑法与用途都不同，
混在一起会让护栏的条数随「这次要不要出动图」浮动。

用法：
    python scripts/make_gif.py --prefix drag_rim_ --out work/gif/nav-rim.gif
    python scripts/make_gif.py --prefix drag_rim_ --out work/gif/nav-rim.gif \
        --crop 0,1560,840,1740 --width 640

体积是这里唯一需要调的东西：GIF 只有 256 色，帧一多就肥。默认参数是按
「≤10 秒、几百 KB」调的；`--fps` 降一档比 `--width` 降一档更省，且更不容易糊。
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

from PIL import Image

FRAMES_DIR = os.path.join("app", "build", "visual", "frames")


def parse_crop(text: str | None) -> tuple[int, int, int, int] | None:
    if not text:
        return None
    parts = [int(v) for v in re.split(r"[,\s]+", text.strip()) if v]
    if len(parts) != 4:
        raise SystemExit("--crop 要四个数：left,top,right,bottom")
    return (parts[0], parts[1], parts[2], parts[3])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", required=True, help="帧文件名前缀，如 drag_rim_")
    ap.add_argument("--out", required=True, help="输出的 .gif 路径")
    ap.add_argument("--crop", default=None, help="裁剪框 left,top,right,bottom（可选）")
    ap.add_argument("--width", type=int, default=640, help="输出宽度（等比缩放）")
    ap.add_argument("--fps", type=int, default=14, help="播放帧率")
    ap.add_argument("--colors", type=int, default=128, help="调色板色数（越少越小）")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(FRAMES_DIR, f"{args.prefix}*.png")))
    if not files:
        print(f"没有帧：{FRAMES_DIR}/{args.prefix}*.png", file=sys.stderr)
        return 1

    crop = parse_crop(args.crop)
    frames: list[Image.Image] = []
    for path in files:
        im = Image.open(path).convert("RGB")
        if crop:
            im = im.crop(crop)
        if im.width != args.width:
            h = max(1, round(im.height * args.width / im.width))
            im = im.resize((args.width, h), Image.LANCZOS)
        frames.append(im)

    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    duration_ms = int(round(1000 / args.fps))
    # `disposal=2`（每帧回到背景色再画下一帧）：不做的话，帧间只有局部变化时
    # 会留下上一帧的残影 —— GIF 的透明处理很容易踩这个。
    #
    # 调色板**全片共用**：逐帧各自量化会让颜色在播放中抖。
    #
    # ⚠️ **取样不能只用第一帧。** 入场动画的第一帧常常是空白 / 加载态，那张图算出来的
    # 调色板只有一两种颜色，后面每一帧都会被量化成同一片色 —— 于是 `optimize` 认为
    # 帧帧相同、把整段合并成**一帧**，GIF 变成一张静图（弹窗凝聚那条就这么栽过：
    # 22 帧出来只有 1 帧、1 KB）。取首 / 中 / 末三帧拼一张来算。
    sample = frames[0]
    if len(frames) > 2:
        picks = [frames[0], frames[len(frames) // 2], frames[-1]]
        montage = Image.new('RGB', (sample.width, sample.height * len(picks)))
        for i, f in enumerate(picks):
            montage.paste(f, (0, i * sample.height))
        sample = montage
    palette = sample.quantize(colors=args.colors, method=Image.MEDIANCUT)
    # **不做抖动。** 抖动会往平色区里撒噪点，而 GIF 的压缩全靠大片相同像素 ——
    # 一抖就把体积抬上去（实测同一段 680x194、44 帧：抖动 1567 KB，不抖 300 KB 级）。
    # 界面截图本来就是平色，抖动换不来观感，只换来体积。
    frames = [f.quantize(palette=palette, dither=Image.NONE) for f in frames]

    frames[0].save(
        args.out,
        save_all=True,
        append_images=frames[1:],
        duration=duration_ms,
        loop=0,
        optimize=True,
        disposal=2,
    )

    size_kb = os.path.getsize(args.out) / 1024
    print(
        f"{args.out}  {frames[0].width}x{frames[0].height}  "
        f"{len(frames)} 帧 @{args.fps}fps ≈ {len(frames)/args.fps:.1f}s  "
        f"{size_kb:.0f} KB"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
