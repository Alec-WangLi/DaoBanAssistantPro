#!/usr/bin/env bash
# 瘦身检查：AGENTS.md 体积预警 + 找出最该归档的段落。
# 只报告、不动文件 —— 自动改 AGENTS.md 容易改坏，归档由 AI 照这份报告做。
# 由 .claude/settings.json 的 PreToolUse(git tag*) 在每次打版本标签时提醒一次。
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

AGENTS="AGENTS.md"
WARN_KB=32
HARD_KB=35

if [ ! -f "$AGENTS" ]; then
  echo "没找到 AGENTS.md，跳过瘦身检查。"
  exit 0
fi

bytes=$(wc -c < "$AGENTS")
kb=$((bytes / 1024))

echo "===== AGENTS.md 体积 ====="
echo "当前 ${kb} KB（${bytes} 字节）；预算 ≤${HARD_KB} KB，预警线 ${WARN_KB} KB。"

if [ "$kb" -lt "$WARN_KB" ]; then
  echo "✅ 健康。"
  exit 0
fi

if [ "$kb" -ge "$HARD_KB" ]; then
  echo "🚨 已经超过 ${HARD_KB} KB 预算 —— 当年 405KB 就是这么来的，尽快归档。"
else
  echo "⚠️  逼近预算，该归档了。"
fi

echo ""
echo "体积最大的段落（归档候选，按从大到小）："
echo "  把陈年细节/长坑搬进 docs/decisions/<主题>.md，AGENTS.md 只留一行指针。"
echo ""
awk '
  /^## / { if (title != "") print len, title; title = substr($0,4); len = 0; next }
  { len += length($0) + 1 }
  END { if (title != "") print len, title }
' "$AGENTS" | sort -rn | head -5 | while read -r len title; do
  printf "  %6d 字符   %s\n" "$len" "$title"
done

echo ""
echo "（本脚本只预警、不拦截，退出码恒为 0。）"
exit 0
