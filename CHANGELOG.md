# 更新日志

## v3.30.0（真实 JS 引擎 / 书源全链路打通 / 一键调试 / Web 服务）
- **真实 JavaScript 引擎（核心）**：新增基于无头 WebView(V8) 的 legado 兼容运行时与桥接层，支持现代 JS（模板字符串、let/const、解构、async/Promise、`with(JavaImporter)`、jsLib、loginUrl），并实现 `java.ajax`（同步 XHR，原生接管绕过跨域）、`java.put/get`、`java.base64/hexEncode/Decode`、`java.startBrowser(Await)` 网页登录回收 Cookie、`source.getVariable/setVariable/getLoginInfo(Map)`、`cookie.getCookie/getKey/setCookie/removeCookie`、`cache`、设备号/UA 等；书源变量、登录信息、跨阶段 KV、Cookie 全部持久化。旧迷你求值器作为不可用平台的回退保留。
- **书源能力对齐原版**：searchUrl/exploreUrl/ruleBookInfo(init)/ruleToc/ruleContent 全阶段支持完整 `<js>`、“前置 `<js>` + 后缀 JSONPath/CSS”、`{{$.x}}` mustache、`@js:`、`URL,{options}`、`data:;base64,<状态>,{选项}` 书址（如大灰狼融合 VIP5.0 的 qingtian/qingtian2/qingtian3）、十六进制响应（非 hex 明文安全原样返回）、图片正文(imageStyle=full)。修复“搜索一搜就空”——根因是 URL 阶段此前完全不执行 JS，把 `<js>` 字面量当网址请求。
- **书源登录重做**：解析 `loginUi` 动态生成 text/password/button 表单，先求值 `loginUrl` 定义 login/register/logout 等函数，按钮以“字段名→值”为 result 求值，支持 ajax 登录与 `startBrowserAwait` 网页登录回收 Cookie；URL 型 loginUrl 直接开网页；登录后刷新书源变量。
- **调试改为原版一键全链路**：只保留一个“搜索内容”输入框，点击后顺序跑 搜索→详情→目录→第一章正文，分级彩色日志并附带每步网络/JS 明细。
- **书源编辑保存后**自动丢弃旧 JS 运行时上下文，jsLib/loginUrl/规则改动即时生效；阅读、详情、书架、本地搜书等所有 getToc/getContent 调用补传 book/chapter 上下文。
- **Web 服务套用 web-yuedu3**：内置其 Vue 构建产物（assets/web），按 legado 兼容契约实现 `/getBookshelf`、`/getChapterList?url=`、`/getBookContent?url=&index=`，书架/目录/正文在本地无缓存时实时用书源抓取并回写缓存，浏览器可直接在线阅读。
- **订阅源（RSS）全链路打通 / 界面重做**：把无头 WebView JS 运行时从书源泛化到订阅源（抽出最小接口 `JsSource`，书源/订阅源各自实现）。
  - 支持 `data:` 逻辑源（如“慕এ~”）、`@js:`/`<js>`/`{{...}}` 的文章列表与正文、`@js` 请求头（动态 `Authorization` 等）、`sortUrl` 分类（`名称::URL`，URL 内 mustache 实时求值）、`loginUi`/`loginUrl` 登录（按钮、网页登录回收 Cookie）、`variableComment` 等。
  - **AES 加解密**：在运行时内注入 aes-js（MIT），桥接实现 `java.aesBase64DecodeToString/EncodeToString/aesDecode/Encode`（ECB/CBC + PKCS7，同步语义），UTF-8 统一走 TextEncoder/Decoder；已用 Node 以 node:crypto 为独立基准交叉验证 193 组向量（含 FIPS-197、短 key 补零、块边界、emoji）。
  - 新建「订阅文章列表页」（进入即拉取、分类切换、缩略图、已读/未读、下拉刷新、失败重试并落库）与「订阅源登录页」；重写「阅读页」，ruleContent 实时计算，HTML 正文用 WebView 渲染、纯文本保留字号调节；订阅源点击直达文章列表，长按菜单新增“登录”；编辑保存后丢弃旧运行时。
  - rss_sources 表补 `variable`、`enabledCookieJar` 列，rss_articles 表补 `image`、`content` 列（含老库迁移）。
- 已知限制：iOS 下 WebView 无法拦截 https 的 XHR（书源内 ajax 可能受跨域限制，Android 正常）；沙箱无安卓设备，WebView V8 真机行为（同步 XHR、网页登录回收 Cookie、headless 生命周期、HTML 渲染）未能端到端，仅以 Node 向量与 Dart 伪运行时验证编排；`createSymmetricCrypto`(AES 工厂) 原生侧仍抛错（源内 AES 已由注入的 aes-js 支持，书源自动登录回退 putLoginInfo）；`java.connect` 响应头未回填；RSS `articleStyle`(0/1/2) 未细分，正文按“是否 HTML”自动选择 WebView/文本。

