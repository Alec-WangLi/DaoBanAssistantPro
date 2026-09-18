# 胶囊悬浮修正 + 去高光 · 执行方案

- 日期：2026-09-04
- 目标版本：`0.4.6+66`（末位非 0 → 自动发**测试版**）
- 状态：待执行（给低成本模型照做即可）

## 一句话背景

v0.4.5 把底部导航胶囊做成了「近实心 + 投影 + 左上角静态高光」，观感差（像贴底蒙版、没有液态透明感）。本方案改回「半透明磨砂玻璃」，并去掉投影和左上角静态高光。

---

## 全局约束

- 所有 flutter 命令先 `cd app`。
- 构建环境见 `tools/build-env.ps1`（设 JAVA_HOME/ANDROID_HOME/PUB_CACHE/GRADLE_USER_HOME 等）。`flutter analyze` / `flutter test` 不需要该环境；`flutter pub get` 与 `flutter build` 需要。
- 验收铁律：`flutter analyze` **0 error / 0 warning**；`flutter test` 全过。
- 版本号在 `app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处同步。

---

## 改动 1 · `app/lib/core/design_tokens.dart`：胶囊填充改半透明 + 删除 navShadow

找到约 110–125 行这段：

```dart
  // ── 底部悬浮导航胶囊（近实填充 + 强投影：内容从下方干净穿过，无磨砂蒙版） ──
  static List<Color> navFill(bool isDark) => isDark
      ? [
          const Color(0xFF16161E).withValues(alpha: 0.97),
          const Color(0xFF16161E).withValues(alpha: 0.92),
        ]
      : [
          Colors.white.withValues(alpha: 0.97),
          Colors.white.withValues(alpha: 0.93),
        ];

  static BoxShadow navShadow(bool isDark) => BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.16),
        blurRadius: 28,
        offset: const Offset(0, 12),
      );
```

**整段替换为：**

```dart
  // ── 底部悬浮导航胶囊（半透明磨砂玻璃：真实模糊 + 通透白 tint，内容滑过若隐若现） ──
  static List<Color> navFill(bool isDark) => isDark
      ? [
          Colors.white.withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0.06),
        ]
      : [
          Colors.white.withValues(alpha: 0.62),
          Colors.white.withValues(alpha: 0.28),
        ];
```

（`navShadow` 整个删掉，胶囊不再有投影。）

---

## 改动 2 · `app/lib/core/glass/glass.dart`：玻璃面板去掉左上角静态高光

找到 `GlassPanel._build` 里约 89–113 行这段：

```dart
      child: Stack(
        children: [
          // 顶部镜面高光（静态左上，不再随手机倾斜流动）
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: LinearGradient(
                    begin: const Alignment(-0.4, -1.2),
                    end: const Alignment(0.0, -0.5),
                    colors: AppTokens.glassHighlight(isDark),
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: padding ?? const EdgeInsets.all(20),
            child: Material(color: Colors.transparent, child: child),
          ),
        ],
      ),
```

**替换为：**

```dart
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: Material(color: Colors.transparent, child: child),
      ),
```

> 注意：`glassHighlight` token 还被 `glass_snackbar.dart` 用到，**不要删 token 本身**，只删 GlassPanel 里这段高光 Stack。

---

## 改动 3 · `app/lib/features/home/home_shell.dart`：胶囊恢复磨砂模糊 + 去投影 + 去高光

### 3a. 替换开头（约 281–317 行）

找到：

```dart
        child: Container(
          height: _capsuleHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_capsuleHeight / 2),
            border: Border.all(color: AppTokens.glassBorder(isDark)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTokens.navFill(isDark),
            ),
            boxShadow: [AppTokens.navShadow(isDark)],
          ),
          child: Stack(
            children: [
              // 静态顶部镜面高光（悬浮玻璃质感，无磨砂模糊蒙版）
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.all(_innerPad),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(_capsuleHeight / 2),
                        gradient: LinearGradient(
                          begin: const Alignment(-0.4, -1.2),
                          end: const Alignment(0.0, -0.5),
                          colors: AppTokens.glassHighlight(isDark),
                          stops: const [0.0, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(_innerPad),
                child: LayoutBuilder(
```

**替换为：**

```dart
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_capsuleHeight / 2),
          child: GlassBlur(
            sigma: AppTokens.blurPanel,
            child: Container(
              height: _capsuleHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_capsuleHeight / 2),
                border: Border.all(color: AppTokens.glassBorder(isDark)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppTokens.navFill(isDark),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(_innerPad),
                child: LayoutBuilder(
```

### 3b. 替换结尾（约 407–415 行）

找到 LayoutBuilder 的 builder 结束后的收尾括号：

```dart
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
```

**替换为：**

```dart
                },
              ),
            ),
          ),
        ),
      ),
      ),
    );
