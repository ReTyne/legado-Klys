import 'dart:async';
import 'dart:convert';

import 'package:legado_md3/utils/cookie_util.dart' as cu;
import 'package:shared_preferences/shared_preferences.dart';

/// Cookie 管理器（进程内单例）：以 eTLD+1 为域键，区分会话 / 持久两层，
/// 解析 Set-Cookie 属性并按 path / domain / secure 规则筛选请求 Cookie 头。
class CookieManager {
  static final CookieManager _instance = CookieManager._();
  factory CookieManager() => _instance;
  CookieManager._() {
    _loaded = _loadPersisted();
  }

  /// 持久层在 SharedPreferences 中的存储键（JSON 序列化）。
  static const String persistentPrefsKey = 'cookie_manager.persistent.v1';

  /// 每个域键的 Cookie 头字节上限，超限淘汰插入最早的条目。
  static const int maxCookieBytes = 4096;

  // 域键 -> (name -> cookie)
  // 会话层：无 expires / max-age，仅内存、进程内有效。
  final Map<String, Map<String, _Cookie>> _session = {};
  // 持久层：带 expires / max-age，落盘到 SharedPreferences。
  final Map<String, Map<String, _Cookie>> _persistent = {};

  int _seq = 0;
  Future<void>? _loaded;

  // ===================================================================
  // 既有公开 API（保持签名与语义）
  // ===================================================================

  /// 从响应头解析并保存 cookie。
  void saveFromResponse(String url, List<String>? setCookies) {
    if (setCookies == null) return;
    final defaultPath = cu.defaultCookiePath(url);
    for (final raw in setCookies) {
      final sc = cu.parseSetCookie(raw, defaultPath: defaultPath);
      if (sc == null) continue;
      _put(url, sc);
    }
  }

  /// 生成请求 Cookie 头（合并会话层与持久层，按属性筛选）。
  String? cookieHeader(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final reqPath = uri.path.isEmpty ? '/' : uri.path;
    final secureRequest = uri.scheme.toLowerCase() == 'https';
    final now = DateTime.now().toUtc();
    final selected = <String, _Cookie>{};

    for (final layer in [_persistent, _session]) {
      for (final entry in layer.entries) {
        if (!_domainKeyMatches(host, entry.key)) continue;
        for (final c in entry.value.values) {
          if (c.host != null && !cu.cookieDomainMatch(host, c.host)) continue;
          if (c.isExpired(now)) continue;
          if (c.secure && !secureRequest) continue;
          if (!cu.cookiePathMatch(reqPath, c.path)) continue;
          final prev = selected[c.name];
          // 同名以 path 更具体者优先
          if (prev == null || c.path.length >= prev.path.length) {
            selected[c.name] = c;
          }
        }
      }
    }
    if (selected.isEmpty) return null;
    final list = selected.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list.map((c) => '${c.name}=${c.value}').join('; ');
  }

  void clear() {
    _session.clear();
    _persistent.clear();
    _seq = 0;
    _schedulePersist();
  }

  /// 移除某主机对应的 cookie；[host] 可为完整 URL 或纯主机名。
  void removeHost(String host) {
    _session.remove(host);
    _persistent.remove(host);
    final key = cu.getSubDomain(host.contains('://') ? host : 'http://$host');
    _session.remove(key);
    _persistent.remove(key);
    _schedulePersist();
  }

  /// 按名称移除指定 URL 域键下的单个 cookie（会话层与持久层同时清理）。
  void removeCookie(String url, String key) {
    final domainKey = _domainKey(url);
    _session[domainKey]?.remove(key);
    _persistent[domainKey]?.remove(key);
    _schedulePersist();
  }

  // ===================================================================
  // 新增能力
  // ===================================================================

  /// 合并式替换：把 cookie 串解析后写入当前域，新值覆盖同名旧值，其余保留。
  void replaceCookie(String url, String cookie) {
    final key = _domainKey(url);
    final path = cu.defaultCookiePath(url);
    final now = DateTime.now().toUtc();
    for (final e in cu.cookieToMap(cookie).entries) {
      _putAt(
        key,
        _Cookie(
          e.key,
          e.value,
          path: path,
          host: null,
          expires: null,
          maxAge: null,
          secure: false,
          httpOnly: false,
          createdAt: now,
          order: _seq++,
        ),
      );
    }
  }

  /// `a=1; b=2` Cookie 头 → map。
  Map<String, String> cookieToMap(String cookie) => cu.cookieToMap(cookie);

  /// map → `a=1; b=2` Cookie 头。
  String mapToCookie(Map<String, String> map) => cu.mapToCookie(map);

  /// 会话层条目数（分层验证用）。
  int get sessionCount => _session.values.fold(0, (n, m) => n + m.length);

  /// 持久层条目数（分层验证用）。
  int get persistentCount => _persistent.values.fold(0, (n, m) => n + m.length);

  /// 指定 URL 域键下的 Cookie 头字节数（4096 上限验证用）。
  int cookieByteSize(String url) => _byteSize(_domainKey(url));

  /// 仅清空会话层（持久层保留）。
  void clearSession() => _session.clear();

  /// 等待持久化 Cookie 加载完成（应用启动或测试可显式调用）。
  Future<void> ready() => _loaded ?? Future<void>.value();

  /// 从 SharedPreferences 重新载入持久层（覆盖当前内存中的持久 Cookie）。
  Future<void> reload() async {
    _persistent.clear();
    await _loadPersisted();
  }

  /// 将持久层立即刷写到 SharedPreferences（测试或关键节点可显式调用）。
  Future<void> flush() async {
    await ready();
    await _writePersisted();
  }

  // ===================================================================
  // 内部存储
  // ===================================================================

