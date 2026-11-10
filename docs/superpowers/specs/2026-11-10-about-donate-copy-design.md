# 「关于」页 + 打赏（支付宝 / 微信）+ 全量文案审校（设计）

- 日期：2026-11-10
- 起因：用户 v0.13.1 大量测试后提的三条需求：
  1. 官网与国内直连已上线，App 里还没有对应界面；加「关于」，介绍作者、官网、开源仓库。
  2. 加支付宝 / 微信打赏，默认 5 / 10 / 20 元与自定义，一键跳到付款。
  3. 全量检查 App 内文案，改掉过时与别扭的表达。
- 用户拍板（2026-11-10）：
  - 收款码由用户提供两张实际图片（`app/assets/donate/alipay.png`、`wechat.png`）；
  - 作者署名 `Alec Wang`，反馈渠道走 GitHub Issues，不公开邮箱；
  - 支付宝一键唤起收款页，微信展示二维码扫码（微信个人收款没有公开的唤起付款页接口）。
- 影响版本：v0.13.2 测试版（`X.Y` 由用户定，AI 只动 `Z` 与 `build`）

---

## 1. 目标 / 非目标 / 反目标

**目标**

- 「我的 → 关于」里有一行「关于倒班助手Pro」，点进去是一整页：作者、版本、官网、开源仓库、
  问题反馈、开源许可、隐私说明。
- 「我的」页新增「支持」区，一行「请我喝杯奶茶」，打开底部玻璃弹层：
  - 金额 `¥5 / ¥10 / ¥20 / 自定义`；
  - 支付宝一键唤起收款页；微信展示二维码并给出截图识别说明；
  - 没有广告、没有订阅的说明写清楚，不诱导。
- 把 v0.13.1 之后已经过时的文案改掉，尤其是「国内需要开代理」「连不上 GitHub」这类
  与三通道更新机制矛盾的句子。
- 新页面 / 新弹层进视觉工装屏单，单测 + analyze + 工装出图都有证据。

**非目标**

- 不接支付宝当面付 / 微信支付商户号，不做服务端验签、订单、回调。
- 不做「支付成功后自动感谢」之类的闭环 —— 个人收款码没有回调。
- 不改更新检查的三通道顺序、不改 `latest.json` 格式。
- 不改 README 配图管线（本轮是测试版，不是 `X.Y.0` 正式版）。
- 不引入新的第三方依赖。

**反目标**

- 用占位二维码发版，用户扫到别人的账户。
- 把「一键付款」写成支付宝、微信都能做到 —— 微信个人收款做不到，文案不能撒谎。
- 打赏文案写得像收费墙 / 订阅引导，或遮挡主要功能。
- 为了加两行入口把 `profile_screen.dart` 继续堆高（它已在 E14 台账里）。

---

## 2. 方案

### 2.1 关于页（`features/profile/about_screen.dart`）

整页，沿用《使用帮助》的骨架：`Scaffold + AppBar + CenteredContent + ListView`。

```
┌ 关于 ─────────────────────────────┐
│  [品牌图标]  倒班助手Pro            │
│              v0.13.2               │
│  为倒班的人做的排班日历、           │
│  班次闹钟与待办日程                 │
├────────────────────────────────────┤
│ 开发者          Alec Wang          │
│ 开源许可        MIT            >   │
│ 官方网站        daoban-shift.pages.dev  > │
│ 开源仓库        github.com/Alec-WangLi/… > │
│ 问题反馈        GitHub Issues     > │
├────────────────────────────────────┤
│ 隐私                               │
│ 无账号、无广告、无后端。排班、待办  │
│ 与设置只存在这台手机上，不会上传。  │
└────────────────────────────────────┘
```

- 品牌图标不引入图片资源：用当前主色的圆角方块 + 白色日历图标（与官网 favicon 同形），
  深色 / 浅色、五种主色都成立，也不增加 APK 体积。
- 链接统一走 `AlarmService.openUrl()`（原生 `ACTION_VIEW`）；打不开时提示
  「没能打开链接，请检查是否安装了浏览器」，不抛给界面。
