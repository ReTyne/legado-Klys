# legado-Klys 相对 legado-E（阅读Sigma）功能差距清单

> 对比基准：legado-E `main` 分支（859 个源文件，约 13.6 万行 Kotlin/Java）
> 目标项目：legado-Klys / `legado_md3`（Flutter 重写版，135 个 Dart 文件，约 5.3 万行）
> 通读范围：两项目全部源码（legado-E 的 app/modules 全模块；Klys 的 lib/test 全量）

---

## 一、总体结论

Klys 对 legado-E 的**主体功能已完成度约 85%**：书源规则引擎（五种解析模式、`||`/`&&`/`%%`/`@@` 连接符、`##` 后处理、`@put/@get`）、书架/发现/详情/目录/阅读/漫画/音频/视频/RSS/订阅/字典/替换规则/备份/WebDAV/Web 服务（Klys 实际为 E 的超集）等主线功能均已实现，且阅读配置项、TTS 引擎数量（Klys 9 家云 TTS 全部内置）等局部反超 E。

以下为**逐项核对后确认缺失**的功能，按优先级分四组。另有一组为"设计差异/平台差异"项（不计入缺失）。

---

## 二、确认缺失的功能清单

### A 组：核心功能（高优先级）

| # | 缺失功能 | legado-E 位置 | 差距说明 |
|---|---------|--------------|---------|
| A1 | **书源检测（CheckSource）** | `model/CheckSource.kt`、`service/CheckSourceService.kt`、`ui/book/source/manage/BookSourceActivity.kt`、`ui/config/CheckSourceConfig.kt` | Klys 完全没有。E 支持：超时配置、写注释开关、七项校验开关（域名/搜索/发现/详情/目录/正文）、失败自动打分组（`校验超时/js失效/网站失效/域名失效/搜索失效/发现失效/搜索目录失效/搜索正文失效` 等）、记录 `respondTime` 响应时间、前台服务进度通知。**这是 E 最核心的书源管理功能** |
| A2 | **搜索范围（SearchScope）** | `ui/book/search/SearchScope.kt`、`SearchScopeDialog.kt` | Klys 仅有"全部/书名/作者"三档（`search_scope` pref）。E 支持**按书源分组搜索**与**单书源搜索**（`名称::url` 格式，单源搜索不缓存），分组多选 |
| A3 | **验证码人工识别** | `ui/association/VerificationCodeActivity.kt` + `VerificationCodeDialog.kt`；JS 桥 `getVerificationCode(imageUrl)` | Klys JS 桥内为占位返回 `""`，无 UI。E 为透明 Activity 弹对话框展示验证码图片，人工输入后回传 JS（书源登录/反爬关键路径） |
| A4 | **在线导入 UI + 深链类型扩展** | `ui/association/OnLineImportActivity.kt`；`JsExtensions.openUrl` → `OnLineImportActivity` | Klys 深链仅支持 `bookSource/rssSource/theme` 三类（`common/deep_link_service.dart`）。E 支持七类：`bookSource/rssSource/replaceRule/textTocRule/httpTTS/dictRule/readConfig`（+theme），且有独立的"输入 URL 一键导入"界面（输入地址+自动识别类型） |
| A5 | **导出功能增强** | `ui/book/cache/CacheActivity.kt`（881 行）、`service/ExportBookService.kt`、`help/config/AppConfig.kt` | Klys 仅有 txt/epub 基础导出 + 文件名模板。E 还有：**导出类型选择**（txt/epub）、**导出到 WebDAV**、**导出不含章节名**、**图片导出为文件引用**（exportPictureFile）、**自定义导出章节范围**（`1-10,15,20` 语法 + epub 分卷大小）、**导出时净化**（replace_purify）、**并行导出**（配置项 Klys 已有，缓存页无入口）、**导出文件夹选择** |
| A6 | **书签导出** | `ui/book/toc/TocViewModel.kt` `saveBookmark/saveBookmarkMd` | Klys 书签页无导出。E 目录页书签 Tab 可导出：JSON（全字段）与 Markdown（`#### 章节` / `###### 原文` / `###### 摘要`）两种格式 |
| A7 | **exploreUrl 动态分类** | `help/source/BookSourceExtensions.kt` `exploreKinds()` | Klys `getExploreKinds` 仅解析文本格式（`标题:::url`）。E 还支持：**JSON 数组格式**（`[{"title":..,"url":..}]`，含 style/layout 扩展位）与 **`@js:`/`<js>` 动态生成分类**（带 ACache 缓存） |
| A8 | **JS 桥 `downloadFile`** | `help/JsExtensions.kt` `downloadFile(url)` | Klys 桥缺失（grep 0 命中）。E：下载任意文件到缓存目录并返回**相对路径**，书源脚本常用（如下载字体/图片后本地读取） |
| A9 | **JS 桥 `get7zStringContent`/`getRarStringContent`** | 同上 | Klys 仅有 `getZipStringContent`。E 支持直接读取 7z/rar 压缩包内指定文件内容 |
| A10 | **书籍上传 WebDAV** | `help/AppWebDav.kt`（`defaultBookWebDav`/`RemoteBookWebDav.upload`）、`ui/book/info/BookInfoActivity.upLoadBook` | Klys WebDAV 仅覆盖备份/进度/远程书籍下载，**无单本书籍上传**（详情页"上传到远程"菜单缺失） |

