# 阅读 (legado)

基于 Flutter 的 Material Design 3 开源阅读器。系统语言为中文时显示「阅读」，其他语言显示「legado」。

## 功能

功能概览：

- **书架**：分组页签（标签/分区）、列表/紧凑列表/网格 2~6 列布局、手动排序、书架管理（多选、批量移动分组/缓存/导出/删除）、
  更新目录、本地/远程/URL 添加书籍、书架导入导出
- **发现**：各书源发现分类一屏直达，支持搜索过滤与书源分组过滤
- **订阅**：RSS 订阅源网格、订阅源管理（启用/编辑/删除/分组过滤）、文章阅读与收藏
- **我的**：书源管理、TXT 目录规则、替换净化、词典规则、主题模式、Web 服务、备份与恢复、主题设置、其他设置、书签、阅读记录、文件管理、关于
- **阅读体验**：主题管理、排版精细设置、朗读 TTS、书签
- **其他**：备份恢复、Web 服务、`legado://` 深链导入、二维码分享、主题导入导出

## 下载

前往 [Releases](https://github.com/ReTyne/legado-Klys/releases) 下载最新构建：

- `app-universal-release.apk` — Android 通用版
- `app-arm64-release.apk` — Android arm64 专用版
- `legado-ios-unsigned.ipa` — iOS 未签名包（需自行签名 / sideload）

当前版本：**1.0-beta**

## 开发

```bash
flutter pub get
flutter run
flutter test        # 146 个测试
```

应用图标由 `tools/gen_launcher_icons.py` 程序化生成，修改设计后运行 `python3 tools/gen_launcher_icons.py` 重新生成。

## 致谢

- [legado](https://github.com/gedoor/legado) - 原版开源阅读器
- [legado-with-MD3](https://github.com/HapeLee/legado-with-MD3) - MD3 设计参考

## 许可

[GNU GPL v3](LICENSE)