```

> 3b 本质：把第 4 行的 `],` 改成 `),`（原来那个 `Stack(children:[...])` 没了，变成 `Container > Padding > LayoutBuilder`，外面包 `ClipRRect > GlassBlur`，括号层级仍是 9 行、配平）。改完一定跑 `flutter analyze` 验证括号没配错。

---

## 改动 4 · 版本号两处

- `app/pubspec.yaml`：`version: 0.4.5+65` → `version: 0.4.6+66`
- `app/lib/core/app_info.dart`：`const String appVersion = '0.4.5';` → `const String appVersion = '0.4.6';`

---

## 改动 5 · 更新日志 `app/lib/features/profile/app_dialogs.dart`

在 `_changelogZh` 最前（`const String _changelogZh = 'v0.4.5\n'` 之前）**插入**：

```dart
'v0.4.6\n'
'· 底部导航胶囊改回半透明磨砂玻璃：内容滑过若隐若现，去掉投影和左上角高光\n\n'
```

在 `_changelogEn` 最前插入：

```dart
'v0.4.6\n'
'· Bottom nav capsule back to translucent frosted glass (content shows through while scrolling), removed its shadow and the top-left highlight\n\n'
```

然后**删除**两个列表各自最末一条（都是 `v0.3.4`，保持 10 条）：

```dart
'v0.3.4\n'
'· 检查更新真正修复：内置只读令牌请求 GitHub API，私有仓库也能查到最新版\n'
'· 认证后限额 5000 次/小时，不再有未认证频率限制\n\n'
```

```dart
'v0.3.4\n'
'· Update check truly fixed: authenticates with a bundled read-only token, so the private repo is reachable\n'
'· Authenticated limit is 5000/hr, no more unauthenticated rate limit\n\n'
```

---

## 改动 6 · 设计规格文档同步（防止带偏）

文件：`docs/superpowers/specs/2026-09-03-design-language-unification-design.md`

- §2 设计方向第 3 点：把关于「镜面高光 / 静态左上高光」的描述改成「**玻璃 = 磨砂模糊 + 半透明 tint + 细描边，无镜面高光**」。
- §5 整节：标题从「玻璃高光（静态左上）」改为「玻璃 = 磨砂模糊 + 半透明（无镜面高光）」，内容写：玻璃质感来自真实背景模糊 + 半透明白 tint + 顶部细描边，**不再叠加任何镜面高光**。
- 文末「修订记录」追加一行：`2026-09-04`：去掉玻璃面板左上角静态高光；底部导航胶囊去掉投影、改回半透明磨砂玻璃（navFill 白 0.62→0.28 亮 / 0.14→0.06 暗）。

---

## 验证

```bash
cd app
flutter analyze      # 必须 0 error / 0 warning
flutter test         # 全过
```

---

## 构建 + 提交 + 推送 + 发版（按既定自动流程）

1. 构建 APK（arm64，同 v0.4.5 方式）：
   ```bash
   cd app
   # 先 source tools/build-env.ps1 里那套环境变量（JAVA_HOME/ANDROID_HOME/PUB_CACHE/GRADLE_USER_HOME/ANDROID_USER_HOME/APPDATA/LOCALAPPDATA/PATH）
   flutter build apk --release --target-platform android-arm64
   cp build/app/outputs/flutter-apk/app-release.apk ../dist/倒班助手Pro-v0.4.6.apk
   ```
2. 提交全部改动（含本方案文档、图标脚本不动），commit message 形如：
   `fix(design): v0.4.6 胶囊改回半透明磨砂玻璃 + 去投影/去高光`
   （结尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`）
3. `git push origin main`
4. 写发布说明 `tools/gh/release-notes-v0.4.6.md`（含 SHA256 + 构建信息），然后：
   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release.ps1 -SkipConfirm
   ```
   它会自动标 `v0.4.6` 为**测试版**并上传 APK 到 GitHub Release。

> 说明：APK 不进 git（走 Releases）；`dist/`、`tools/`、`work/` 已被 .gitignore 忽略。
