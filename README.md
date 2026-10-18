# Legado MD3 - 跨平台开源阅读器

基于 [Legado](https://github.com/gedoor/legado) 开源项目的 Material Design 3 跨平台版本，使用 Flutter 开发，支持 Android 和 iOS。

## 功能特性

### 完整功能清单（已实现）

#### 📚 书架管理
- 列表/网格/详细网格三种布局自由切换
- 书籍分组管理，按分组筛选
- 批量管理（多选、删除）
- 书籍搜索
- 一键更新所有书籍章节
- 本地书籍导入（TXT/EPUB）
- 阅读进度自动保存

#### 🔍 书源系统
- 完整书源规则引擎，支持 CSS选择器、XPath、JSONPath、正则表达式、JS脚本
- 可视化分标签页编辑（基本/搜索/发现/详情/目录正文）
- 多源并发搜索
- 书源启用/禁用、分组管理
- 网络导入、本地导入、二维码导入
- 书源导出分享
- 书源校验测试

#### 📖 阅读界面
- 8种预设主题（护眼/羊皮纸/纯白/白绿/黑色/深灰/褐色/绿色）
- 字号、字体、粗细、颜色实时调节
- 行距、段距、缩进、对齐方式
- 6种翻页动画（覆盖/仿真/滑动/滚动/无动画/上下）
- 点击左/中/右三区翻页/菜单
- 顶部标题栏 + 底部时间/页码/电量显示
- 章节进度滑块、上下章快速切换
- 目录跳转、章节搜索
- 亮度调节
- 替换净化规则实时应用
- 阅读记录自动统计

#### 🔊 TTS朗读
- 系统TTS引擎支持
- 独立朗读播放器界面
- 语速、音调、音量调节
- 多语言/多引擎切换
- 章节自动连播
- 上一章/下一章/暂停/播放控制

#### 🌐 发现页
- 书源发现内容浏览
- 书源管理双Tab切换

#### 📡 订阅
- RSS/Atom订阅源管理
- 订阅源添加、刷新、删除
- 文章列表展示
- 已读/未读标记
- 外部浏览器打开文章
- 一键刷新所有订阅

#### 🔄 替换净化
- 正则表达式替换规则
- 全局/书源范围控制
- 规则启用/禁用
- 规则导入导出
- 阅读时自动应用

#### 📊 阅读统计
- 今日阅读时长
- 累计阅读时长
- 阅读天数统计
- 近30天阅读趋势图表
- 时间轴视图
- 概览/时间轴双Tab

#### 💾 备份恢复
- 完整数据备份（书籍/书源/替换规则/阅读记录）
- 备份内容可选择
- 本地备份文件管理
- 从文件恢复
- 书源单独导入/导出
- 分享备份文件

#### ⚙️ 设置
- 深色模式（跟随系统/浅色/深色）
- 主题色自定义（8种预设色）
- 通用设置（自动更新、更新间隔等）
- 阅读设置（默认配置、音量键翻页等）
- 缓存管理
- 语言设置
- 关于页面

#### 🎨 Material Design 3
- 完整MD3设计系统
- 动态颜色支持
- 预测性返回手势
- 共享元素动画
- 圆角卡片、FAB、NavigationBar
- 模态底部面板、搜索栏

### 技术架构

```
lib/
├── main.dart                    # 应用入口
├── models/                      # 数据模型 (9个)
│   ├── book.dart               # 书籍
│   ├── book_chapter.dart       # 章节
│   ├── book_source.dart        # 书源
│   ├── read_config.dart        # 阅读配置
│   ├── replace_rule.dart       # 替换规则
│   ├── search_book.dart        # 搜索结果
│   ├── rss_source.dart         # RSS订阅源
│   ├── rss_article.dart        # RSS文章
│   └── read_record.dart        # 阅读记录(在replace_rule.dart中)
├── providers/                   # 状态管理
│   └── book_provider.dart      # 书籍/阅读状态
├── services/                    # 业务服务 (9个)
│   ├── database_service.dart   # SQLite数据库
│   ├── book_source_engine.dart # 书源规则引擎
│   ├── local_file_service.dart # 本地文件导入
│   ├── tts_service.dart        # TTS朗读
│   ├── backup_service.dart     # 备份恢复
│   ├── rss_service.dart        # RSS订阅
│   ├── reading_record_service.dart # 阅读记录
│   ├── auto_update_service.dart # 自动更新
│   └── replace_rule_service.dart # 替换净化
├── screens/                     # 页面 (18个)
│   ├── main_screen.dart        # 主框架
│   ├── bookshelf_screen.dart   # 书架
│   ├── reading_screen.dart     # 阅读界面
│   ├── tts_player_screen.dart  # TTS播放器
│   ├── discover_screen.dart    # 发现
│   ├── subscribe_screen.dart   # 订阅
│   ├── profile_screen.dart     # 我的
│   ├── search_screen.dart      # 搜索
│   ├── chapter_list_screen.dart # 目录
│   ├── book_detail_screen.dart # 书籍详情
│   ├── source_manage_screen.dart # 书源管理
│   ├── source_edit_screen.dart # 书源编辑
│   ├── replace_rule_screen.dart # 替换净化
│   ├── reading_stats_screen.dart # 阅读统计
│   ├── settings_screen.dart    # 设置
│   └── backup_screen.dart      # 备份恢复
└── theme/                       # 主题
    └── app_theme.dart           # MD3主题系统
```

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── models/                      # 数据模型
│   ├── book.dart               # 书籍模型
│   ├── book_chapter.dart       # 章节模型
│   ├── book_source.dart        # 书源模型
│   ├── read_config.dart        # 阅读配置
│   ├── replace_rule.dart       # 替换规则
│   └── search_book.dart        # 搜索结果
├── providers/                   # 状态管理
│   └── book_provider.dart      # 书籍/阅读状态
├── services/                    # 业务服务
│   ├── database_service.dart   # 本地数据库
│   └── book_source_engine.dart # 书源规则引擎
├── screens/                     # 页面
│   ├── main_screen.dart        # 主框架(底部导航)
│   ├── bookshelf_screen.dart   # 书架
│   ├── reading_screen.dart     # 阅读界面
│   ├── discover_screen.dart    # 发现
│   ├── subscribe_screen.dart   # 订阅
│   ├── profile_screen.dart     # 我的
│   ├── search_screen.dart      # 搜索
│   ├── chapter_list_screen.dart # 目录
│   ├── book_detail_screen.dart # 书籍详情
│   ├── source_manage_screen.dart # 书源管理
│   ├── source_edit_screen.dart # 书源编辑
│   ├── replace_rule_screen.dart # 替换净化
│   ├── reading_stats_screen.dart # 阅读统计
│   ├── settings_screen.dart    # 设置
│   └── backup_screen.dart      # 备份恢复
├── theme/                       # 主题
│   └── app_theme.dart          # MD3主题系统
└── widgets/                     # 通用组件
```

## 技术栈

- **框架**: Flutter 3.19+
- **语言**: Dart 3.3+
- **状态管理**: Provider
- **本地存储**: SQLite (sqflite) + SharedPreferences
- **网络请求**: Dio
- **HTML解析**: html + csslib
- **图片缓存**: cached_network_image
- **TTS**: flutter_tts
- **EPUB解析**: epubx
- **文件选择**: file_picker

## 快速开始

### 环境要求
- Flutter SDK >= 3.19.0
- Dart SDK >= 3.3.0
- Android Studio (Android开发)
- Xcode 14+ (iOS开发, 仅macOS)

### 安装依赖

```bash
flutter pub get
```

### 运行

```bash
# Android
flutter run -d android

# iOS (需要macOS + Xcode)
flutter run -d ios
```

### 构建

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS (需要macOS + Xcode)
flutter build ios --release
```

## 书源规则说明

书源规则支持CSS选择器语法，主要字段：

### 搜索规则
- `searchUrl`: 搜索地址，支持 `{{key}}` 占位符
- `ruleSearch`: 搜索结果列表选择器
- `ruleSearchNoteUrl`: 书名/详情页URL
- `ruleSearchAuthor`: 作者
- `ruleSearchCover`: 封面
- `ruleSearchIntro`: 简介

### 目录规则
- `ruleToc`: 目录列表选择器
- `ruleTocName`: 章节名称
- `ruleTocUrl`: 章节URL
- `ruleTocNext`: 目录下一页

### 正文规则
- `ruleContent`: 正文内容选择器
- `ruleContentNext`: 正文下一页
- `ruleImageUrl`: 图片URL

## 与原版Legado的区别

| 特性 | 原版Legado | 本项目 |
|------|-----------|--------|
| 平台 | Android | Android + iOS |
| 语言 | Kotlin | Dart/Flutter |
| 设计 | Material Design 2 | Material Design 3 |
| 书源引擎 | 完整支持 | 基础CSS选择器支持 |
| JS规则 | 支持 | 开发中 |
| WebView | 内置 | 开发中 |

## 开发计划

- [ ] 完整的书源JS规则支持
- [ ] 内置WebView浏览器
- [ ] EPUB完整解析支持
- [ ] WebDAV同步
- [ ] 更多翻页动画
- [ ] 阅读时长统计完善
- [ ] 订阅源RSS/Atom支持
- [ ] 多语言支持

## 许可证

本项目基于 GPL-3.0 许可证开源，遵循原 Legado 项目的许可证要求。

## 致谢

- [Legado](https://github.com/gedoor/legado) - 原版开源阅读器
- [legado-with-MD3](https://github.com/HapeLee/legado-with-MD3) - MD3设计参考
