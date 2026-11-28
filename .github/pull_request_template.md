## 改了什么

<!-- 一句话说清「改之前是什么样、改之后是什么样」。别写「优化了一些体验」这种。 -->

## 为什么

<!-- 关联的 Issue（`Closes #13`）、用户报的现象、或者决策记录里的理由。 -->

## 怎么验证的

<!-- 贴原始输出，不要写「测试通过」。 -->

```
flutter analyze      →
flutter test         → +N
flutter test tool/visual/  → +N（动 UI 才有）
```

## 提交前逐条确认

- [ ] 目标分支是 **`beta`**（`main` 只在发正式版时收合并）
- [ ] `flutter analyze` 是 `No issues found!`
- [ ] 用例只增不减，条数与 `.github/workflows/ci.yml` 的 `EXPECTED_TESTS` 对得上
- [ ] 动了 Drift 表：已跑 `dart run build_runner build`，`app_database.g.dart` 一起提交
- [ ] 改了界面：`app/test/` 里对应的守门用例跟着更新，视觉工装跑过
- [ ] 升了版本：`app/pubspec.yaml` 与 `app/lib/core/app_info.dart` 两处同步（`app_info_test.dart` 会拦）
- [ ] 补了更新日志：`app_dialogs.dart` 的 `_changelogZh` / `_changelogEn` 各 prepend 一条、保持 10 条
- [ ] 改了界面或版本：`site/index.html`、`README.md`、`PRODUCT_SPEC.md` 的版本与文案同步
- [ ] 没有提交 `tools/`、`toolchain/`、`dist/`、`work/`、keystore 与 `key.properties`

## 风险与回滚

<!-- 涉及闹钟重排、数据迁移、备份导入的，写清最坏情况是什么、怎么退回去。 -->