- 官网地址取 `UpdateChecker.siteBase`（唯一来源）；仓库 / Issues / LICENSE 地址由
  `UpdateChecker` 新暴露的 `repoUrl` / `issuesUrl` / `licenseUrl` 提供，不在 UI 里重抄。
- 「关于」区从 `profile_screen.dart` 抽成 `about_section.dart`（`AboutSection`），
  把版本 / 检查更新 / 版本更新 / 使用帮助 / 查看日志一起搬过去 —— 既让新入口有位置，
  也把 `profile_screen.dart` 从 E14 台账里往下减一截。

### 2.2 打赏（`features/profile/donate_sheet.dart`）

入口：「我的 → 支持 → 请我喝杯奶茶」。底部弹层，`GlassPanel(solid: true)` +
`GlassSheetHeader`，与铃声 / 贪睡选择器同一套配方。

```
┌ 请我喝杯奶茶 ─────────────────────┐
│ 倒班助手Pro 没有广告，也没有订阅。  │
│ 它帮到你的话，可以请作者喝杯奶茶。  │
│                                   │
│ 金额   [ ¥5 ][ ¥10 ][ ¥20 ][自定义]│
│                                   │
│ [ 支付宝 ]        [ 微信 ]         │
│                                   │
│ 支付宝会直接打开收款页；微信请截图  │
│ 后用「扫一扫 → 相册」识别。        │
└───────────────────────────────────┘
```

- 金额：`GlassSegment` 四档；「自定义」弹一个玻璃输入弹窗（`GlassField` + 数字键盘），
  合法范围 1–2000 元，非法值留在弹窗里提示，不关窗。
- 支付宝：
  - 若二维码内容串（`DonateAssets.alipayQrUrl`）可用，走
    `alipays://platformapi/startapp?saId=10000007&qrcode=<encodeComponent>` 直接唤起收款页；
    打开失败（没装支付宝 / ROM 拦截）时回落到二维码弹窗。
  - 二维码内容串从用户提供的图片里解出来，**不写死账户、手机号**。
- 微信：没有公开的唤起付款页接口，弹二维码弹窗。说明写「截图后用微信『扫一扫 → 相册』识别，
  或让另一台设备扫」。
- 二维码弹窗：白底圆角容器 + `Image.asset`，下面写当前金额与下一步；图片读取失败时显示
  「二维码还没配置」而不是让页面报错。
- 资源：`app/assets/donate/alipay.png`、`wechat.png`，pubspec 挂 `assets/donate/`；
  加 `donate_assets_test.dart` 断言两张图真的能 `rootBundle.load`，缺图 CI 直接红，
  防止把占位图或空目录发出去。

### 2.3 文案审校（本轮先改的确定项）

| 位置 | 现状 | 改成 | 为什么 |
|---|---|---|---|
| `checkUpdateSubtitle` | 检查最新正式版 / 测试版（国内网络需开代理） | 检查最新正式版 / 测试版；国内可直连官网下载 | v0.13.1 起官网清单是首选通道，旧句已不成立 |
| `updateCheckFailed` | 连不上 GitHub 服务器。若你在国内，通常需要开启代理或加速器后重试。 | 官网与 GitHub 都连不上。请检查网络后重试；也可以直接到官网下载最新版。 | 三条通道都失败才是这个弹窗，原因不再只是 GitHub |
| `downloadFailed` | 下载失败：连不上 GitHub 服务器…… | 下载失败：网络中断或下载地址没有响应，请检查网络后重试。 | 下载直链可能来自官网清单，不再必然是 GitHub |
| `viewLogSubtitle` | 排错时把这里的内容复制给我 | 反馈问题时把这里的内容复制过去 | 「给我」在公开 App 里指向不明，也不适合作为长期文案 |
| `widgetEntrySubtitle` | 说明在《使用帮助》里，小米机型在二级分类里 | 添加方法与常见问题见《使用帮助》；小米机型在二级分类里 | 前半句只说「在哪」，没说「里面有什么」 |
| `ringtoneSubtitle` | 选择内置、系统、你的铃声，或「仅震动」 | 选择内置、系统或自己的铃声，或「仅震动」 | 「你的铃声」与「系统铃声」并列时断句不顺 |
| `guideUpdateDesc` | 两条 | 补一条「国内可直连官网，连不上时自动回退 GitHub」 | 帮助页应当解释三通道，而不是只列「检查更新」 |
| `app_dialogs.dart` 注释 | 说清「连不上 GitHub、国内要开代理」 | 改成「官网与 GitHub 都失败」 | 注释与实现对不上（E15） |
| `update_checker.dart` 注释 | 提到不存在的 `.github/workflows/site.yml` | 改成 `scripts/release.ps1` 第 9 步 / `scripts/build_site.py` | 注释里的路径必须真实存在（standards_check 同源规矩） |

