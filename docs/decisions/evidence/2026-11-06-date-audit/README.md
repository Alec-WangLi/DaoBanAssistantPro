# 证据 · 2026-11-06 日期依赖用例清点

本目录是 `docs/decisions/date-time-in-tests.md` 的原始证据。有人质疑文档里那些数字（尤其「① 会红 23 条」）时，从这里往回查。

## 文件

| 文件 | 大小 | 是什么 |
|---|---|---|
| `mar1-2026-03-01-anchor.log` | 65,934 B / 522 行 | **原样搬运，未截断未重排版。** 把 `app/test/support/fixed_clock.dart` 的 `kAnchor` 临时改成 `2026-03-01` 之后跑全套的完整输出，尾部 `Failing tests:` 段就是「锚点形状族 8 条」的名单（短名单为前 4 条 + `... and 4 more`，8 条全名与温柔版描述见 `triage.md` 脚注①） |
| `p1-pin-failing.txt` | 642 B / 6 行 | 批次 1a/1b/1c 反向验证（HEAD 版表达式 + 敌意锚点 `2026-01-31`）那次全跑的输出尾部。短名单为前 4 条 + `... and 17 more`，完整 15 条的落点见 `triage.md` 第 2 节 |
| `triage.md` | 14,917 B / 143 行 | 逐条结账：三分类（① 会红 / ② 静默空转 / ③ 本来就自洽）怎么分、23 为什么可以相加、条数时间线 1228 → 1242 |

## 为什么 `p1-pin.log` 没有全搬

两次原始日志合计 **440 KB**（`p1-pin.log` 380,074 B / 3,087 行，`mar1.log` 65,934 B），超过仓库能接受的 300 KB 线。所以 `p1-pin.log` **只搬了 `Failing tests:` 那 6 行**（第 3082–3087 行），其余是 `flutter test` 的逐条进度输出，信息量只有那几行。

`mar1.log` 单独就 65,934 B、远在 300 KB 以下，而它是「8 条」这个数唯一的原始凭据，所以整份原样留在仓库里。

## 怎么复现全量日志

```bash
# 1. 改锚点（唯一需要动的地方，改完记得改回来；备份先 cp 到 work/tmp/）
#    app/test/support/fixed_clock.dart 的 kAnchor -> DateTime(2026, 3, 1)

# 2. 跑全套，整份输出落盘
cd app && flutter test 2>&1 | tee ../work/tmp/mar1.log

# 3. 看尾部
tail -12 ../work/tmp/mar1.log
```

批次 1a/1b/1c 的反向验证还要把测试文件换回 HEAD 版表达式（`git checkout` 拿到原文件后**只**补 `import` 与 `useFixedNow()`，断言一字不改），再按同样方式落盘。

## 日期

2026-11-06。对应提交：`c981ad1`（1a）、`045f3f9`（1b）、`92ab81a`（1c）、`6d649af`（六行月）、`16920df`（批次 2）、`6aa6e63`（批次 3）、`a8370de`（批次 4，条数落在 1242）。
