/// JS 运行时所需的最小书源/订阅源接口，使同一运行时可服务 BookSource 与 RssSource。
abstract class JsSource {
  /// 逻辑/实际源地址（书源 bookSourceUrl / 订阅源 sourceUrl），可能是 data: 逻辑名
  String get jsUrl;

  /// 源名称
  String get jsName;

  /// http 型源地址（用于相对 URL 解析）；非 http 逻辑源返回空串
  String get jsHttpUrl;

  /// 运行时变量（getVariable/setVariable）
  String? get variable;
  set variable(String? v);

  /// 变量注释（部分源用其 AES 加密存放配置）
  String? get variableComment;

  /// 最近更新时间
  int? get lastUpdateTime;

  String? get jsLib;
  String? get loginUrl;
  String? get header;
  bool get enabledCookieJar;
}
