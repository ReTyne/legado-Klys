/// 轻量 Cookie 管理器：按域名存储，解析 Set-Cookie
class CookieManager {
  static final CookieManager _instance = CookieManager._();
  factory CookieManager() => _instance;
  CookieManager._();

  // host -> (name -> value)
  final Map<String, Map<String, String>> _store = {};

  /// 从响应头解析并保存 cookie
  void saveFromResponse(String url, List<String>? setCookies) {
    if (setCookies == null) return;
    final host = Uri.parse(url).host;
    final jar = _store.putIfAbsent(host, () => {});
    for (final raw in setCookies) {
      final pair = raw.split(';').first;
      final idx = pair.indexOf('=');
      if (idx > 0) {
        jar[pair.substring(0, idx).trim()] = pair.substring(idx + 1).trim();
      }
    }
  }

  /// 生成请求 Cookie 头
  String? cookieHeader(String url) {
    final host = Uri.parse(url).host;
    final jar = _store[host] ?? _matchDomain(host);
    if (jar == null || jar.isEmpty) return null;
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Map<String, String>? _matchDomain(String host) {
    for (final entry in _store.entries) {
      if (host.endsWith(entry.key)) return entry.value;
    }
    return null;
  }

  void clear() => _store.clear();
  void removeHost(String host) => _store.remove(host);
}
