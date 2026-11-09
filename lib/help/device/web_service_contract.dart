/// 批次 6 · Web 服务原生边界的纯 Dart 契约（零平台依赖，便于单元回归）。
///
/// 渠道 ID / 通知 ID / 意图常量 / 多 IP 通知文本。
/// 真正的原生能力（前台服务 / 通知渠道 / WakeLock / WifiLock）见
/// `web_service_boundary.dart` 顶部的「Flutter 无等价能力」标注。
/// 本文件独立成库，避免测试因 MethodChannel / app_database 的传递依赖
/// 被并行编辑中的其它模块阻塞。
library;

/// 对齐 `constant/AppConst.kt:19-21`。
class WebChannelIds {
  static const String download = 'channel_download';
  static const String readAloud = 'channel_read_aloud';
  static const String web = 'channel_web';
}

/// 对齐 `constant/NotificationId.kt:9-18`（统一规划，避免通知互相覆盖）。
class WebNotificationIds {
  static const int readAloudService = 101;
  static const int audioPlayService = 102;
  static const int cacheBookService = 103;
  static const int exportBookService = 104;
  static const int webService = 105;
  static const int downloadService = 106;
  static const int checkSourceService = 107;
  static const int videoPlayService = 108;
  static const int download = 10000;
  static const int exportBook = 201;
}

/// 对齐 `WebService.kt:118` 与 IntentAction 的停止/复制/续期意图。
class WebServiceActions {
  static const String copyHostAddress = 'copyHostAddress';
  static const String stop = 'stop';
  static const String serve = 'serve';
}

/// 把多 IP 地址列表格式化成前台通知文本（对齐 WebService.kt:97-103 的
/// `notificationList.addAll(addressList.map { getString(http_ip, ...) })`，
/// 每个地址一行 `http://<ip>:<port>`）。空列表时返回「网络不可用」占位。
List<String> formatHostAddresses(List<String> addresses, int port) {
  if (addresses.isEmpty) return const <String>['网络不可用'];
  return addresses.map((ip) => 'http://$ip:$port').toList();
}
