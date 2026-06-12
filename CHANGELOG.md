# Changelog

## v1.0.0

### 中文

- 首个公开版本：本地优先的 Flutter 记账本，支持 macOS、Android，以及由 GitHub Actions 构建的 Windows x64 包。
- 支持当前金额校准、实时余额、收入/支出新增编辑删除、撤销删除和按天归档。
- 支持微信支付、支付宝账单 CSV / XLSX / 文本导入，写入前先预览有效、重复和错误记录。
- 新增分类图标、导入来源图标和正式应用图标。
- 修复 macOS 新增账单时可能因 SQLite FFI 原生层崩溃导致闪退的问题。
- 增加数据库保存测试和 macOS 新增账单集成测试。

### English

- First public release: a local-first Flutter bookkeeping app for macOS, Android, and a Windows x64 package built by GitHub Actions.
- Supports current balance anchoring, real-time balance, entry create/edit/delete/restore, and daily archives.
- Supports WeChat Pay and Alipay bill import from CSV, XLSX, and pasted table text with preview before saving.
- Adds category icons, import source icons, and a custom app icon.
- Fixes a macOS crash that could happen when adding a ledger entry through the SQLite FFI native path.
- Adds database save coverage and a macOS integration test for adding a manual entry.
