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
