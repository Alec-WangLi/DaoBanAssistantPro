# 胶囊浅色可见性 + 宽度微缩 + 主题色与滑块文字对比 · 执行方案

- 日期：2026-09-05
- 目标版本：`0.4.9+69`（末位非 0 → 自动发**测试版**）
- 状态：待执行（给低成本模型照做）

## 背景

v0.4.8 用户实测反馈三点：

1. **浅色模式胶囊可见性差**：白底上白 tint + 白描边（`glassBorder` 亮色 = 白 0.90）等于隐身，模糊在纯白背景上也无效，胶囊只剩一层淡白。
2. **胶囊略宽**：希望稍窄一点，方便单手操作。
3. **5 个主题色部分不合适**，且胶囊滑块上的选中文字（当前用主题色本身、叠在同色半透明渐变上）对比度极差，如青/橙色上文字几乎看不清。

本方案：胶囊新增**深色细描边**解决白底可见性（不加投影，尊重 v0.4.6 去投影决策）；左右边距 16→24 收窄；5 色微调 + 滑块选中文字改**自动对比色**。

> 重要说明：对比度经 RGB 空间精确核算。原设计中「暗色模式青/橙用深字」的判定是错的——半透明滑块在暗色模式下与深底混合后，**当前 5 色全部用白字更清晰（≥4.9:1）**。`navForeground` 亮色模式恒深字；暗色模式按明度阈值 0.45 分黑/白（当前 5 色全低于阈值 → 全白字）。阈值分支为未来更浅的主题色留兜底。青色受此影响从原设计 `#00A99E` 改为 `#00B3A6`（`#00A99E` 明度居中，黑白字都过不了 4.5:1）。

---

## 全局约束

- flutter 命令先 `cd app`。
- 构建环境同前（设 JAVA_HOME/ANDROID_HOME/PUB_CACHE/GRADLE_USER_HOME/ANDROID_USER_HOME/APPDATA/LOCALAPPDATA/PATH）。
- `flutter analyze` **0 error / 0 warning**；`flutter test` 全过（含本方案新增测试）。
- 版本号在 `app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处同步。

---

## 改动 1 · `app/lib/core/design_tokens.dart`：navFill 微调 + 新增 navBorder + navForeground

### 1a. navFill 亮色提不透明度（暗色不动）

找到约 110–119 行：

```dart
  // ── 底部悬浮导航胶囊（半透明磨砂玻璃：真实模糊 + 通透白 tint，内容滑过若隐若现） ──
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

**整段替换为：**

```dart
  // ── 底部悬浮导航胶囊（半透明磨砂玻璃：真实模糊 + 通透白 tint，内容滑过若隐若现） ──
  static List<Color> navFill(bool isDark) => isDark
      ? [
          Colors.white.withValues(alpha: 0.09),
          Colors.white.withValues(alpha: 0.035),
        ]
      : [
          Colors.white.withValues(alpha: 0.56),
          Colors.white.withValues(alpha: 0.24),
        ];
```

### 1b. 紧跟其后新增 navBorder 与 navForeground 两个函数

在 navFill 的 `}` 之后、类的最终 `}` 之前插入：

```dart
  /// 胶囊描边：亮色转深色细线勾勒轮廓（白底上白描边会隐身），暗色保持白描边。
  static Color navBorder(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.16)
      : inkLight.withValues(alpha: 0.14);

  /// 胶囊滑块选中项前景（图标/文字）：浅色模式滑块被白底冲淡，恒用深字；
  /// 暗色模式按明度选黑/白——当前 5 个主题色均低于 0.45 阈值，走白字。
  static Color navForeground(bool isDark, Color accent) {
    if (!isDark) return inkLight;
    return accent.computeLuminance() > 0.45 ? inkLight : inkDark;
  }
```

> 不要动 `glassBorder`（卡片/弹窗/按钮等仍用它）。

---

## 改动 2 · `app/lib/core/theme/app_colors.dart`：5 个主题色微调

找到约 12–15 行：

```dart
  static const Color sky = Color(0xFF0A84FF);
  static const Color teal = Color(0xFF00C7BE);
  static const Color orange = Color(0xFFFF9F0A);
  static const Color rose = Color(0xFFFF375F);
```

以及第 9 行的 primary：

```dart
  static const Color primary = Color(0xFF5B6CFF);
```

**全部替换为（方向：沉稳一点、拉开蓝紫与天蓝距离）：**

| 常量 | 旧值 | 新值 |
|---|---|---|
| primary 蓝紫 | `0xFF5B6CFF` | `0xFF4F5BE8` |
| sky 天蓝 | `0xFF0A84FF` | `0xFF0B6FE6` |
| teal 青 | `0xFF00C7BE` | `0xFF00B3A6` |
| orange 橙 | `0xFFFF9F0A` | `0xFFF08800` |
| rose 玫红 | `0xFFFF375F` | `0xFFE83567` |

