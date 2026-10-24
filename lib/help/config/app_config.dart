import 'package:shared_preferences/shared_preferences.dart';

/// 全局应用配置（运行时常量与特性开关）
class AppConfig {
  AppConfig._();

  static const bool debug = false;
  static const int connectTimeout = AppConstants.connectTimeout;
  static const int readTimeout = AppConstants.readTimeout;
  static const String appVersion = AppConstants.appVersion;
  static const int webPort = AppConstants.defaultWebPort;

  /// 特性开关
  static const bool enableWebService = true;
  static const bool enableRss = true;
  static const bool enableManga = true;
  static const bool enableAiChat = true; // AI 读书助手（离线兜底 + 可配置 OpenAI 兼容接口）

  /// 本地书籍支持的扩展名
  static const List<String> localBookExt = ['txt', 'epub'];
  static const List<String> archiveExt = ['zip'];
}

/* ===== 由 app_constants.dart 合并 ===== */
/// 应用级常量
class AppConstants {
  AppConstants._();

  static const String appName = 'legado';
  static const String appVersion = '1.0';
  static const int appVersionCode = 1;

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  /// 书源类型
  static const int sourceTypeText = 0;   // 小说
  static const int sourceTypeAudio = 1;  // 音频
  static const int sourceTypeImage = 2;  // 图片/漫画
  static const int sourceTypeFile = 3;   // 文件

  /// 书籍类型
  static const int bookTypeText = 0;
  static const int bookTypeAudio = 1;
  static const int bookTypeImage = 2;
  static const int bookTypeLocal = 3;

  /// 默认 Web 服务端口
  static const int defaultWebPort = 1122;

  /// 请求超时（毫秒）
  static const int connectTimeout = 30000;
  static const int readTimeout = 30000;

  /// 搜索历史最大条数
  static const int maxSearchHistory = 50;
}

/* ===== 持久化全局配置（SharedPreferences）=====
 * 对照 legado-E help/config/AppConfig.kt 的 PreferKey 逐项补齐。
 * 用法：
 *  - 读取：静态 getter（启动时 load 进内存，之后同步读取）；
 *  - 写入：静态 setter（同步改内存 + 异步落盘，UI 可直接赋值后 setState）；
 *  - 启动加载：main() 里已有 SharedPreferences 实例，加一行
 *    `AppConfig.loadFrom(prefs);` 即可；也可随时 `await AppConfig.load();`。
 */
/// 全局持久化配置（键名与 legado-E PreferKey 保持一致，便于配置互通）
class AppPrefs {
  AppPrefs._();

  /* ---------- SharedPreferences 键名 ---------- */
  static const String keyThreadCount = 'threadCount';
  static const String keyPreDownloadNum = 'preDownloadNum';
  static const String keyUserAgent = 'userAgent';
  static const String keyCustomHosts = 'customHosts';
  static const String keyDefaultBookTreeUri = 'defaultBookTreeUri';
  static const String keyProcessText = 'process_text';
  static const String keyBitmapCacheSize = 'bitmapCacheSize';
  static const String keyRecordHeapDump = 'recordHeapDump';
  static const String keyTtsTimer = 'ttsTimer';
  static const String keyExportCharset = 'exportCharset';
  static const String keyExportUseReplace = 'exportUseReplace';
  static const String keyExportNoChapterName = 'exportNoChapterName';
  static const String keyExportPictureFile = 'exportPictureFile';
  static const String keyExportToWebDav = 'exportToWebDav';
  static const String keyParallelExportBook = 'parallelExportBook';
  // 书源校验（legado-E CheckSourceConfig：checkSourceTimeout/wSourceComment/checkDomain/...）
  static const String keyCheckSourceTimeout = 'checkSourceTimeout';
  static const String keyWSourceComment = 'wSourceComment';
  static const String keyCheckDomain = 'checkDomain';
  static const String keyCheckSearch = 'checkSearch';
  static const String keyCheckDiscovery = 'checkDiscovery';
  static const String keyCheckInfo = 'checkInfo';
  static const String keyCheckCategory = 'checkCategory';
  static const String keyCheckContent = 'checkContent';
  // 搜索范围（legado-E AppConfig.searchScope / searchGroup）
  static const String keySearchScope = 'searchScope';
  static const String keySearchGroup = 'searchGroup';
  // 封面（沿用本项目已有键，bookshelf_screen 直接消费，勿改键名）
  static const String keyUseDefaultCover = 'cover_useDefault';
  static const String keyCoverShowName = 'cover_showName';
  static const String keyCoverShowAuthor = 'cover_showAuthor';
  // 主题外观（legado-E pref_config_theme.xml）
  static const String keyTransparentStatusBar = 'transparentStatusBar';
  static const String keyImmNavigationBar = 'immNavigationBar';
  static const String keyBarElevation = 'barElevation';
  static const String keyBackgroundImage = 'backgroundImage';
  static const String keyColorBottomBackground = 'colorBottomBackground';
  // 备份（legado-E pref_config_backup.xml）
  static const String keyWebDavDeviceName = 'webDavDeviceName';
  static const String keyRestoreIgnore = 'restoreIgnore';
  static const String keyOnlyLatestBackup = 'onlyLatestBackup';
  static const String keyAutoCheckNewBackup = 'autoCheckNewBackup';