### B 组：阅读与播放体验

| # | 缺失功能 | legado-E 位置 | 差距说明 |
|---|---------|--------------|---------|
| B1 | **长章节自动拆分** | `data/entities/Book.kt`（`ReadConfig.splitLongChapter`）、`model/localBook/TextFile.kt`（L214/L369 `maxLengthWithToc`）、详情页菜单 | 本地 TXT 章节超过阈值时自动拆分；E 在导入与阅读两处生效，详情页可开关。Klys 无此配置与逻辑 |
| B2 | **视频长按倍速 / 自动全屏** | `model/VideoPlay.kt`（`longPressSpeed` 默认 3.0x、`startFull`） | Klys 视频播放器有倍率菜单与进度保存，但无**长按手势倍速**、无**直接全屏启动**配置 |
| B3 | **媒体按钮（耳机按键）控制** | `receiver/MediaButtonReceiver.kt`、`service/BaseReadAloudService.kt` | Klys 朗读（flutter_tts）与音频（audioplayers）无媒体按键事件处理。E 耳机按键可控制 播放/暂停/上下一章 |
| B4 | **网络状态监听** | `receiver/NetworkChangedListener.kt` | Klys 无全局网络状态广播监听。E 用于：断网时暂停自动缓存、Web 服务地址刷新等 |
| B5 | **弹幕文件存储管理** | `help/RuleBigDataHelp.kt` `getDanmakuFile` | Klys 已有阅读页弹幕展示（`_tryParseDanmaku`），但 E 有按 `bookUrl+chapterUrl` 的弹幕文件存储体系（与书源变量同级），缓存清理策略更完整 |

### C 组：数据与迁移

| # | 缺失功能 | legado-E 位置 | 差距说明 |
|---|---------|--------------|---------|
| C1 | **旧版 legado 数据迁移** | `help/storage/ImportOldData.kt`（372 行） | E 可从旧版「阅读」备份/数据目录迁移（书源分组、阅读记录、旧格式替换规则等）。Klys 备份还原格式与 E 不完全一致，旧版数据导入缺失 |
| C2 | **直链上传（DirectLinkUpload）** | `help/DirectLinkUpload.kt` | 按规则把本地文件（压缩 zip 后）上传到目标服务器，返回下载直链——用于把本地书籍生成分享链接。Klys 无 |

### D 组：平台/系统集成（Flutter 侧需原生配合）

| # | 缺失功能 | legado-E 位置 | 差距说明 |
|---|---------|--------------|---------|
| D1 | **Content Provider API** | `api/ReaderProvider.kt` | Android 应用间数据共享（`content://providerHost/bookSource/insert`，需 `io.legado.READ_WRITE` 权限）。Klys 无对应实现 |
| D2 | **应用快捷方式（ShortCuts）** | `api/ShortCuts.kt` | 长按图标的动态快捷菜单（继续阅读、发现等） |
| D3 | **快捷设置磁贴** | `service/WebTileService.kt` | 下拉通知栏磁贴，快速开关 Web 服务 |
| D4 | **视频悬浮窗播放** | `help/gsyVideo/FloatingPlayer.kt` + `video_layout_floating` | E 用 GSY 播放器子类实现应用内悬浮播放（`openVideoPlayer(url,title,isFloat)`）。Flutter 可用画中画/系统悬浮窗替代，实现成本较高 |
| D5 | **PDF / 压缩包本地导入 + 文件关联** | `ui/association/FileAssociationActivity.kt`、`model/localBook/LocalBook.kt` | Klys `local_import_screen` 仅 txt/epub/umd/mobi/azw，**不支持 PDF 与 zip 压缩包导入**（PDF 阅读器已存在但无入口）；无外部应用"打开方式"文件关联（ACTION_VIEW） |

