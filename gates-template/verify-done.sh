#!/usr/bin/env bash
# 提交门禁（模板版）：静态分析必绿 +（--full）测试必绿 + 写回软提醒。
# 用法：bash verify-done.sh [--full]
#
# ═══════════ 新项目只改下面这一段 ═══════════
ANALYZE_CMD="flutter analyze"      # 静态分析命令（简单命令，别带引号/管道）
TEST_CMD="flutter test"            # 测试命令
WORKDIR="app"                      # 在哪个子目录跑测试/分析；留空 = 项目根
CODE_DIRS="app/lib app/test app/android app/tool app/shaders"   # 算「改了代码」的 git 相对路径（空格分隔）
DOC_DIRS="AGENTS.md PRODUCT_SPEC.md BUILD.md README.md docs"     # 算「写了文档」的路径
# ═══════════ 改到这里为止 ═══════════
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [ -n "$WORKDIR" ]; then cd "$root/$WORKDIR"; fi

echo "===== 1/2 静态分析（必须无 issue）====="
if ! $ANALYZE_CMD; then
  echo "" >&2
  echo "❌ 静态分析没通过。修完再提交。" >&2
  exit 1
fi

if [ "${1:-}" = "--full" ]; then
  echo ""
  echo "===== 2/2 测试（全套，绿色才放行）====="
  if ! $TEST_CMD; then
    echo "" >&2
    echo "❌ 测试有红。修完再提交。" >&2
    exit 1
  fi
fi

# 写回检查：改了代码、没动任何文档 → 软提醒。
cd "$root"
code_changed=""
doc_changed=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -n "$(git status --porcelain -- $CODE_DIRS 2>/dev/null)" ] && code_changed=1
  [ -n "$(git status --porcelain -- $DOC_DIRS 2>/dev/null)" ] && doc_changed=1
fi

if [ -n "$code_changed" ] && [ -z "$doc_changed" ]; then
  echo ""
  echo "⚠️  这轮改了代码，但没看到任何文档记录。"
  echo "   新坑/设计变更/测试套路 → 写进项目的决策文档；如果确实不需要，说明一句为什么（此提醒不硬拦）。"
fi

echo ""
echo "✅ verify-done 通过。"