  /* ---------- 内存缓存（默认值与 legado-E 对齐） ---------- */
  static int _threadCount = 32;
  static int _preDownloadNum = 2;
  static String _userAgent = '';
  static String _customHosts = '';
  static String _defaultBookTreeUri = '';
  static bool _processText = true;
  static int _bitmapCacheSize = 50;
  static bool _recordHeapDump = false;
  static int _ttsTimer = 0;
  static String _exportCharset = 'UTF-8';
  static bool _exportUseReplace = true;
  static bool _exportNoChapterName = false;
  static bool _exportPictureFile = false;
  static bool _exportToWebDav = false;
  static bool _parallelExportBook = false;
  static int _checkSourceTimeout = 180000; // 毫秒
  static bool _wSourceComment = true;
  static bool _checkDomain = false;
  static bool _checkSearch = true;
  static bool _checkDiscovery = true;
  static bool _checkInfo = true;
  static bool _checkCategory = true;
  static bool _checkContent = true;
  static String _searchScope = '';
  static String _searchGroup = '';
  static bool _useDefaultCover = false;
  static bool _coverShowName = true;
  static bool _coverShowAuthor = true;
  static bool _transparentStatusBar = true;
  static bool _immNavigationBar = true;
  static int _barElevation = 0;
  static String _backgroundImage = '';
  static int _colorBottomBackground = 0; // 0 = 未设置（用主题默认色）
  static String _webDavDeviceName = '';
  static List<String> _restoreIgnore = const [];
  static bool _onlyLatestBackup = true;
  static bool _autoCheckNewBackup = true;