即最终为：

```dart
  static const Color primary = Color(0xFF4F5BE8);

  static const Color sky = Color(0xFF0B6FE6);
  static const Color teal = Color(0xFF00B3A6);
  static const Color orange = Color(0xFFF08800);
  static const Color rose = Color(0xFFE83567);
```

---

## 改动 3 · `app/lib/features/home/home_shell.dart`：宽度 + 描边 + 选中文字颜色

### 3a. 左右边距 16 → 24

找到约 170 行：

```dart
  static const _outerPad = 16.0;
```

**改为：**

```dart
  static const _outerPad = 24.0;
```

### 3b. build 里新增 fg 变量

找到约 270–275 行：

```dart
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: isDark ? 0.72 : 0.55);
```

**在 inactiveColor 之后追加一行：**

```dart
    final fg = AppTokens.navForeground(isDark, activeColor); // 滑块上选中项前景
```

### 3c. 胶囊描边换 navBorder

找到约 296 行：

```dart
                border: Border.all(color: AppTokens.glassBorder(isDark)),
```

**改为：**

```dart
                border: Border.all(color: AppTokens.navBorder(isDark)),
```

### 3d. 选中图标颜色：activeColor → fg

找到约 367–373 行的 Icon：

```dart
                                  Icon(
                                    items[i].$1,
                                    size: 22,
                                    color: selected
                                        ? activeColor
                                        : inactiveColor,
                                  ),
```

**把 `color: selected ? activeColor : inactiveColor,` 改为 `color: selected ? fg : inactiveColor,`：**

```dart
                                  Icon(
                                    items[i].$1,
                                    size: 22,
                                    color: selected ? fg : inactiveColor,
                                  ),
```

### 3e. 选中文字颜色：activeColor → fg

找到约 375–386 行的 Text：

```dart
                                  Text(
                                    items[i].$2,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selected
                                          ? activeColor
                                          : inactiveColor,
                                    ),
                                  ),
```

**改为：**

```dart
                                  Text(
                                    items[i].$2,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selected ? fg : inactiveColor,
                                    ),
                                  ),
```

> `activeColor` 仍被滑块渐变（`accentGradient(activeColor)`）使用，不要删。

---

## 改动 4 · `app/test/design_tokens_test.dart`：新增 2 个测试

### 4a. 加 import

在文件头部（第 5 行 import design_tokens 之后）加：

```dart
import 'package:shiftassistantpro/core/theme/app_colors.dart';
```

### 4b. 在 `void main()` 之前加对比度辅助函数

```dart
double _wcagContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
```

### 4c. 在 `main()` 里最后一个测试之后追加两个测试

```dart
  test('navBorder 亮色为深描边、暗色为白描边', () {
    final light = AppTokens.navBorder(false);
    final dark = AppTokens.navBorder(true);
    expect(light.r, lessThan(0.3)); // 深色
    expect(dark.r, greaterThan(0.9)); // 白
    expect(light.a, greaterThan(0.08));
  });

  test('5 个主题色在胶囊滑块上文字对比度 ≥ 4.5', () {
    // 模拟滑块：主题色渐变与玻璃底按 60% 混合（文字所在区域的近似比例）
    const bgLight = Color(0xFFF5F6FA);
    const bgDark = Color(0xFF16161E);
    for (final accent in AppColors.accentPalette) {
      final sliderLight = Color.lerp(bgLight, accent, 0.6)!;
      expect(
        _wcagContrast(AppTokens.navForeground(false, accent), sliderLight),
        greaterThanOrEqualTo(4.5),
        reason: '亮色模式 $accent',
      );
      final sliderDark = Color.lerp(bgDark, accent, 0.6)!;
      expect(
        _wcagContrast(AppTokens.navForeground(true, accent), sliderDark),
        greaterThanOrEqualTo(4.5),
        reason: '暗色模式 $accent',
      );
    }
  });
```

> 预期：`flutter test` 全部通过（原 13 项 + 新增 2 项 = 15 项）。若对比度测试失败，说明色值/阈值被改错，参照本方案开头「重要说明」核算。

---

## 改动 5 · 版本号两处

- `app/pubspec.yaml`：`version: 0.4.8+68` → `version: 0.4.9+69`
- `app/lib/core/app_info.dart`：`const String appVersion = '0.4.8';` → `const String appVersion = '0.4.9';`

---

## 改动 6 · 更新日志 `app/lib/features/profile/app_dialogs.dart`