## v3.29.0（全 App 界面走查与缺陷修复）
对书架、发现、订阅、我的、首页、搜索、书源管理/详情/调试、书籍详情/目录/换源/换封面及各子菜单做了一次系统性走查，修复“假弹窗/只提示不执行/按钮无响应/表单不保存/设置不生效”类问题：
- **发现（致命修复）**：原实现选中分类后未清空分类列表，构建逻辑又永远优先渲染分类，导致发现的书籍**永远不显示**。重构为「选源 → 选分类 → 书籍列表」三级视图，支持返回、单分类源直达、分页加载、失败重试、下拉刷新。
  - 「分类管理」由假弹窗改为真实的分类显示/隐藏（按书源持久化，至少保留一个可见分类）。
  - 「筛选」由四个无响应静态项改为可勾选的 书名/作者/简介/分类 过滤字段，对当前分类实时过滤。
  - 「排序」由无响应选项改为可用的 默认/名称/作者/最新章节 排序。
  - 修复书源切换器用 enabledExplore 硬过滤、与发现源加载口径不一致可能列空的问题，统一为“已启用且配置了发现地址”。
- **订阅**：订阅源卡片补上点击进入（原仅能长按）；「查看文章」与卡片点击现按该订阅源过滤文章，顶部显示过滤条并可一键回到全部文章；刷新提示把抓取总数误称为“新文章”的措辞更正。
- **换封面（数据丢失修复）**：原保存时新建仅含少量字段的 Book 整体覆盖，会清空阅读进度、目录地址、分组等；改为就地更新并写入正确的 customCoverUrl 字段，「恢复默认封面」真正生效，保存后同步书架。
- **书源管理**：「分组管理-新建分组」原只弹“已创建”提示却不保存任何内容，改为对既有分组的重命名（级联更新该组全部书源）与解散，并说明新建分组的正确入口；书源「登录」补存密码（loginPwd，且重复保存不再累积旧变量）。
- **书源调试**：发现调试原忽略输入框 URL、固定调用无参发现，改为按输入的单分类地址真实调试，默认填入首个发现地址；修复搜索结果简介为空时的空指针。
- **搜索**：修复书源筛选弹层「全选」实际执行清空的反逻辑，新增「重置」，确定按钮显示已选数量。
- **首页**：最近阅读「更多」由空回调改为打开阅读记录页；首页模块管理补上「关联发现书源」配置（原新增模块无法关联、首页点击仅提示未配置），支持查看/更换/清除关联。
- **书籍详情**：封面优先使用自定义封面（与书架一致）；清除缓存改用章节真实 index（含卷章时不再错位清错）；更新书籍在缺书源/缺目录地址时给出明确反馈并自动补全目录地址。
- **换源**：换源成功后清除旧源已失效的目录与缓存章节、重置阅读进度，阅读页按新源重新拉取目录，避免章节 URL 错乱。
- 统一版本号至 v3.29.0（pubspec、关于、页脚、检查更新、备份元数据）；Web 服务说明弹窗的设备地址由硬编码 192.168.1.100 改为显示实际局域网 IP。

## v3.28.0（联网智能规则补全 + RSS 编辑/规则生效 + 书架补全）
- 书源编辑「规则补全」由本地占位升级为**联网智能推导**（新增 lib/help/source/rule_auto_completer.dart）：
  - 真实抓取搜索/发现页，通过“同标签直接子元素 + 链接去重率 + 文本量 + 最深叶子优先 + 内层不再含同构块”打分识别重复列表块，生成带稳定 class/祖先上下文、可被引擎直接消费的 `@css:` 列表规则
  - 条目内自动推导 书名/详情链接/封面（含 data-original、data-src 懒加载）/作者/分类/最新章节/字数/简介，并做命中率(support)校验；作者、分类的“作者：/分类：”前缀自动追加正则去除
  - 详情→目录→首章正文**链式推导**：详情页识别 h1 书名/封面/简介/目录链接，目录页识别重复章节链接（含 dd/li 包裹），正文页按文本量、class/id 提示与 `<p>` 占比选出正文容器并输出标题/下一页；JSON 接口递归定位“元素为 Map 的列表”并按 key 别名映射，输出 `$.a.b[*]` 路径
  - 书源 URL 未填时由搜索/发现地址推导站点基址；带进度弹窗、**只填空规则不覆盖已填**，失败自动回退原本地补全
  - 引擎新增编辑期方法 editFetch（应用书源标志/URL 模板/请求头/Cookie/编码后抓取）、resolveEditUrl、firstExploreUrlOf，并让书源级 charset 全局生效