---

## 三、设计差异项（非缺失，仅记录）

| 项目 | legado-E | legado-Klys | 评价 |
|------|----------|-------------|------|
| JS 引擎 | Rhino（modules/rhino，完整 ES5+ 部分 ES6，同步阻塞模型） | 无头 WebView（V8）+ 迷你求值器降级 | **Klys 方案引擎能力更强**（完整 V8）；桥 API 已对齐 E 的 90%+（ajax/connect/webView/cookie/cache/queryTTF/replaceFont/toURL 等均已实现），差异仅在 A8/A9 两项 |
| 网络栈 | Cronet + OkHttp | dio | 等价 |
| 视频播放 | GSYVideoPlayer（弹幕/悬浮窗/倍速） | video_player | Klys 缺悬浮窗/长按倍速（见 B2/D4） |
| 音频播放 | ExoPlayer + AudioPlayService | audioplayers + FlutterTts | Klys 云 TTS 内置 9 家反超 E |
| 段评（ReviewRule） | 实体存在但**序列化被写死返回 null**（功能已禁用） | 同样保留字段 | E 实际已废弃，非缺失 |
| SharedJsScope（jsLib 共享作用域） | Rhino prototype 链 | 每源独立求值 | 设计差异，功能可用 |
| 漫画颜色滤镜 | RGBA+L 五通道自定义 | 灰度 + 墨水屏矩阵 | Klys 覆盖主要场景 |
| 阅读页眉页脚 | ReadTipConfig 六槽位枚举 | header/footer 字符串 + FooterSlot | 等价实现 |

---

## 四、Klys 已覆盖但易误判为缺失的项（抽查记录）

为避免误报，以下 E 功能经代码核对**确认 Klys 已实现**：内容编辑、生效替换、重新分段、删除注音/标题标签、简繁转换、自动阅读、章节换源、书源变量设置、TTS 引擎选择/HTTP TTS 编辑、朗读定时、音频跳过片头片尾、漫画墨水屏/灰度/缩放、RSS 收藏/排序/订阅、全文搜索、键盘助手、主题管理、二维码分享、OPDS、远程书籍、备份加密、自动备份、应用更新、崩溃日志、本地密码锁、隐私政策、阅读统计、字典查词、EPUB/UMD/MOBI 解析、Web 服务（Klys 为 E 超集，含 searchBookMulti/refreshToc 等）。

---

## 五、实现计划（本次完成）

按优先级落地顺序（均在 `/workspace/legado-Klys` 工作副本实施）：

1. **A8/A9**：JS 桥补 `downloadFile`、`get7zStringContent`/`getRarStringContent`（桥文件 + Dart 侧文件操作）
2. **A7**：`exploreUrl` JSON 数组 + `@js:` 动态分类解析
3. **A1**：书源检测（CheckSourceConfig + 检测引擎 + 管理页入口 + 失效分组 + 响应时间）
4. **A2**：搜索范围（分组/单源，含选择弹窗）
5. **A3**：验证码识别对话框 + JS 桥打通
6. **A4**：在线导入界面 + 深链扩展为 7 类
7. **A5/A6/A10**：导出增强 + 书签导出 + 书籍上传 WebDAV
8. **B1**：本地 TXT 长章节拆分
9. **B2**：视频长按倍速 + 自动全屏配置
10. **B4**：网络状态监听（Dart 侧，零新依赖）
11. **C2**：直链上传
12. **C1/D5**：旧版数据迁移探针 + PDF/压缩包导入 + 文件关联

> D1–D4（Content Provider / 快捷方式 / 磁贴 / 悬浮窗）为 Android 平台深度集成项，需在 Flutter 侧编写原生 Kotlin 模块。本次在报告与代码注释中保留设计说明，并按 D5 的文件关联方式补齐可 Flutter 化的部分。