  /* ---------- getter ---------- */
  /// 并发线程数（搜索/目录/正文并发上限），默认 32
  static int get threadCount => _threadCount;
  /// 预下载章节数，默认 2
  static int get preDownloadNum => _preDownloadNum;
  /// 全局 UA；为空时返回默认 UA（写入请用 setter，空串表示用默认）
  static String get userAgent =>
      _userAgent.isNotEmpty ? _userAgent : AppConstants.defaultUserAgent;
  /// 自定义 Host 映射原文，每行一条 `host=ip`
  static String get customHosts => _customHosts;
  /// 默认书籍保存目录（本地书籍导入/落盘位置）
  static String get defaultBookTreeUri => _defaultBookTreeUri;
  /// 系统文本处理菜单入口开关。
  /// 说明：Flutter 版暂无 Android Intent.ACTION_PROCESS_TEXT 注册能力，
  /// 该值仅持久化保存，待原生层支持后消费。
  static bool get processText => _processText;
  /// 图片缓存大小（MB），默认 50
  static int get bitmapCacheSize => _bitmapCacheSize;
  /// 性能监测时记录堆转储
  static bool get recordHeapDump => _recordHeapDump;
  /// 朗读定时分钟数（0 = 不定时）
  static int get ttsTimer => _ttsTimer;
  /// 导出编码（gbk / utf-8）
  static String get exportCharset => _exportCharset;
  /// 导出时应用替换净化
  static bool get exportUseReplace => _exportUseReplace;
  /// 导出时不添加章节名
  static bool get exportNoChapterName => _exportNoChapterName;
  /// 导出包含图片
  static bool get exportPictureFile => _exportPictureFile;
  /// 导出到 WebDAV
  static bool get exportToWebDav => _exportToWebDav;
  /// 并发导出多本书
  static bool get parallelExportBook => _parallelExportBook;
  /// 书源校验超时（毫秒），默认 180 秒
  static int get checkSourceTimeout => _checkSourceTimeout;
  /// 校验失败时把错误信息写入书源注释
  static bool get wSourceComment => _wSourceComment;
  /// 校验源地址可访问性（Socket 探测）
  static bool get checkDomain => _checkDomain;
  /// 校验搜索
  static bool get checkSearch => _checkSearch;
  /// 校验发现
  static bool get checkDiscovery => _checkDiscovery;
  /// 校验详情
  static bool get checkInfo => _checkInfo;
  /// 校验目录
  static bool get checkCategory => _checkCategory;
  /// 校验正文
  static bool get checkContent => _checkContent;
  /// 搜索范围原文：空=全部；`分组1,分组2`；`名称::url`=单书源
  static String get searchScope => _searchScope;
  /// 单选分组时的分组名（E: searchGroup）
  static String get searchGroup => _searchGroup;
  /// 无封面时使用默认封面（bookshelf_screen 消费）
  static bool get useDefaultCover => _useDefaultCover;
  /// 封面显示书名（bookshelf_screen 消费）
  static bool get coverShowName => _coverShowName;
  /// 封面显示作者（bookshelf_screen 消费）
  static bool get coverShowAuthor => _coverShowAuthor;
  /// 透明状态栏
  static bool get transparentStatusBar => _transparentStatusBar;
  /// 沉浸式导航栏
  static bool get immNavigationBar => _immNavigationBar;
  /// 顶栏阴影（0-8）
  static int get barElevation => _barElevation;
  /// 书架背景图路径（空 = 不使用）
  static String get backgroundImage => _backgroundImage;
  /// 底部背景色（0 = 未设置，用主题默认）
  static int get colorBottomBackground => _colorBottomBackground;
  /// WebDAV 设备名（标识备份来源设备）
  static String get webDavDeviceName => _webDavDeviceName;
  /// 恢复忽略项（BackupType.name 列表）
  static List<String> get restoreIgnore => _restoreIgnore;
  /// 仅恢复最新备份
  static bool get onlyLatestBackup => _onlyLatestBackup;
  /// 自动检查新备份
  static bool get autoCheckNewBackup => _autoCheckNewBackup;

  /// 自定义 Host 映射解析结果：每行 `host=ip`，非法行忽略
  static Map<String, String> get hostMap {
    final map = <String, String>{};
    for (final line in _customHosts.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final i = t.indexOf('=');
      if (i <= 0 || i == t.length - 1) continue;
      map[t.substring(0, i).trim()] = t.substring(i + 1).trim();
    }
    return map;
  }

  /* ---------- setter（同步改内存 + 异步落盘） ---------- */
  static set threadCount(int v) {
    _threadCount = v.clamp(1, 128);
    _save(keyThreadCount, _threadCount);
  }

  static set preDownloadNum(int v) {
    _preDownloadNum = v.clamp(0, 10);
    _save(keyPreDownloadNum, _preDownloadNum);
  }

  static set userAgent(String v) {
    _userAgent = v.trim();
    _save(keyUserAgent, _userAgent);
  }

  static set customHosts(String v) {
    _customHosts = v;
    _save(keyCustomHosts, _customHosts);
  }

  static set defaultBookTreeUri(String v) {
    _defaultBookTreeUri = v.trim();
    if (_defaultBookTreeUri.isEmpty) {
      _remove(keyDefaultBookTreeUri);
    } else {
      _save(keyDefaultBookTreeUri, _defaultBookTreeUri);
    }
  }

  static set processText(bool v) {
    _processText = v;
    _save(keyProcessText, _processText);
  }

  static set bitmapCacheSize(int v) {
    _bitmapCacheSize = v.clamp(10, 512);
    _save(keyBitmapCacheSize, _bitmapCacheSize);
  }