新增文案统一走 `L10n`（E12）：`about*`、`support*`、`donate*` 三组 getter / 带参 fn。

---

## 3. 文件与改动

**新增**

- `app/lib/features/profile/about_screen.dart`
- `app/lib/features/profile/about_section.dart`
- `app/lib/features/profile/donate_sheet.dart`
- `app/assets/donate/alipay.png`、`wechat.png`（用户提供）
- `app/test/about_screen_test.dart`、`app/test/donate_sheet_test.dart`、`app/test/donate_assets_test.dart`

**修改**

- `app/lib/features/profile/profile_screen.dart`：删掉原「关于」区的五种行与 `_checkUpdate` /
  `_showLog`，换成 `AboutSection`；加 `SectionHeading(L10n.sectionSupport)` + 打赏行。
- `app/lib/core/l10n.dart`：新增文案 + 上表改动。
- `app/lib/core/update_checker.dart`：暴露 `repoUrl` / `issuesUrl` / `licenseUrl`，修正注释。
- `app/lib/features/profile/app_dialogs.dart`：v0.13.2 更新日志、修正注释。
- `app/pubspec.yaml`：`assets:` 挂 `assets/donate/`；版本 `0.13.2+189`。
- `app/lib/core/app_info.dart`：`appVersion = '0.13.2'`。
- `app/tool/visual/visual_screens.dart`：加「关于」与「打赏弹层」两条屏单。
- `.github/workflows/ci.yml`：`EXPECTED_TESTS` 按 CI 尾行实测更新。
- `docs/changelog/v0.13.md`：补 v0.13.2 一条。

---

## 4. 测试与验收

- `flutter analyze`：0 error / 0 warning（info 可容忍）。
- `flutter test`：新增三组用例；`EXPECTED_TESTS` 只增不减，数字以 CI 尾行 `+N` 为准。
  - `about_screen_test`：渲染出 Alec Wang / MIT / 官网 / 仓库，点官网断言 `openUrl` 收到
    `siteBase`，点仓库断言收到 `repoUrl`。
  - `donate_sheet_test`：四档金额切换、自定义金额校验、点微信弹出二维码弹窗；
    不依赖真实图片（`errorBuilder` 兜底）。
  - `donate_assets_test`：两张图都能从 `rootBundle` 读到。
- 视觉工装：`flutter test tool/visual/` 出「关于」「打赏弹层」两张图，逐张看。
- 真机 / 模拟器：点一遍官网、GitHub、Issues、支付宝唤起、微信扫码提示。
- 发版前确认 `app/assets/donate/` 两张不是占位图、不是空文件；`release.ps1` 的签名校验照旧。

---

## 5. 风险与待办

- **支付宝唤起依赖二维码里的 URL**：用户提供图片后需要解码。若本机解不出，请用户把
  支付宝「收款码」的链接文本发来；没有链接时只能退回二维码展示，并在文案里说清。
- **微信只能扫码**：已在用户拍板范围内，文案不承诺「一键」。
- **收款码是敏感素材**：只放本地仓库，不入文档截图；发版前确认图上没有多余个人信息。
- **2027 年法定节假日数据**：`lunar_info.dart` 目前只到 2026 年底，与本轮文案审校无关，
  但 2026-11-10 已临近，单独记为后续项，不在本轮偷偷改。