- RSS 源编辑与解析双重修复：
  - rss_service.dart 重写：bytes 抓取 + utf8/gbk/big5 解码 + 自定义请求头；**此前完全被忽略的 ruleArticles/ruleTitle/ruleLink/ruleDescription/rulePubDate 现真正生效**，支持 ruleNextPage 翻页（最多 5 页、按 link 去重），标准 RSS2.0/Atom/通用 HTML 兜底保留
  - RSS 源编辑页整体重做为与书源编辑同款 MD3 卡片式（基本/起始/列表/WebView 四 Tab + 底部全屏多行编辑器 + 快捷片段 chip + 测试/保存/更多 + 规则补全 + 未保存确认）
- 书架板块补全（配置页此前约 30 项设置大多“只存不生效”）：
  - 布局选择由仅“列表/网格”扩为与实际一致的 5 种（详细列表/紧凑列表/三列网格/紧凑网格/大封面），网格列数、列表封面宽度、封面阴影、标题行数/居中/紧凑、分割线、紧凑详情等全部实时生效；布局与当前分组**持久化**（重启保留）
  - 排序与配置页打通（最近阅读/书名/作者/添加时间/手动 + 升降序，双向持久化），手动排序置顶在前；显示最新章节/简介(行数)/标签/最后更新时间按开关渲染
  - 角标落地：未读章节数角标/红点、分组书籍数量；分组支持“折叠(顶部标签)/平铺(分区)”两种样式、隐藏空分组、隐藏整个分组 Tab
  - 一键更新接入更新数量上限、canUpdate 过滤，并回报检查数/更新数
  - 修复“添加书签”为假动作（原仅弹数量）：现按当前阅读章节/位置真实写入书签并截取正文摘要；修复点击搜索图标因空格关键字导致空结果
  - 分组管理打通两套数据：与书籍实际分组合并，支持重命名（级联更新该组书籍）、删除解散（书籍回到未分组）、显隐、拖拽排序、显示书籍数；修复显隐/排序保存因 insert 非 upsert 产生重复分组行
  - 移动到分组支持选择已有分组；封面优先使用自定义封面 customCoverUrl；导出文件名去除非法字符
- 测试：新增智能推导纯逻辑测试、本地 HTTP 端到端（列表→详情→目录→正文）、RSS 自定义规则+翻页端到端、书架分组纯逻辑与列表/网格/平铺/角标/配置 widget 测试；flutter analyze 维持 0 error / 0 warning，测试由 9 项增至 26 项全部通过

## v3.27.0（书源编辑重做 + 数据层一致性修复 + AI 助手）
- 书源编辑页对齐 legado-with-MD3 重做：
  - 由“内联单行输入框”改为“字段卡片预览 + 点击弹出底部多行编辑器”，规则字段支持光标处快捷插入 `@text/@href/@src/class./id./tag./$./{{}}/<js></js>/@js:/@Regex:` 等片段
  - 补齐此前缺失字段：并发率 concurrentRate、自动保存 Cookie(enabledCookieJar)、编码 charset、书源变量 variable、搜索权重 weight、排序编号 customOrder、发现分类 exploreScreen、评论/图片规则 JSON；模型补 concurrentRate/enabledCookieJar 全量序列化
  - 顶栏新增 调试 / 保存 / 更多；更多菜单新增 登录(WebView)、保存并搜索、清除 Cookie、规则补全、设置书源变量、复制、粘贴、分享、帮助
  - 修复“调试”使用空白书源导致规则全部丢失，改为直接用当前表单内容调试；修复 checkKeyWord 被错误塞进 ruleSearch；移除空方法与重复载入逻辑；新增未保存返回二次确认；粘贴兼容数组/单对象
- 数据层致命一致性修复：books/book_sources/bookmarks/replace_rules/rss_sources/rss_articles/txt_toc_rules 七张表的建表列与各模型 toMap 写入键大面积不一致（缺列会令 sqflite 写入直接抛 “no column named …”），导致加入书架、保存书源/RSS源、存书签、存替换/TXT目录规则等运行期崩溃；统一补全列、数据库 v7→v8 逐列 ALTER 迁移（可重入、不丢数据），并修正 books/bookmarks/replace_rules/txt_toc_rules 的过期排序列与 RSS 已读/星标双列不同步
- 完成 AI 聊天（原为“功能开发中”占位）：新增 AiChatService（OpenAI 兼容 /chat/completions，配置本地持久化，未配置时离线读书助手兜底）与 AiChatScreen（气泡对话、快捷提问、接口设置、清空），“我的-AI聊天”正式接通
- 书源引擎落地两个书源级能力：enabledCookieJar 开启时 Cookie 跨启动持久化（落库并在请求前恢复），concurrentRate 并发率节流（支持 `毫秒` 与 `n/毫秒`）
- 适配新版 Flutter：CardTheme/DialogTheme/TabBarTheme 迁移为对应 *ThemeData，修复当前稳定版下的 3 处硬编译错误；修正正文递归 nextContentUrl 未 await 的告警
- analyze 维持 0 error / 0 warning（剩余为与既有代码一致的风格 info），全部单元测试通过

