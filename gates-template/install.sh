#!/usr/bin/env bash
# 把门禁三件套装进一个目标项目。
# 用法：bash gates-template/install.sh /path/to/new-project
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="${1:-}"

if [ -z "$target" ]; then
  echo "用法：bash install.sh <目标项目目录>" >&2
  exit 1
fi
if [ ! -d "$target" ]; then
  echo "目标目录不存在：$target" >&2
  exit 1
fi

mkdir -p "$target/scripts" "$target/.claude"
cp "$here/onboard.sh" "$here/verify-done.sh" "$here/consolidate-memory.sh" "$target/scripts/"

if [ -f "$target/.claude/settings.json" ]; then
  echo "⚠️  $target/.claude/settings.json 已存在，不覆盖——请手动合并 hooks 段。"
else
  cp "$here/settings.json" "$target/.claude/settings.json"
fi

echo "✅ 已装进 $target"
echo ""
echo "下一步："
echo "  1) 改 $target/scripts/verify-done.sh 顶部的 CONFIG（ANALYZE_CMD / TEST_CMD / WORKDIR / CODE_DIRS / DOC_DIRS）；"
echo "  2) 改 $target/scripts/onboard.sh 的 VERSION_FILE；"
echo "  3) 重开 Claude Code 会话：开工会自动注入现场，git commit 会先跑门禁。"
