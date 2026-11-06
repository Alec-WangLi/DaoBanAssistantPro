#!/usr/bin/env bash
# 收尾/提交门禁：flutter analyze 必绿（--full 再加 flutter test 全套），
# 改了代码却没落文档记录时给提醒。
#
# 用法：
#   bash scripts/verify-done.sh          # 轻量：analyze + 写回提醒（Stop hook 用）
#   bash scripts/verify-done.sh --full   # 全量：analyze + test + 写回提醒（commit/tag 前用）
#
# 设计原则：analyze/test 是硬门禁（不绿就 exit 1 拦住），
# 写回检查是软提醒（只喊话、不硬拦）—— 硬拦会逼 AI 为过门禁硬凑废话，
# 是否升级成硬拦，跑几轮后你拍板。
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# 定位 flutter：优先本地 toolchain（版本钉死 3.47.2），其次 PATH。
if [ -x "$root/toolchain/flutter/bin/flutter" ]; then
  FLUTTER="$root/toolchain/flutter/bin/flutter"
  export PATH="$root/toolchain/flutter/bin:$PATH"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER="flutter"
else
  echo "❌ 找不到 flutter（toolchain/ 或 PATH 都没有）。装好 Flutter 再跑。" >&2
  exit 1
fi

# 与 tools/flutter-test.sh 同一套环境：PUB_CACHE 落在库内、TMP 落在 work/tmp。
if [ -d "$root/toolchain/pub-cache" ]; then
  export PUB_CACHE="$root/toolchain/pub-cache"
fi
mkdir -p "$root/work/tmp"
export TMP="$root/work/tmp" TEMP="$root/work/tmp"

# 关掉 flutter 遥测：受限沙箱里 AppData\Roaming 不可写，遥测日志删不动会崩
# （与 BUILD.md「七条最贵的坑」同源）；门禁脚本本就不该发遥测。
export FLUTTER_SUPPRESS_ANALYTICS=true

cd "$root/app"

echo "===== 1/2 flutter analyze（必须 No issues found）====="
if ! "$FLUTTER" analyze; then
  echo "" >&2
  echo "❌ flutter analyze 没通过。修掉上面的 issues 再提交。" >&2
  exit 1
fi

if [ "${1:-}" = "--full" ]; then
  echo ""
  echo "===== 2/2 flutter test（全套，绿色才放行）====="
  if ! "$FLUTTER" test; then
    echo "" >&2
    echo "❌ flutter test 有红。修完再提交。" >&2
    exit 1
  fi
fi

# 写回检查：改了代码、没动任何文档 → 软提醒。
cd "$root"
code_changed=""
doc_changed=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -n "$(git status --porcelain -- app/lib app/test app/android app/tool app/shaders 2>/dev/null)" ] && code_changed=1
  [ -n "$(git status --porcelain -- AGENTS.md PRODUCT_SPEC.md BUILD.md README.md docs 2>/dev/null)" ] && doc_changed=1
fi

if [ -n "$code_changed" ] && [ -z "$doc_changed" ]; then
  echo ""
  echo "⚠️  这轮改了代码，但没看到任何文档记录。"
  echo "   新坑 → docs/decisions/<主题>.md；设计变更 → docs/decisions/ui-rules.md；版本/更新 → docs/changelog/。"
  echo "   如果这次确实不需要记录，说明一句为什么即可（此提醒不硬拦）。"
fi

if [ "${1:-}" = "--full" ]; then
  echo ""
  echo "✅ verify-done 通过（analyze 绿、test 绿）。"
else
  echo ""
  echo "✅ verify-done 通过（analyze 绿）。"
fi