### zh 加条目（前缀）

把：

```dart
const String _changelogZh = 'v0.4.8\n'
    '· 日历今日信息卡上移、不再被悬浮胶囊遮挡；胶囊通透度再微调\n\n'
```

改成：

```dart
const String _changelogZh = 'v0.4.9\n'
    '· 底部胶囊浅色模式更清晰：柔和深色细描边 + 填充微调；胶囊略收窄、更适单手\n'
    '· 5 个主题色微调更沉稳协调；胶囊滑块上图标/文字改为自动对比色，任何颜色都清晰\n\n'
    'v0.4.8\n'
    '· 日历今日信息卡上移、不再被悬浮胶囊遮挡；胶囊通透度再微调\n\n'
```

### zh 删最旧（保持 10 条）

把末尾：

```dart
    'v0.3.7\n'
    '· 调休「班」标记改为农历行内联，不再与日期重叠\n'
    '· 新增「法定班次」空白表：跟随法定节假日作息，无班次轮换\n'
    '· 统一触摸反馈：列表条目玻璃水波纹 + Q弹；弹窗按钮全面玻璃化 + ✕ 关闭\n\n';
```

改成：

```dart
    '· 修复：日历格子文字偏移、应用重启 StaleDataException 崩溃\n\n';
```

（即直接删掉 v0.3.7 的整段 4 行，v0.4.0 的最后一条成为列表结尾。）

### en 加条目（前缀）

把：

```dart
const String _changelogEn = 'v0.4.8\n'
    '· Raised the calendar today-info card so the floating capsule no longer covers it; capsule translucency tuned slightly\n\n'
```

改成：

```dart
const String _changelogEn = 'v0.4.9\n'
    '· Bottom capsule clearer in light mode: subtle dark hairline outline + tuned fill; capsule slightly narrower for one-hand use\n'
    '· 5 accent colors refined; capsule slider icons/text now use an auto-contrast color, readable on any accent\n\n'
    'v0.4.8\n'
    '· Raised the calendar today-info card so the floating capsule no longer covers it; capsule translucency tuned slightly\n\n'
```

### en 删最旧（保持 10 条）

把末尾：

```dart
    'v0.3.7\n'
    '· Makeup-workday "班" tag now inline with the lunar text (no longer overlaps the date)\n'
    '· New "Legal-holiday schedule" blank table: follows statutory holidays, no shift rotation\n'
    '· Unified touch feedback (glass ripple + springy scale) and glass dialog buttons + ✕ close\n\n';
```

改成：

```dart
    '· Fixed: cell text misalignment, StaleDataException crash on restart\n\n';
```

---

## 改动 7 · 设计规格修订记录 `docs/superpowers/specs/2026-09-03-design-language-unification-design.md`

在修订记录表 `0.4.8+68` 那一行**下面**追加：

```markdown
| 2026-09-05 | 0.4.9+69 | 胶囊浅色可见性（新增 `navBorder` 深色细描边、`navFill` 亮色 0.44→0.56）；胶囊左右边距 16→24；5 主题色微调（`#4F5BE8/#0B6FE6/#00B3A6/#F08800/#E83567`）；滑块选中文字改 `navForeground` 自动对比色。 |
```

---

## 验证

```bash
cd app
flutter analyze   # 0 error / 0 warning
flutter test      # 15 项全过（含新增 navBorder + 5 色对比度测试）
```

---

## 构建 + 提交 + 推送 + 发版（自动流程）

1. 构建 APK（arm64）：
   ```bash
   cd app
   flutter build apk --release --target-platform android-arm64
   cp build/app/outputs/flutter-apk/app-release.apk ../dist/倒班助手Pro-v0.4.9.apk
   ```
   （用 aapt 核对 `versionName=0.4.9` / `versionCode=69`）
2. 提交并推送：
   ```bash
   cd ..
   git add -A
   git commit -m "fix(design): v0.4.9 胶囊浅色可见性 + 微缩宽度 + 主题色与滑块对比
   
   Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
   git -c http.proxy= push origin main
   ```
   （`-c http.proxy=` 是绕过本地可能挂掉的代理 127.0.0.1:7890 走直连，不改全局配置；若推送仍失败，先问用户代理 8080 是不是没开，再排查。）
3. 写发布说明 `tools/gh/release-notes-v0.4.9.md`（照 `tools/gh/release-notes-v0.4.8.md` 的格式：本次更新要点 + 构建信息 + 对应源码提交 + SHA256），然后：
   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release.ps1 -SkipConfirm
   ```
   自动标测试版并上传 APK。

> APK 不进 git（走 Releases）；`dist/`、`tools/`、`work/` 已被 .gitignore 忽略。