  static set recordHeapDump(bool v) {
    _recordHeapDump = v;
    _save(keyRecordHeapDump, _recordHeapDump);
  }

  static set ttsTimer(int v) {
    _ttsTimer = v.clamp(0, 600);
    _save(keyTtsTimer, _ttsTimer);
  }

  static set exportCharset(String v) {
    _exportCharset = v;
    _save(keyExportCharset, _exportCharset);
  }

  static set exportUseReplace(bool v) {
    _exportUseReplace = v;
    _save(keyExportUseReplace, _exportUseReplace);
  }

  static set exportNoChapterName(bool v) {
    _exportNoChapterName = v;
    _save(keyExportNoChapterName, _exportNoChapterName);
  }

  static set exportPictureFile(bool v) {
    _exportPictureFile = v;
    _save(keyExportPictureFile, _exportPictureFile);
  }

  static set exportToWebDav(bool v) {
    _exportToWebDav = v;
    _save(keyExportToWebDav, _exportToWebDav);
  }

  static set parallelExportBook(bool v) {
    _parallelExportBook = v;
    _save(keyParallelExportBook, _parallelExportBook);
  }

  static set checkSourceTimeout(int v) {
    _checkSourceTimeout = v.clamp(1000, 600000);
    _save(keyCheckSourceTimeout, _checkSourceTimeout);
  }

  static set wSourceComment(bool v) {
    _wSourceComment = v;
    _save(keyWSourceComment, _wSourceComment);
  }

  static set checkDomain(bool v) {
    _checkDomain = v;
    _save(keyCheckDomain, _checkDomain);
  }

  static set checkSearch(bool v) {
    _checkSearch = v;
    _save(keyCheckSearch, _checkSearch);
  }

  static set checkDiscovery(bool v) {
    _checkDiscovery = v;
    _save(keyCheckDiscovery, _checkDiscovery);
  }

  static set checkInfo(bool v) {
    _checkInfo = v;
    _save(keyCheckInfo, _checkInfo);
  }

  static set checkCategory(bool v) {
    _checkCategory = v;
    _save(keyCheckCategory, _checkCategory);
  }

  static set checkContent(bool v) {
    _checkContent = v;
    _save(keyCheckContent, _checkContent);
  }

  static set searchScope(String v) {
    _searchScope = v;
    _save(keySearchScope, _searchScope);
  }

  static set searchGroup(String v) {
    _searchGroup = v;
    _save(keySearchGroup, _searchGroup);
  }

  static set useDefaultCover(bool v) {
    _useDefaultCover = v;
    _save(keyUseDefaultCover, _useDefaultCover);
  }

  static set coverShowName(bool v) {
    _coverShowName = v;
    _save(keyCoverShowName, _coverShowName);
  }

  static set coverShowAuthor(bool v) {
    _coverShowAuthor = v;
    _save(keyCoverShowAuthor, _coverShowAuthor);
  }

  static set transparentStatusBar(bool v) {
    _transparentStatusBar = v;
    _save(keyTransparentStatusBar, _transparentStatusBar);
  }

  static set immNavigationBar(bool v) {
    _immNavigationBar = v;
    _save(keyImmNavigationBar, _immNavigationBar);
  }

  static set barElevation(int v) {
    _barElevation = v.clamp(0, 8);
    _save(keyBarElevation, _barElevation);
  }

  static set backgroundImage(String v) {
    _backgroundImage = v;
    if (_backgroundImage.isEmpty) {
      _remove(keyBackgroundImage);
    } else {
      _save(keyBackgroundImage, _backgroundImage);
    }
  }

  static set colorBottomBackground(int v) {
    _colorBottomBackground = v;
    if (_colorBottomBackground == 0) {
      _remove(keyColorBottomBackground);
    } else {
      _save(keyColorBottomBackground, _colorBottomBackground);
    }
  }

  static set webDavDeviceName(String v) {
    _webDavDeviceName = v.trim();
    _save(keyWebDavDeviceName, _webDavDeviceName);
  }

  static set restoreIgnore(List<String> v) {
    _restoreIgnore = List.unmodifiable(v);
    _save(keyRestoreIgnore, _restoreIgnore);
  }

