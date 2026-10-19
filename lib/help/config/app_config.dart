


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

  static const String appName = 'Legado';
  static const String appVersion = '3.30.0';
  static const int appVersionCode = 32607;

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

