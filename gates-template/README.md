# 项目门禁三件套（模板）

给 Claude Code 项目加一层机器门禁，让「读 → 写回 → 验证 → 瘦身」不再靠 AI 自觉。
实装版在 shiftassistant 项目的 `scripts/` 下；这里是通用模板，装进新项目用。

## 四个文件

| 文件 | 作用 |
|---|---|
| `onboard.sh` | 开工注入现场（git log / 分支 / 未提交改动 / 版本）+ SOP 提醒 |
| `verify-done.sh` | 提交门禁：静态分析必绿 +（`--full`）测试必绿 + 写回软提醒 |
| `consolidate-memory.sh` | 瘦身检查：AGENTS.md 超阈值就提醒归档（只报告、不改文件） |
| `settings.json` | 三个 hook 的接线（SessionStart / `git commit` / `git tag`） |

## 装进新项目

```bash
bash gates-template/install.sh /path/to/new-project
```

装完改两处：
1. `verify-done.sh` 顶部的 CONFIG（分析命令 / 测试命令 / 工作子目录 / 代码目录 / 文档目录）；
2. `onboard.sh` 的版本号来源 `VERSION_FILE`。

然后重开 Claude Code 会话即生效。

## 设计原则（为什么这么设计）

- **analyze / test 是硬门禁**（不绿就 `exit 1` 拦 commit）；**写回是软提醒**（不硬拦，避免逼 AI 为过门禁硬凑废话）。要不要升级成硬拦，跑几轮后你定。
- **瘦身脚本只报告、不动文件** —— 自动改 AGENTS.md 容易改坏，归档由 AI 照报告做。
- **不挂 Stop hook** —— 它在每个回合结束都触发，只要有未提交改动就拦，会把「中途停下来问你一句」这种正常停顿也卡死；commit 门禁已经在你最需要的那一刻拦住。

## 特殊环境

如果你的项目有 vendored 工具链 / 特殊环境变量（像 Flutter 项目要设 `PUB_CACHE`、`TMP`），
参考 shiftassistant 的实装版 `scripts/verify-done.sh`，把那段环境准备抄进来即可。