  static set onlyLatestBackup(bool v) {
    _onlyLatestBackup = v;
    _save(keyOnlyLatestBackup, _onlyLatestBackup);
  }

  static set autoCheckNewBackup(bool v) {
    _autoCheckNewBackup = v;
    _save(keyAutoCheckNewBackup, _autoCheckNewBackup);
  }

  /* ---------- 加载 ---------- */
  /// 自行获取 SharedPreferences 并加载（可重复调用刷新）
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    loadFrom(p);
  }

  /// 用已有 SharedPreferences 实例同步加载（main() 启动时调用）
  static void loadFrom(SharedPreferences p) {
    _threadCount = (p.getInt(keyThreadCount) ?? 32).clamp(1, 128);
    _preDownloadNum = (p.getInt(keyPreDownloadNum) ?? 2).clamp(0, 10);
    _userAgent = p.getString(keyUserAgent) ?? '';
    _customHosts = p.getString(keyCustomHosts) ?? '';
    _defaultBookTreeUri = p.getString(keyDefaultBookTreeUri) ?? '';
    _processText = p.getBool(keyProcessText) ?? true;
    _bitmapCacheSize = (p.getInt(keyBitmapCacheSize) ?? 50).clamp(10, 512);
    _recordHeapDump = p.getBool(keyRecordHeapDump) ?? false;
    _ttsTimer = (p.getInt(keyTtsTimer) ?? 0).clamp(0, 600);
    _exportCharset = p.getString(keyExportCharset) ?? 'UTF-8';
    _exportUseReplace = p.getBool(keyExportUseReplace) ?? true;
    _exportNoChapterName = p.getBool(keyExportNoChapterName) ?? false;
    _exportPictureFile = p.getBool(keyExportPictureFile) ?? false;
    _exportToWebDav = p.getBool(keyExportToWebDav) ?? false;
    _parallelExportBook = p.getBool(keyParallelExportBook) ?? false;
    _checkSourceTimeout = (p.getInt(keyCheckSourceTimeout) ?? 180000).clamp(1000, 600000);
    _wSourceComment = p.getBool(keyWSourceComment) ?? true;
    _checkDomain = p.getBool(keyCheckDomain) ?? false;
    _checkSearch = p.getBool(keyCheckSearch) ?? true;
    _checkDiscovery = p.getBool(keyCheckDiscovery) ?? true;
    _checkInfo = p.getBool(keyCheckInfo) ?? true;
    _checkCategory = p.getBool(keyCheckCategory) ?? true;
    _checkContent = p.getBool(keyCheckContent) ?? true;
    _searchScope = p.getString(keySearchScope) ?? '';
    _searchGroup = p.getString(keySearchGroup) ?? '';
    _useDefaultCover = p.getBool(keyUseDefaultCover) ?? false;
    _coverShowName = p.getBool(keyCoverShowName) ?? true;
    _coverShowAuthor = p.getBool(keyCoverShowAuthor) ?? true;
    _transparentStatusBar = p.getBool(keyTransparentStatusBar) ?? true;
    _immNavigationBar = p.getBool(keyImmNavigationBar) ?? true;
    _barElevation = (p.getInt(keyBarElevation) ?? 0).clamp(0, 8);
    _backgroundImage = p.getString(keyBackgroundImage) ?? '';
    _colorBottomBackground = p.getInt(keyColorBottomBackground) ?? 0;
    _webDavDeviceName = p.getString(keyWebDavDeviceName) ?? '';
    _restoreIgnore = p.getStringList(keyRestoreIgnore) ?? const [];
    _onlyLatestBackup = p.getBool(keyOnlyLatestBackup) ?? true;
    _autoCheckNewBackup = p.getBool(keyAutoCheckNewBackup) ?? true;
  }

  /* ---------- 内部落盘 ---------- */
  static Future<void> _save(String key, Object v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool) {
      await p.setBool(key, v);
    } else if (v is int) {
      await p.setInt(key, v);
    } else if (v is String) {
      await p.setString(key, v);
    } else if (v is List<String>) {
      await p.setStringList(key, v);
    }
  }

  static Future<void> _remove(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(key);
  }
}
