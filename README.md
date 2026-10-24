# 阅读 (legado)

基于 Flutter 的 Material Design 3 开源阅读器。系统语言为中文时显示「阅读」，其他语言显示「legado」。

## 功能

- **本地书籍**：TXT / EPUB / PDF 导入与阅读，章节字数统计
- **网络书源**：JS 规则解析搜索、目录与正文，兼容 legado 书源生态
- **阅读体验**：主题管理、排版精细设置、朗读 TTS、书签、阅读统计
- **书架与发现**：分组管理、首页模块自定义、RSS 订阅阅读
- **其他**：备份恢复、Web 服务、`legado://` 深链导入、二维码分享、主题导入导出

## 下载

前往 [Releases](https://github.com/ReTyne/legado-Klys/releases) 下载最新 APK（universal / arm64）。

当前版本：**1.0-beta**

## 开发

```bash
flutter pub get
flutter run
flutter test        # 83 个测试
```

应用图标由 `tools/gen_launcher_icons.py` 程序化生成，修改设计后运行 `python3 tools/gen_launcher_icons.py` 重新生成。

## 致谢

- [legado](https://github.com/gedoor/legado) - 原版开源阅读器
- [legado-with-MD3](https://github.com/HapeLee/legado-with-MD3) - MD3 设计参考

## 许可

[GNU GPL v3](LICENSE)
