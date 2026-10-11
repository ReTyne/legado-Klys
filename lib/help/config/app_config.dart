import '../../constant/app_constants.dart';

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
