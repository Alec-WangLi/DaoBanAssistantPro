# 发布与分发 · 决策与坑

> 从 `AGENTS.md` 拆出（v0.14.2）。**只在要动发布链、要查某次事故时读**；
> 日常发版照 `AGENTS.md`「分支与发布」「构建 / 测试 / 发布」两节做就够了。

## 1. 分支纪律（2026-09-21 用户定，从 0.9.4 起照办）

- 测试版（末位 `Z ≠ 0`）在 `beta` 分支上做、提交、发布；tag 打在 beta 的提交上没问题
  —— 预发布本来就不占 Releases 页的 Latest。
- `main` 只在发正式版（`Z = 0`）时收一次合并，用 `--no-ff` 留一条合并记录；正式版的 tag 打在 main 上。
- 历史注记：0.9.1 / 0.9.2 / 0.9.3 三个测试版是直接在 main 上发的（那时还没定这条规矩）。

## 2. `latest.json`：为什么必须只改一个字段

App 的主更新通道读 `raw.githubusercontent.com/<owner>/<repo>/main/latest.json`。`release.ps1` 第 7 步
把它提交到**当前分支**，第 8b 步再同步回 main。

**8b 步曾经是 `git checkout <分支> -- latest.json`** —— 把当前分支的整份清单搬到 main。**错的**，
2026-10-13 改成「切到 main 后读 main 自己那份、只写本次发布那个通道的字段」。

根因：正式版在 main 发、测试版在 beta 发，beta 那份的 `stable` 永远停在旧值 —— 每在 beta 发一次
测试版就把 main 打回一次（v0.11.0 被打回 0.10.0）。完全静默，只能靠 curl 发现。

**判据**：Release 标得对不对看 Releases 页，`latest.json` 对不对只能 curl 那一份，两者会各自独立地错。

### 两次挂在这里的复盘（v0.9.4 / v0.9.5）

两次发布都挂在 8b 这一行、两次都是手动补的 main。根因既不是锁文件也不是网络：

脚本顶部 `$ErrorActionPreference = 'Stop'` 下，`git checkout … 2>&1 | Out-Null` 会把 git 写在
**stderr** 上的常规提示（「Switched to branch 'main'」）包成 `NativeCommandError` **抛出来** ——
git 明明成功了也照抛，所以只要分支切成功就必挂。

2026-09-23 实测（PowerShell 5.1）：带 `2>&1` 必抛、不带不抛、`2>$null` 也抛。修法是那一段临时放宽成
`Continue`（成败仍看本来就逐个查的 `$LASTEXITCODE`），`finally` 里还原。

**`git` / `gh` 这类原生命令的 stderr 上写的都是常规输出，别用 `2>&1` 去接。** 第 7 步（发布验证）
也中过同一条；那里还多一层：`ConvertFrom-Json` 更不该吃 stderr —— gh 真失败时那串错误文本会被喂进
JSON 解析，报出的是「解析失败」而不是「gh 失败」。

当时看到的两个 0 字节残留锁（`.git/AUTO_MERGE.lock` / `.git/packed-refs.lock`）是脚本中途抛异常留下的
**症状**，不是病因。

**手动补 main 之前**先确认没有 git.exe 在跑，并删掉这两个残留锁，否则会报
「Another git process seems to be running」。

## 3. 签名：为什么「自动回退 debug」很危险

release 用独立 keystore `app/android/keystore/release.jks`，口令在 `app/android/key.properties`
（storeFile / storePassword / keyAlias / keyPassword），二者均 gitignore、**务必本地备份**
（丢了无法再发可覆盖升级的包）。`key.properties` 缺失时 `build.gradle.kts` 自动回退 debug 证书便于本机调试。

**那条「自动回退」的代价是「静默」—— 2026-10-13 真踩过一次。** v0.11.16 的 APK 是在一个 **git worktree**
里构建的，而 worktree 是一次干净 checkout、**既没有 key.properties 也没有 release.jks**，于是它被
**debug 证书**签了名。包照常发了出去，版本号 / 资产 / `latest.json` / 清单**全对**，用户一装就报
`Couldn't install (-7)` — **Conflicting app signatures**，只能卸载重装。

