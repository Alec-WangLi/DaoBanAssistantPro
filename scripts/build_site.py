#!/usr/bin/env python3
"""组装官网静态目录（`_site/`），用于部署与本地预览。

用法（在仓库根目录）：

    # 本地预览：清单里写相对地址，配 python -m http.server 看
    python scripts/build_site.py

    # 真站点：写绝对地址（App 读不了相对路径）
    python scripts/build_site.py --base https://daoban-shift.pages.dev

    # 发版时：指定本次写哪个通道，另一通道取 origin/main 上的权威值
    python scripts/build_site.py --channel prerelease --base https://...

**两个通道的 APK 都会带**（只要 `dist/` 里有对应文件）。只带正式版是不够的：
测试版发出去时，清单里 `prerelease` 那一版在站点上找不到文件，那条地址就会
退回 GitHub —— 国内用户又得开代理，正是这套东西要解决的问题。

`_site/` 已 gitignore，可随时删掉重建。
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "site"
OUT = ROOT / "_site"
IMAGES = ROOT / "docs" / "images"

# 与 index.html 保持一致：只带首页真正引用的图。
PNGS = ["hero.png"]
GIFS = ["v0130-color.gif", "v0130-monthly.gif"]

# Cloudflare Pages 单文件上限。逼近时会安静地失败在 wrangler 那边，这里先喊。
PAGE_FILE_LIMIT = 25 * 1024 * 1024

_VERSION_RE = re.compile(r"v(\d+\.\d+\.\d+)")


def _copy(src: Path, dst: Path) -> None:
    if not src.is_file():
        sys.exit(f"缺文件：{src}")
    shutil.copy2(src, dst)


def _load_manifest(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _origin_main_manifest(local: dict) -> dict:
    """main 上的清单才是权威 —— beta 那份的 stable 可能停在旧值。

    只用本地已有的 ref（release.ps1 在 8b 步已经 fetch 过）；取不到就退回本地那份。
    """
    try:
        raw = subprocess.run(
            ["git", "show", "origin/main:latest.json"],
            cwd=ROOT, capture_output=True, text=True,
            encoding="utf-8", errors="replace", check=True,
        ).stdout
        return json.loads(raw)
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        print("  取不到 origin/main:latest.json，底稿用当前工作区那份")
        return dict(local)


def _dist_apks() -> dict[str, Path]:
    """版本号 → dist/ 里的 APK。同一版本有中英两份时优先 ASCII 名，
    中文文件名进 URL 会被转义得很丑，也不便排查。"""
    apk_dir = ROOT / "dist"
    if not apk_dir.is_dir():
        return {}
    found: dict[str, Path] = {}
    # False 排在 True 前面，setdefault 于是留下 ASCII 那份
    for p in sorted(apk_dir.glob("*.apk"), key=lambda q: (not q.name.isascii(), q.name)):
        m = _VERSION_RE.search(p.name)
        if m:
            found.setdefault(m.group(1), p)
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description="组装 _site/")
    parser.add_argument(
        "--base", default="",
        help="站点根地址（如 https://daoban-shift.pages.dev）。留空写相对路径，只适合本地预览。",
    )
    parser.add_argument(
        "--channel", choices=["stable", "prerelease"], default=None,
        help="本次发布写哪个通道。给了就用 origin/main 的清单当底稿，只覆盖这个通道。",
    )
    args = parser.parse_args()
    base = args.base.rstrip("/")

    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "assets").mkdir(parents=True)
    (OUT / "download").mkdir(parents=True)

    # og:image 必须是绝对地址，分享预览才出图；域名只在 index.html 里留个占位，
    # 组装时填 —— 免得又出现一处要人记着同步的域名。
    html = (SRC / "index.html").read_text(encoding="utf-8")
    (OUT / "index.html").write_text(
        html.replace("__SITE_BASE__", base), encoding="utf-8"
    )
    _copy(SRC / "styles.css", OUT / "styles.css")

    for name in PNGS + sorted(p.name for p in IMAGES.glob("shot-*.png")):
        _copy(IMAGES / name, OUT / "assets" / name)
    for name in GIFS:
        _copy(IMAGES / name, OUT / "assets" / name)

    local = _load_manifest(ROOT / "latest.json")
    if args.channel:
        manifest = _origin_main_manifest(local)
        # 本次发布那个通道以工作区（刚由 release.ps1 写好）为准
        if isinstance(local.get(args.channel), dict):
            manifest[args.channel] = local[args.channel]
    else:
        manifest = local

    apks = _dist_apks()

    # 把清单里点到名的版本，dist/ 有就带上。两个通道都带。
    copied: set[str] = set()
    for channel in ("stable", "prerelease"):
        node = manifest.get(channel)
        if not isinstance(node, dict) or not node.get("version"):
            continue
        version = node["version"]
        apk = apks.get(version)
        if apk is None:
            print(f"  跳过 {channel} {version}：dist/ 里没有这一版，仍指向 GitHub")
            continue
        size = apk.stat().st_size
        if size > PAGE_FILE_LIMIT:
            sys.exit(
                f"{apk.name} 有 {size / 1024 / 1024:.2f} MiB，超过 Cloudflare Pages "
                "单文件 25 MiB 上限 —— 改放 Cloudflare R2（免费 10GB 存储 + 零出口费）"
            )
        # 落盘用**清单里的 asset 名**，不是 dist/ 里的文件名：release.ps1 在 dist/
        # 存的是中文名「倒班助手Pro-vX.Y.Z.apk」，照搬会让下面「文件是否存在」
        # 的判断对不上，那条 URL 就退回 GitHub 了 —— 正是要避免的事。
        dest = node.get("asset") or f"DaoBanAssistantPro-v{version}.apk"
        shutil.copy2(apk, OUT / "download" / dest)
        copied.add(dest)
        print(f"  带上 {channel} {version}：{dest}（{size / 1024 / 1024:.2f} MiB）")

    # 站点上真有的文件才改写地址，否则保留原样（GitHub）。
    for channel in ("stable", "prerelease"):
        node = manifest.get(channel)
        if not isinstance(node, dict) or not node.get("version"):
            continue
        asset = node.get("asset") or f"DaoBanAssistantPro-v{node['version']}.apk"
        node["asset"] = asset
        if (OUT / "download" / asset).is_file():
            node["url"] = f"{base}/download/{asset}" if base else f"/download/{asset}"

    if not copied:
        print("dist/ 里一版 APK 都没有 —— 下载按钮会退回 GitHub")

    (OUT / "latest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    total = sum(p.stat().st_size for p in OUT.rglob("*") if p.is_file())
    print(f"已组装 {OUT}（{total / 1024 / 1024:.1f} MiB）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
