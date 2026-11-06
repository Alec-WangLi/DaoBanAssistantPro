#!/usr/bin/env bash
# 开工注入：把「现场状态 + 开工 SOP 提醒」打进每次新会话的开头。
# 由 .claude/settings.json 的 SessionStart hook 调用；stdout 会进上下文。
#
# 注意：这里只吐「现场 + 一句 SOP」，不重复吐 AGENTS.md 全文 ——
# AGENTS.md 由 Claude 自动加载（或按需读），重复注入只会把上下文撑爆，
# 重走当年 405KB 的老路。
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
echo "--- 当前版本（pubspec）---"
grep -m1 '^version:' app/pubspec.yaml 2>/dev/null || echo "(读不到 pubspec)"

echo ""
echo "===== 开工 SOP（照做，别跳）====="
echo "1) 读 AGENTS.md 的开工 SOP；"
echo "2) 按任务只读一个 topic（docs/decisions/ 对应文件）；"
echo "3) 报技能：这次用哪几个、为什么；"
echo "4) 动第一行代码前想清楚。"
