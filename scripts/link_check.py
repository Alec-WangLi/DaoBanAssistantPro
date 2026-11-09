#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""断链检查：扫 docs/ 下所有 .md（外加 AGENTS.md / README.md / BUILD.md）里的相对链接与图片。

只读，不修改任何文件。相对路径按「链接所在文件所在目录」解析；带 # 锚点的只查文件本身。
"""
import io
import os
import re
import sys

def find_root(start):
    """从脚本所在目录往上找仓库根（认 docs/ 与 AGENTS.md），不受 cwd 与层级变动影响。"""
    cur = os.path.abspath(start)
    for _ in range(6):
        if os.path.isdir(os.path.join(cur, 'docs')) and os.path.isfile(
                os.path.join(cur, 'AGENTS.md')):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


ROOT = find_root(os.path.dirname(os.path.abspath(__file__)))
SCAN_FILES = []
for dirpath, _dirnames, filenames in os.walk(os.path.join(ROOT, 'docs')):
    for fn in filenames:
        if fn.endswith('.md'):
            SCAN_FILES.append(os.path.join(dirpath, fn))
for extra in ('AGENTS.md', 'README.md', 'BUILD.md'):
    p = os.path.join(ROOT, extra)
    if os.path.exists(p):
        SCAN_FILES.append(p)

# [text](target) / ![alt](target)；target 允许带 <...> 与 "title"
LINK = re.compile(r'!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')

total = 0
external = 0
img_total = 0
img_broken = []
link_broken = []
skipped_in_code = []
FENCE = re.compile(r'```.*?```', re.S)
CODE = re.compile(r'`[^`\n]*`')
for path in sorted(SCAN_FILES):
    with io.open(path, encoding='utf-8') as fh:
        text = fh.read()
    # 反引号里的 `[文字](链接)` 是举例说明某个 markdown 写法，不是链接；围栏代码块同理
    raw_hits = LINK.findall(text)
    masked = FENCE.sub(' ', text)
    masked = CODE.sub(' ', masked)
    kept = len(LINK.findall(masked))
    if kept != len(raw_hits):
        skipped_in_code.append((os.path.relpath(path, ROOT),
                                len(raw_hits) - kept))
    text = masked
    base = os.path.dirname(path)
    for m in LINK.finditer(text):
        target = m.group(1)
        is_img = m.group(0).startswith('![')
        total += 1
        if target.startswith(('http://', 'https://', 'mailto:', '#', 'data:')):
            external += 1
            continue
        rel = target.split('#', 1)[0]
        if not rel:
            continue
        if is_img:
            img_total += 1
        resolved = os.path.normpath(os.path.join(base, rel))
        if os.path.exists(resolved):
            continue
        # 「路径:行号」是引用写法，不是文件链接 —— 去掉尾部的 :123 再试一次
        stripped = re.sub(r':\d+$', '', rel)
        if stripped != rel and os.path.exists(os.path.normpath(os.path.join(base, stripped))):
            continue
        (img_broken if is_img else link_broken).append(
            (os.path.relpath(path, ROOT), target))

print('扫描文件 %d 个；链接总数 %d（外链/锚点 %d）' % (len(SCAN_FILES), total, external))
for src, n in skipped_in_code:
    print('  [代码内举例，已跳过 %d 条] %s' % (n, src))
print('图片链接 %d 条，断 %d 条' % (img_total, len(img_broken)))
for src, target in img_broken:
    print('  [图] %s -> %s' % (src, target))
print('其它本地链接断 %d 条' % len(link_broken))
for src, target in link_broken:
    print('  %s -> %s' % (src, target))
sys.exit(1 if (img_broken or link_broken) else 0)
