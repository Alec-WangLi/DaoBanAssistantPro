#!/usr/bin/env bash
# 开工注入（模板版）：现场状态 + 开工 SOP 提醒。
# 由 .claude/settings.json 的 SessionStart hook 调用；stdout 会进上下文。
#
# ═══════════ 新项目只改这一行 ═══════════
VERSION_FILE="app/pubspec.yaml"   # 版本号来源文件；留空 = 不读版本
# ═══════════ 改到这里为止 ═══════════
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

echo "===== 开工现场（自动注入）====="
echo "--- 最近 8 条提交 ---"
git --no-pager log --oneline -8 2>/dev/null || echo "(无 git 历史)"
echo "--- 当前分支 ---"
git branch --show-current 2>/dev/null || echo "(不在 git 仓库)"
echo "--- 未提交改动 ---"
git status --short 2>/dev/null || true
echo "--- 当前版本 ---"
if [ -n "$VERSION_FILE" ] && [ -f "$VERSION_FILE" ]; then
  grep -m1 'version' "$VERSION_FILE" 2>/dev/null || echo "(读不到版本)"
else
  echo "(未配置版本来源)"
fi

echo ""
echo "===== 开工 SOP（照做，别跳）====="
echo "1) 读 AGENTS.md 的开工 SOP；"
echo "2) 按任务只读一个 topic 文档；"
echo "3) 报技能：这次用哪几个、为什么；"
echo "4) 动第一行代码前想清楚。"
