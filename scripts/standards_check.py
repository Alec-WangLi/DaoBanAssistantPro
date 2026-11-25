#!/usr/bin/env python3
"""规范层自检：docs/standards/ 里写过的东西，必须真的存在。

守两件事（E7 的剥壳纪律照样用：只扫正文行，不扫围栏代码块）：

1. **路径存在**：三份规范文件里凡是用反引号包起来的仓库路径（`test/x_test.dart`、
   `app/lib/y.dart`、`scripts/z.py`），都要真的在盘上。规划中的路径要写成 `待补：` 前缀或
   放在围栏代码块里 —— 围栏里的示例命令不算承诺。
2. **矩阵一致**：README 的守门矩阵必须一条不少地覆盖 design-principles 的 D 编号与
   dev-standards 的 E 编号（矩阵是台账，条目是事实，两边对不上就是漂移）。

退出码 0 = 规范层与自己一致；1 = 有断裂处，逐条打印。
对应规范：README §5 维护纪律第 6 条。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STD = ROOT / "docs" / "standards"
FILES = ["README.md", "design-principles.md", "dev-standards.md"]

# 反引号里的候选路径：至少含一个 "/"，以已知后缀收尾。允许 `:12` / `:12-18` 行号尾巴。
INLINE = re.compile(r"`([^`\n]+)`")
PATHISH = re.compile(
    r"^((?:app/)?(?:lib|test|tool|scripts|docs|shaders|android|ios|tools|gates-template"
    r"|core|features|domain|data|state)[/\w.\-]+"
    r"\.(?:dart|py|sh|ps1|md|json|yaml|yml|kts|gradle|frag|vert|plist))(?::[\d\-–—]+)?$"
)
FENCE = re.compile(r"^\s*(```|~~~)")


def strip_fences(text: str) -> str:
    out, inside = [], False
    for line in text.splitlines():
        if FENCE.match(line):
            inside = not inside
            continue
        if not inside:
            out.append(line)
    return "\n".join(out)


def resolve(p: str) -> bool:
    for base in (ROOT, ROOT / "app", ROOT / "app" / "lib", ROOT / "app" / "test", ROOT / "app" / "tool"):
        if (base / p).exists():
            return True
    return False


def check_paths() -> list[str]:
    bad: list[str] = []
    for name in FILES:
        text = strip_fences((STD / name).read_text(encoding="utf-8"))
        for i, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("|") and "待补" in line:
                continue
            for span in INLINE.findall(line):
                for candidate in (span, span.split()[0]):
                    m = PATHISH.match(candidate.strip())
                    if not m:
                        continue
                    p = m.group(1)
                    if not resolve(p):
                        bad.append(f"{name}:{i} 指向不存在的路径 {p}")
                    break
    return bad


def ids(text: str) -> set[str]:
    return set(re.findall(r"\b([DE])(\d{1,2})\b", text))


def check_matrix() -> list[str]:
    readme = (STD / "README.md").read_text(encoding="utf-8")
    matrix = re.findall(r"^\|\s*([DE]\d{1,2})\s*\|", readme, re.M)
    in_matrix = set(matrix)
    declared: set[str] = set()
    for name, tag in (("design-principles.md", "D"), ("dev-standards.md", "E")):
        body = (STD / name).read_text(encoding="utf-8")
        declared |= {f"{tag}{n}" for tag in [tag] for n in re.findall(rf"^### {tag}(\d{{1,2}})\.", body, re.M)}
    problems: list[str] = []
    for miss in sorted(declared - in_matrix):
        problems.append(f"条目 {miss} 在正文里有，但 README §4 矩阵没有它")
    for extra in sorted(in_matrix - declared):
        problems.append(f"矩阵里的 {extra} 在正文里找不到 ### 条目")
    dupes = {x for x in matrix if matrix.count(x) > 1}
    for d in sorted(dupes):
        problems.append(f"矩阵里 {d} 出现了 {matrix.count(d)} 次")
    return problems


def main() -> int:
    problems = check_paths() + check_matrix()
    size_kb = sum((STD / f).stat().st_size for f in FILES) / 1024
    print(f"规范层 {len(FILES)} 份，合计 {size_kb:.1f} KB（红线 56 KB）")
    if size_kb > 56:
        problems.append(f"体积 {size_kb:.1f} KB 超红线，把细节搬去 docs/decisions/")
    if problems:
        print(f"\n断链/不一致 {len(problems)} 处：")
        for p in problems:
            print("  " + p)
        return 1
    print("路径全部存在，矩阵与条目一一对应。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