## v3.26.9（功能完整性审计与运行期修复）
- 修复章节表致命缺陷：`book_chapters` 建表用保留字 `"index"` 且缺 start_pos/end_pos/variable 列，与 BookChapter.toMap 写入键不一致，导致本地导入(TXT/EPUB/UMD/MOBI)、离线缓存、保存章节全部运行期崩溃；统一为 chapter_index 列并补齐字段，数据库升级 v6→v7 并自动迁移旧数据
- 修复备份崩溃：默认备份直接把 ReadRecord 对象交给 jsonEncode 会抛异常（无 toJson），改为 toMap 并补全阅读记录的恢复
- 修复缓存管理：清除单本书缓存误调用“清空全部”，且原方法删错表（删 caches 而非章节正文）；新增按书清除 clearBookChapterContent，清空改为置空 book_chapters.content
- 书源引擎接入 Cookie 管理器：请求自动携带同域 Cookie、响应回存 Set-Cookie，修复需要会话接力的书源
- 接通此前“只存不生效”的功能：
  - 实验室 5 个开关全部落地：正文自由选择复制、墨水屏去动画高对比主题、分页估算诊断、加速下载(预缓存并发)、打开应用自动 WebDAV 同步(新增 AutoSyncService)
  - 字典规则（正则替换词典）新增 ContentDictService 并在正文显示前应用
  - 高亮标签规则新增 HighlightService，命中片段以彩色 Text.rich 高亮
  - 下载缓存“预下载章节数”落地：阅读时后台顺序/并发预缓存后续 N 章
  - “模拟阅读”落地：进入阅读页按设置自动翻页；移除无对应子系统的“漫画阅读”空开关
  - WebDAV“同步阅读进度”落地：上传备份时一并上传进度（新增 getAllBookProgress）
  - 首页模块卡片由仅弹提示改为跳转到真实发现书籍列表（新增 ExploreBooksScreen，支持翻页/加入/阅读）
- 移除查询不存在表 search_books 的潜在崩溃死方法 getSearchBooks
- analyze 维持 0 error / 0 warning，9 项单元测试全部通过

## v3.26.8（补全与修复）
- 修复 23 处导致无法编译的错误：重复的 ReadRecord 类型、缺失模型导出、crypto 命名遮蔽、BookChapter 缺 toJson、常量类型错误等
- 重写书源规则引擎，新增统一规则管线 rule_pipeline.dart：
  - 真正接入此前写好但未被使用的 CSS / XPath / JSONPath / 正则 / JS 选择器（原 XPath 分支实际退化为默认规则）
  - 支持原版组合语法：`||`(或)、`&&`(链式)、`@@`(取全部)、`##正则##替换`/`###只取匹配`、结尾 `@js:`、整段 `<js>`、`{{}}` 模板
  - 支持 `@css:/@xpath:/@json:` 前缀、`@text/@html/@href/属性名` 取值后缀
  - 默认 JSoup 语法 class./tag./id./text./children + `.N`/`!N`/`[区间]` 索引
  - XPath 谓词同时支持单/双引号
- 抓取链路补全：目录 nextTocUrl 翻页、正文 nextContentUrl 分页拼接、图片正文保留、相对 URL 解析、发现分类 `:::`/`&&&` 解析对齐
- 清理重复/未用导入与重复 Map 键；新增规则管线单元测试 9 项，全部通过；flutter analyze 0 error / 0 warning
- 二轮清理：移除全部 35 个 warning（非空字段冗余 ??、未用私有字段/死方法、弃用导入、未用循环变量），并让 TTS 语言/引擎设置真正生效

## v3.26.7
- 完整复刻 Legado MD3 风格
- 书架：5种布局/6种排序/分组/多选/书籍菜单
- 书源：网络/剪贴板/本地导入/编辑/调试/校验/域名分组
- 阅读：5Tab设置/38项配置/书签/目录/搜索/翻译/内容编辑
- 发现：书源切换/分类/筛选/排序
- 搜索：多源并发/结果菜单/书源筛选
- RSS：订阅源/文章/收藏
- Web服务：HTTP REST API + WebSocket
- WebDAV：备份/恢复/同步
- 云TTS：8家提供商
- 本地书籍：TXT/EPUB/MOBI/PDF/UMD
- 漫画阅读：连续滚动/翻页
- 角色系统：列表/详情/关系网
- 主题：5种预设/自定义管理
- Clean Architecture 架构