  void _put(String url, cu.SetCookie sc) {
    final key = _domainKey(url, sc.domain);
    _putAt(
      key,
      _Cookie(
        sc.name,
        sc.value,
        path: sc.path,
        host: sc.domain,
        expires: sc.expires,
        maxAge: sc.maxAge,
        secure: sc.secure,
        httpOnly: sc.httpOnly,
        createdAt: DateTime.now().toUtc(),
        order: _seq++,
      ),
      persistent: !sc.isSession,
    );
  }

  void _putAt(String key, _Cookie c, {bool persistent = false}) {
    final layer = persistent ? _persistent : _session;
    final other = persistent ? _session : _persistent;
    final jar = layer.putIfAbsent(key, () => <String, _Cookie>{});
    jar[c.name] = c;
    // 同名 cookie 不跨层分裂
    other[key]?.remove(c.name);
    _enforceLimit(key);
    if (persistent) _schedulePersist();
  }

  /// eTLD+1 域键；带 domain 属性且作用域合法时以该 domain 归一。
  String _domainKey(String url, [String? domainAttr]) {
    if (domainAttr != null) {
      final host = Uri.parse(url).host.toLowerCase();
      if (cu.cookieDomainMatch(host, domainAttr)) {
        return cu.getSubDomain('http://$domainAttr');
      }
    }
    return cu.getSubDomain(url);
  }

  bool _domainKeyMatches(String host, String domainKey) {
    final h = host.toLowerCase();
    final d = domainKey.toLowerCase();
    return h == d || h.endsWith('.$d');
  }

  int _byteSize(String key) {
    var n = 0;
    for (final layer in [_persistent, _session]) {
      final jar = layer[key];
      if (jar == null) continue;
      for (final c in jar.values) {
        n += utf8.encode('${c.name}=${c.value}; ').length;
      }
    }
    return n;
  }

  /// 超出 [maxCookieBytes] 时丢弃插入最早（最旧）的条目，直到合规。
  void _enforceLimit(String key) {
    while (_byteSize(key) > maxCookieBytes) {
      _Cookie? oldest;
      Map<String, _Cookie>? oldestJar;
      for (final layer in [_persistent, _session]) {
        final jar = layer[key];
        if (jar == null || jar.isEmpty) continue;
        for (final c in jar.values) {
          if (oldest == null || c.order < oldest.order) {
            oldest = c;
            oldestJar = jar;
          }
        }
      }
      if (oldest == null || oldestJar == null) break;
      oldestJar.remove(oldest.name);
    }
  }
  // ===================================================================
  // 持久层序列化（SharedPreferences）
  // ===================================================================

  void _schedulePersist() {
    // 后台落盘；失败静默忽略，不影响请求主流程。
    unawaited(flush());
  }

  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(persistentPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (value is! List) return;
        final jar = <String, _Cookie>{};
        for (final item in value) {
          final c = _cookieFromJson(item);
          if (c != null) jar[c.name] = c;
        }
        if (jar.isNotEmpty) _persistent[key.toString()] = jar;
      });
      for (final jar in _persistent.values) {
        for (final c in jar.values) {
          if (c.order >= _seq) _seq = c.order + 1;
        }
      }
    } catch (_) {
      // 坏数据宽松处理：保持内存现状，不清空。
    }
  }

  Future<void> _writePersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      _persistent.forEach((key, jar) {
        if (jar.isEmpty) return;
        map[key] = jar.values.map(_cookieToJson).toList();
      });
      await prefs.setString(persistentPrefsKey, jsonEncode(map));
    } catch (_) {}
  }

  static Map<String, dynamic> _cookieToJson(_Cookie c) => <String, dynamic>{
        'name': c.name,
        'value': c.value,
        'path': c.path,
        'host': c.host,
        'expires': c.expires?.millisecondsSinceEpoch,
        'maxAge': c.maxAge,
        'secure': c.secure,
        'httpOnly': c.httpOnly,
        'createdAt': c.createdAt.millisecondsSinceEpoch,
        'order': c.order,
      };

  static _Cookie? _cookieFromJson(dynamic v) {
    if (v is! Map) return null;
    try {
      return _Cookie(
        v['name'] as String,
        v['value'] as String,
        path: (v['path'] as String?) ?? '/',
        host: v['host'] as String?,
        expires: _dtFromMillis(v['expires']),
        maxAge: (v['maxAge'] as num?)?.toInt(),
        secure: (v['secure'] as bool?) ?? false,
        httpOnly: (v['httpOnly'] as bool?) ?? false,
        createdAt: _dtFromMillis(v['createdAt']) ?? DateTime.now().toUtc(),
        order: (v['order'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? _dtFromMillis(dynamic v) {
    if (v is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
  }
}

/// 单条已存储的 cookie（含分层 / 过期 / 插入序信息）。
class _Cookie {
  _Cookie(
    this.name,
    this.value, {
    required this.path,
    this.host,
    this.expires,
    this.maxAge,
    this.secure = false,
    this.httpOnly = false,
    required this.createdAt,
    required this.order,
  });

  final String name;
  final String value;
  final String path;
  final String? host;
  final DateTime? expires;
  final int? maxAge;
  final bool secure;
  final bool httpOnly;
  final DateTime createdAt;
  final int order;

  DateTime? get expiryAt {
    if (maxAge != null) return createdAt.add(Duration(seconds: maxAge!));
    return expires;
  }

  bool isExpired(DateTime now) {
    if (maxAge != null) {
      if (maxAge! <= 0) return true;
      return now.isAfter(createdAt.add(Duration(seconds: maxAge!)));
    }
    if (expires != null && now.isAfter(expires!)) return true;
    return false;
  }
}
