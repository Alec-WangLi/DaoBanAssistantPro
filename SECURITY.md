# 安全策略

## 这个项目

倒班助手Pro 是一个**纯本地离线**的 Android App（Flutter）：没有账号、没有后端、没有广告，排班与待办数据只存在用户自己的手机里，仓库也不收集任何遥测。

因此，这里值得报的安全问题主要是：

- App 能读到不属于它的数据、或把用户数据写去了不该去的地方；
- `AndroidManifest.xml` 里某个组件本不该导出却导出了（`exported="true"`）；
- 应用内更新（`REQUEST_INSTALL_PACKAGES` + FileProvider）被利用去安装非预期 APK；
- 仓库里混进了凭据、签名文件或其它不该公开的东西。

## 怎么报

**请不要在 Issue 里贴漏洞细节。**

用 GitHub 的私密漏洞报告入口：

> 仓库页 → **Security** → **Advisories** → **Report a vulnerability**

（地址：<https://github.com/Alec-WangLi/DaoBanAssistantPro/security/advisories/new>）

## 我们会怎么处理

- 这是一个个人维护的开源项目，没有 SLA，但会尽量在 **7 天内**给第一次回复。
- 修好之后会发一个补丁版本，并在 Release 说明里致谢（如果你愿意署名）。
- 已经公开的 Release 历史不会被重写；如需撤销某个旧包，会在 Release 说明里标注。

## 支持范围

只有**最新版本**（Releases 页上的 Latest 与最新预发布）会被修。旧版本请先升级再谈。