**一句话：要发的 APK 只能在主 checkout 里构建**（`dist/`、`tools/`、`toolchain/` 也都只在那儿）。

现在 `release.ps1` 的一致性校验里多一条**签名校验**：① `app/android/key.properties` 必须存在；
② 用 `apksigner verify --print-certs` 取 APK 的证书 SHA-256，与 `keytool -list -v -keystore release.jks`
那一枚**逐位比**（不拿 DN 比 —— DN 是人填的、可以重名；实测 release 那枚是 `265d09b2…ce893`）。

⚠️ **2026-11-05 起默认硬拦（v0.12.10）**：工具不全 / 吐不出摘要 → 默认 `throw`，要跳过必须显式
`-SkipSignCheck`；摘要对不上**任何情况都不放行**（无口子）。这一节还搬出了 `if (-not $SkipVerify)` ——
以前加 `-SkipVerify` 会把签名校验整段静默关掉。**别再把这条当「保险」**：v0.12.9 那次 418B 占位稿
就是被「只是保险、不必需」的旧说法放过去的。

两条路径都验过：拿 worktree 里那份 debug 签名的 APK 当反例，脚本退出码 1 并把两枚摘要一起打出来。

## 4. 检查更新：三条通道为什么这样排

`UpdateChecker` 无鉴权，三条通道依次回退：**官网清单**（`siteBase/latest.json`）→ 仓库根 `latest.json`
→ GitHub API `/releases`。

- 官网排第一，是因为它才是国内用户的快通道；以前 GitHub 那条先试，国内往往要等满 8 秒超时才回退。
- **API 不当主通道**：未认证限 60 次/小时/IP，共享出口很容易耗尽（实测常年 403），拿它优先等于
  大部分时间都在走回退。
- 两条在不同域名上，只被墙了一个的网络也兜得住。
- 按语义版本自行计算「最新正式版 + 最新测试版」双通道展示；`downloadApk` 经 `browser_download_url` 下载安装。
- 连不上时的提示直说「国内需要开代理或加速器」（`showUpdateFailedDialog`，走弹窗不走 2 秒的 snack）。

## 5. 官网（Cloudflare Pages）

`site/` 是一页静态官网，和 APK 放在同一个域：`https://daoban-shift.pages.dev`（项目名 `daoban-shift`）。
**APK 不进仓库**（`dist/` 本来就 gitignore），部署时由 `scripts/build_site.py` 从 `dist/` 取一份放进 `_site/download/`。

**部署走本机，不走 CI**：`release.ps1` 第 9 步跑 `build_site.py --base <siteBase> --channel <stable|prerelease>`
+ `npx wrangler pages deploy _site`。凭据是 `npx wrangler login` 一次之后的 OAuth token，不需要 GitHub secrets；
换机器发版要重新 login。

### 坑一：`APPDATA` 被重定向，wrangler 找不到登录态

