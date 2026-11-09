#!/usr/bin/env python3
"""本地组装官网静态目录（`_site/`），用于预览与自查。

CI 里由 `.github/workflows/site.yml` 做同样的事；这个脚本只是把
「站点源 + 首页用到的图片」拼到一起，好让 `python -m http.server` 直接看。

用法（在仓库根目录）：
    python scripts/build_site.py
    python -m http.server 8087 --directory _site

`_site/` 已 gitignore，可随时删掉重建。
"""

from __future__ import annotations

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

    # 发布清单：本地预览把地址改成相对路径，浏览器与 App 都读得懂。
    manifest = json.loads((ROOT / "latest.json").read_text(encoding="utf-8"))
    for channel in ("stable", "prerelease"):
        node = manifest.get(channel)
        if not isinstance(node, dict):
            continue
        asset = node.get("asset") or f"DaoBanAssistantPro-v{node.get('version')}.apk"
        node["asset"] = asset
        node["url"] = f"/download/{asset}"

    # dist/ 里有 APK 就带上，方便点按钮验证下载链路（取最新产出的那份）。
    apk_dir = ROOT / "dist"
    apk = max(apk_dir.glob("*.apk"), key=lambda p: p.stat().st_mtime, default=None) \
        if apk_dir.is_dir() else None
    if apk is not None:
        shutil.copy2(apk, OUT / "download" / apk.name)
        print(f"带上 APK：{apk.name}")

    (OUT / "latest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    total = sum(p.stat().st_size for p in OUT.rglob("*") if p.is_file())
    print(f"已组装 {OUT}（{total / 1024 / 1024:.1f} MiB）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
