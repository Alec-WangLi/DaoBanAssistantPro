# 日历卡片避让胶囊 + 胶囊通透度微调 · 执行方案

- 日期：2026-09-05
- 目标版本：`0.4.8+68`（末位非 0 → 自动发**测试版**）
- 状态：待执行（给低成本模型照做）

## 背景

v0.4.7 把内容「铺满到底」解决了胶囊四周空背景，但日历页的**今日信息卡**是固定不滑动的元素，现在被悬浮胶囊挡住。本方案：给该卡加底部留白让它上移到胶囊上方；同时 `navFill`（胶囊玻璃填充）通透度再透一点点。

---

## 全局约束

- flutter 命令先 `cd app`。
- 构建环境同前（设 JAVA_HOME/ANDROID_HOME/PUB_CACHE/GRADLE_USER_HOME/ANDROID_USER_HOME/APPDATA/LOCALAPPDATA/PATH）。
- `flutter analyze` **0 error / 0 warning**；`flutter test` 全过。
- 版本号在 `app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处同步。

---

## 改动 1 · `app/lib/core/design_tokens.dart`：navFill 通透度再调

找到约 111–119 行：

```dart
  static List<Color> navFill(bool isDark) => isDark
      ? [
          Colors.white.withValues(alpha: 0.11),
          Colors.white.withValues(alpha: 0.045),
        ]
      : [
          Colors.white.withValues(alpha: 0.52),
          Colors.white.withValues(alpha: 0.20),
        ];
```

**整段替换为：**

```dart
  static List<Color> navFill(bool isDark) => isDark
      ? [
          Colors.white.withValues(alpha: 0.09),
          Colors.white.withValues(alpha: 0.035),
        ]
      : [
          Colors.white.withValues(alpha: 0.44),
          Colors.white.withValues(alpha: 0.16),
        ];
```

---

## 改动 2 · `app/lib/features/calendar/calendar_screen.dart`：今日信息卡上移

找到约 719–720 行（`_infoCard` 方法的返回 `Padding`）：

```dart
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
```

**把底部 padding `16` 改成 `120`：**

```dart
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
```

（120 = 胶囊高度 64 + 底部安全区 ~34 + 余量，卡片稳妥落在胶囊上方；与 profile 页已有的底部留白 120 一致。）

---

## 改动 3 · 版本号两处

- `app/pubspec.yaml`：`version: 0.4.7+67` → `version: 0.4.8+68`
- `app/lib/core/app_info.dart`：`const String appVersion = '0.4.7';` → `const String appVersion = '0.4.8';`

---

## 改动 4 · 更新日志 `app/lib/features/profile/app_dialogs.dart`

### zh 加条目（前缀）

把：

```dart
const String _changelogZh = 'v0.4.7\n'
    '· 底部胶囊更通透、内容无遮挡穿过：去掉浮层四周的空背景「蒙版」\n\n'
```

改成：

```dart
const String _changelogZh = 'v0.4.8\n'
    '· 日历今日信息卡上移、不再被悬浮胶囊遮挡；胶囊通透度再微调\n\n'
    'v0.4.7\n'
    '· 底部胶囊更通透、内容无遮挡穿过：去掉浮层四周的空背景「蒙版」\n\n'
```

### zh 删最旧（保持 10 条）

把：

```dart
    '· 统一触摸反馈：列表条目玻璃水波纹 + Q弹；弹窗按钮全面玻璃化 + ✕ 关闭\n\n'
    'v0.3.6\n'
    '· 修复日历格子文字偏移不居中（「班」角标引入的回归）\n'
    '· 检查更新「去下载」改为应用内下载 + 自动拉起安装，无需登录 GitHub\n'
    '· 修复应用重启时的 StaleDataException 崩溃（系统铃声列表 cursor）\n\n';
```

改成：

```dart
    '· 统一触摸反馈：列表条目玻璃水波纹 + Q弹；弹窗按钮全面玻璃化 + ✕ 关闭\n\n';
```

### en 加条目（前缀）

把：

```dart
const String _changelogEn = 'v0.4.7\n'
    '· More translucent bottom capsule, content flows underneath unobstructed — removed the empty “mask” band around it\n\n'
```

改成：

```dart
const String _changelogEn = 'v0.4.8\n'
    '· Raised the calendar today-info card so the floating capsule no longer covers it; capsule translucency tuned slightly\n\n'
    'v0.4.7\n'
    '· More translucent bottom capsule, content flows underneath unobstructed — removed the empty “mask” band around it\n\n'
```

### en 删最旧（保持 10 条）

把：

```dart
    '· Unified touch feedback (glass ripple + springy scale) and glass dialog buttons + ✕ close\n\n'
    'v0.3.6\n'
    '· Fixed calendar cell text misalignment (regression from the "班" tag)\n'
    '· Update "Download" now downloads in-app and opens the installer, no GitHub login required\n'
    '· Fixed StaleDataException crash on app restart (system ringtone cursor)\n\n';
```

改成：

```dart
    '· Unified touch feedback (glass ripple + springy scale) and glass dialog buttons + ✕ close\n\n';
```

> 注意：en 里是英文弯引号 `“mask”` 和符号 `✕`，复制时保持原样。

---

## 改动 5 · 设计规格修订记录 `docs/superpowers/specs/2026-09-03-design-language-unification-design.md`

在修订记录表 `0.4.7+67` 那一行**下面**追加：

```markdown
| 2026-09-05 | 0.4.8+68 | 日历「今日信息卡」加底部留白(120)避让悬浮胶囊；`navFill` 通透度再微调（亮 0.44→0.16 / 暗 0.09→0.035）。 |
```

---

## 验证

```bash
cd app
flutter analyze   # 0 error / 0 warning
flutter test      # 13 项全过
```

---

## 构建 + 提交 + 推送 + 发版（自动流程）

1. 构建 APK（arm64）：
   ```bash
   cd app
   flutter build apk --release --target-platform android-arm64
   cp build/app/outputs/flutter-apk/app-release.apk ../dist/倒班助手Pro-v0.4.8.apk
   ```
   （用 aapt 核对 `versionName=0.4.8` / `versionCode=68`）
2. 提交并推送：
   ```bash
   cd ..
   git add -A
   git commit -m "fix(design): v0.4.8 日历卡避让胶囊 + 胶囊更通透
   
   Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
   git -c http.proxy= push origin main
   ```
   （`-c http.proxy=` 是绕过本地可能挂掉的代理 127.0.0.1:7890 走直连，不改全局配置）
3. 写发布说明 `tools/gh/release-notes-v0.4.8.md`（含 SHA256 + 构建信息 + 对应源码提交），然后：
   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release.ps1 -SkipConfirm
   ```
   自动标测试版并上传 APK。

> APK 不进 git（走 Releases）；`dist/`、`tools/`、`work/` 已被 .gitignore 忽略。