#!/usr/bin/env python3
"""本地组装官网静态目录（`_site/`），用于预览与自查。

CI 里由 `.github/workflows/site.yml` 做同样的事；这个脚本只是把
「站点源 + 首页用到的图片」拼到一起，好让 `python -m http.server` 直接看。

用法（在仓库根目录）：
    python scripts/build_site.py
    python -m http.server 8087 --directory _site

要交付真站点（Cloudflare 控制台手动上传时用），把地址传进去，
清单里的下载直链才会写成绝对路径 —— App 读不了相对路径：

    python scripts/build_site.py --base https://daoban-shift.pages.dev

`_site/` 已 gitignore，可随时删掉重建。
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "site"
OUT = ROOT / "_site"
IMAGES = ROOT / "docs" / "images"

# 与 site.yml 保持同一份清单：只带首页真正引用的图。
PNGS = ["hero.png"]
GIFS = ["v0130-color.gif", "v0130-monthly.gif"]


def _copy(src: Path, dst: Path) -> None:
    if not src.is_file():
        sys.exit(f"缺文件：{src}")
    shutil.copy2(src, dst)


def main() -> int:
    parser = argparse.ArgumentParser(description="组装 _site/")
    parser.add_argument(
        "--base",
        default="",
        help="站点根地址（如 https://daoban-shift.pages.dev）。留空则写相对路径，只适合本地预览。",
    )
    args = parser.parse_args()
    base = args.base.rstrip("/")

    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "assets").mkdir(parents=True)
    (OUT / "download").mkdir(parents=True)

    _copy(SRC / "index.html", OUT / "index.html")
    _copy(SRC / "styles.css", OUT / "styles.css")

    for name in PNGS + sorted(p.name for p in IMAGES.glob("shot-*.png")):
        _copy(IMAGES / name, OUT / "assets" / name)
    for name in GIFS:
        _copy(IMAGES / name, OUT / "assets" / name)

    # 发布清单（先读 —— 下面挑哪个 APK 要参考它）
    manifest = json.loads((ROOT / "latest.json").read_text(encoding="utf-8"))
    stable = manifest.get("stable") if isinstance(manifest.get("stable"), dict) else None

    # dist/ 里挑 APK：优先按清单里的资产名找，找不到再退回最新的 ASCII 名那份。
    # dist/ 同时放着中文名与 ASCII 名两份，中文那份不能当 URL 用 ——
    # 清单里的 asset 是 ASCII 的那个名字。
    apk_dir = ROOT / "dist"
    apks = sorted(apk_dir.glob("*.apk")) if apk_dir.is_dir() else []
    wanted = (stable or {}).get("asset") or ""
    apk = next((p for p in apks if p.name == wanted), None)
    if apk is None:
        apk = max((p for p in apks if p.name.isascii()),
                  key=lambda p: p.stat().st_mtime, default=None)
    if apk is not None:
        # Cloudflare Pages 单文件上限 25 MiB。现在 22 MiB 出头，涨到顶会更安静地
        # 失败在 wrangler 那边 —— 在这里先喊出来，并指明该往哪搬。
        size = apk.stat().st_size
        if size > 25 * 1024 * 1024:
            sys.exit(
                f"APK {size} 字节超过 Cloudflare Pages 单文件 25 MiB 上限 —— "
                "改放 Cloudflare R2（免费 10GB 存储 + 零出口费），把下载地址换成 R2 的即可"
            )
        shutil.copy2(apk, OUT / "download" / apk.name)
        print(f"带上 APK：{apk.name}（{size / 1024 / 1024:.2f} MiB）")
    else:
        print("dist/ 里没有 APK —— 下载按钮会退回 GitHub")

    # 只把**本站确实有那份文件**的通道改成站内地址，其余保持原样（指向 GitHub）。
    # 否则清单里会挂一条 404。
    for channel in ("stable", "prerelease"):
        node = manifest.get(channel)
        if not isinstance(node, dict) or not node.get("version"):
            continue
        asset = node.get("asset") or f"DaoBanAssistantPro-v{node['version']}.apk"
        node["asset"] = asset
        if (OUT / "download" / asset).is_file():
            node["url"] = f"{base}/download/{asset}" if base else f"/download/{asset}"
        else:
            print(f"  跳过 {channel} {node['version']}：dist/ 里没有 {asset}，仍指向 GitHub")

    (OUT / "latest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    total = sum(p.stat().st_size for p in OUT.rglob("*") if p.is_file())
    print(f"已组装 {OUT}（{total / 1024 / 1024:.1f} MiB）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
