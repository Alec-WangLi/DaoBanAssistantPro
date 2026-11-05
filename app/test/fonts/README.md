# 测试字体（只给量文字尺寸的用例用，不进 APK）

`app/tool/visual/visual_harness.dart` 的 `ensureVisualFonts()` 从这里读字体。
**本地和 CI 读同一份字节 —— 量尺只有一把。** 不再依赖系统装了什么字体，
也不再从 `$FLUTTER_ROOT` 的缓存目录猜（2026-11-05 两次 CI 全红就是因为那目录在 runner 上是空的）。

| 文件 | 来源 | 许可 |
|---|---|---|
| `roboto-regular.ttf` | Flutter SDK `bin/cache/artifacts/material_fonts/` | Apache License 2.0 |
| `materialicons-regular.otf` | 同上 | Apache License 2.0 |
| `NotoSansSC-Regular.otf` | `NotoSansCJK-Regular.ttc` 的第 2 个字面（SC），用 fonttools 子集化 | SIL Open Font License 1.1 |

三份合计 4,675,376 B（2,858,516 + 1,645,184 + 171,676）。

重抽中文字体的完整命令、体积对照（完整字面 16.4MB / U+4E00-9FFF 9.2MB / GB2312 2.86MB /
仅仓库字符 620KB）以及「换字体等于换尺子」的代价，见 `docs/decisions/ui-rules.md` 末尾。

## 许可说明

- Noto Sans CJK 采用 **SIL OFL 1.1**：允许随软件一起再分发（含子集化），条件是随附许可文本并保留版权声明。
  许可全文见 <https://scripts.sil.org/OFL>，上游 <https://github.com/notofonts/noto-cjk>。
- Roboto 与 Material Icons 采用 **Apache License 2.0**：同样允许再分发，需保留声明。
  许可全文见 <https://www.apache.org/licenses/LICENSE-2.0>。

这三份文件只在 `flutter test` 里被加载，不参与 `flutter build apk`，因此不会增大安装包。