`build-env.ps1` 把 `APPDATA` 重定向到 `toolchain\`，而 wrangler 的登录态在真实的
`%APPDATA%\xdg.config\.wrangler`。不指回去就报 "In a non-interactive environment, it's necessary to set a
CLOUDFLARE_API_TOKEN" 直接失败 —— 2026-11-10 发 v0.13.1 时踩到：发布本身成功，站点没更新。
`release.ps1` 第 9 步现在临时把 `APPDATA` 指回真实目录，与 gh 的 `GH_CONFIG_DIR` 是同一类修法。

### 坑二：两个通道的 APK 都要镜像

清单里点到名的版本，`dist/` 有就都放进 `_site/download/`（正式版 + 测试版，约 46MB）。只带正式版是不够的
—— 发测试版时 `prerelease` 那条会因为没有文件而退回 GitHub，国内用户又得开代理，正是这套东西要解决的问题。
`--channel` 决定哪一端以工作区刚写好的清单为准，另一端取 `origin/main` 的权威值。落盘用清单里的 `asset`
名（ASCII），不是 `dist/` 里的中文文件名。

### 坑三：Cloudflare 2026 年已把新建 Pages 项目并进 Workers

`npx wrangler pages project create` 现在建出来的是 **Worker**（域名 `*.workers.dev`），`wrangler pages deploy`
会报 "project does not exist"。本项目那个经典 Pages 项目是用 API 建的（`POST /accounts/<id>/pages/projects`）。
**别用 `pages project create` 重建**，会又得到一个 Worker。

### 坑四：单文件 25 MiB 上限

Pages 单文件上限 25 MiB，当前 APK 约 23 MiB —— 再涨约 2 MiB 就超。`build_site.py` 里有
`25 * 1024 * 1024` 的硬闸，超了直接退出并提示改放 Cloudflare R2（免费 10GB 存储 + 零出口费）。

### 页面本身

纯静态 HTML/CSS，不引任何框架、外部字体或 CDN（国内打开要快，也不给别人当依赖）。深色 / 浅色两套跟随系统，
**只换 `:root` 里的语义变量**，版式、字号、间距一个不动；新加颜色必须走变量，写死 `rgba()` 就会在另一套主题里露馅。
动效只有一个 `IntersectionObserver` 做一次性入场 + 首屏三台机器的轻微视差，两者都尊重 `prefers-reduced-motion`。

改版时先 `python scripts/build_site.py` 再 `.claude/launch.json` 里的 `site` 预览，逐段截图核对。
**`build_site.py` 的 `PNGS` / `SHOTS` 列表必须与 `index.html` 同步** —— 少一张图就是线上裂图，多一张就是白传。

> 工装里的截图要在页面 `visible` 之后才有内容：`.reveal` 元素初始 `opacity: 0`，靠 `IntersectionObserver`
> 点亮。后台标签页里观察器不触发，截图会是一张空白页 —— 临时把 `.reveal` 的 opacity 设成 1 再截。

免备案的代价是走国际线路：比 GitHub 快得多，但不是国内 CDN 那种秒开。要秒开只能备案 + 国内 CDN（B 档，
约 ¥200/年，审批 2~3 周）。

## 6. main 上的「同步 beta」提交：保留，不清理（2026-11-28 体检定）

**现象**：`origin/main` 比 `origin/beta` 多出约 35 条提交，其中约 30 条是 `chore(release): 更新发布清单至 vX.Y.Z（同步 beta）`。
`git log origin/main -- latest.json` 有 216 条，beta 有 215 条。有人想「清理」这段历史。

**结论：保留现状。** 这些提交不是多余的，有两个读者依赖 main 上那份文件：

1. **兜底更新通道**：App 的第二通道写死读 `raw.githubusercontent.com/…/main/latest.json`
   （`app/lib/core/update_checker.dart`，`repoRaw('latest.json')`）。已经装在用户手机上的旧版本只认这个地址，
   它停更，这些用户就收不到新版通知。地址写在已发出的 APK 里，改不了。
2. **官网底稿**：`scripts/build_site.py` 生成官网 `latest.json` 时，取 `origin/main:latest.json` 作底稿。

**为什么不改成别的地方读**：要换地址就得先发一个新版本，而旧版本仍然读 main，所以 main 上的文件无论如何都要保留更新。
唯一能真正消掉这串提交的办法是让 App 不再依赖 main，那是「先发新版、等旧版基本淘汰」之后才能做的排期事项，
不在这次清理的范围内。

**代价**：只是历史里多了这些提交，`git log` 比较吵；功能与发布流程都不受影响。合并 `main` 时这些提交的内容与 beta 等价，
不会产生冲突。

**GIF 瘦身不做（同日定）**：仓库体积主要在历史里的 blob，把 `docs/images/*.gif` 从 HEAD 移走，`.git` 一个字节都不会少；
只有改写历史（force-push 到受保护分支）才能瘦身，代价不值。另外 GIF 被 README、官网、各版本更新日志与 `scripts/make_gif.py`
引用，直接删会在线上留下断图。

**什么时候重新评估**：当 App 的兜底通道已经不再读 main（例如某个版本起改读别处），且旧版本已基本淘汰，
这一节就可以推翻重写。
