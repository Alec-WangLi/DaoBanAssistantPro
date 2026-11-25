# 性能测量与装包安全（2026-11-10 事故）

## 事故

为测量液态玻璃的帧耗时，把测量包的 `applicationId` 改成
`com.daoban.shiftassistantpro.perf`，但**保留 `namespace = com.daoban.shiftassistantpro`**，
用 `flutter drive` 装到用户主力机上。

`flutter drive` 收尾卸载时按 **manifest 包名**执行：

```
PackageManager: Uninstall pkg: com.daoban.shiftassistantpro ... from u2000/15951
```

于是手机上正式安装的 `com.daoban.shiftassistantpro` 连同 `/data/data` 里的排班、待办、
设置一起被卸载。设备没有 root，卸载后的内部数据无法恢复；小米本地备份为空、
Google 备份无 restore set，最终数据永久丢失。

## 根因（按严重程度）

1. **误以为改 `applicationId` 就能隔离。** Flutter 的安装/卸载流程认的是 manifest 包名
   （namespace），不是 applicationId；两者不一致时，它卸载的是 namespace 那个包。
2. **没读工具的卸载路径就动了用户数据。** Flutter 源码就在本地，
   `installApp → uninstallApp(app.id)` 一次 grep 就能看到，但没有先查。
3. **在主力机上装测试包，却没有先确认备份。** 性能测量完全可以用模拟器 / 备用机，
   或一份独立工程副本。
4. **忽略了矛盾信号。** 早期 `pm list packages | grep shift` 查不到已安装的 App，
   没有追问为什么，反而继续往下做。
5. **装完没有立刻核对正式包是否还在。** 直到测量结束才发现。

## 硬规则

- **装包前**：确认目标包名、确认用户数据有备份、明确告知会动到哪个包。
- **隔离测量包**：`namespace` 与 `applicationId` **一起改**，或复制独立工程；
  不要只改一个。改完用 `aapt2 dump badging` 核对两个值。
- **装完立刻核对**：`cmd package list packages | grep <正式包>` 与
  `dumpsys package <正式包> | grep versionName`；正式包一消失立刻停止并恢复。
- **优先模拟器 / 备用机**；主力机只在用户明确要求且确认备份后使用。
- 不要用「改包名」来回避动用户数据；改不彻底比不改更危险。
