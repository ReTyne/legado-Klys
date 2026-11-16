import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 代理协议类型。
enum ProxyScheme { http, socks4, socks5 }

/// 结构化代理配置，由 [ProxyConfig.parse] 从书源 `proxy` 值解析得到。
class ProxyConfig {
  ProxyConfig({
    required this.scheme,
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  final ProxyScheme scheme;
  final String host;
  final int port;
  final String? username;
  final String? password;

  bool get hasAuth => username != null && username!.isNotEmpty;

  /// 按 (scheme, host, port) 缓存 client 的键。
  String get cacheKey => '${scheme.name}://$host:$port';

  /// [HttpClient.findProxy] 返回值。
  ///
  /// 边界：Dart 原生 [HttpClient] 的 findProxy 仅支持 PROXY（HTTP CONNECT）
  /// 与 DIRECT，不实现 SOCKS 握手。因此 socks4/socks5 在此按 HTTP CONNECT
  /// 代理近似转发——前提是本地代理在同一端口提供 HTTP 代理（混合端口）。
  /// 若代理端口仅开放 SOCKS 协议，则该路径不可用，属于平台能力边界。
  String get findProxyValue => 'PROXY $host:$port';

  /// Proxy-Authorization: Basic base64(user:pass)。
  String? get proxyAuthorization {
    if (!hasAuth) return null;
    return 'Basic ${base64.encode(utf8.encode('$username:${password ?? ''}'))}';
  }

  /// 解析 `(http|socks4|socks5)://[user:pass@]host:port`。
  /// 无 scheme 时按 http 处理；未知 scheme 返回 null。
  static ProxyConfig? parse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    var scheme = ProxyScheme.http;
    final sm = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(s);
    if (sm != null) {
      switch (sm.group(1)!.toLowerCase()) {
        case 'http':
        case 'https':
          scheme = ProxyScheme.http;
          break;
        case 'socks4':
        case 'socks4a':
          scheme = ProxyScheme.socks4;
          break;
        case 'socks':
        case 'socks5':
        case 'socks5h':
          scheme = ProxyScheme.socks5;
          break;
        default:
          return null;
      }
      s = s.substring(sm.end);
    }
    // 截掉可能的 path / query
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);

    // 认证：user:pass@host:port（用最后一个 @，允许密码中含 @）
    String? user;
    String? pass;
    final at = s.lastIndexOf('@');
    if (at >= 0) {
      final cred = s.substring(0, at);
      s = s.substring(at + 1);
      final colon = cred.indexOf(':');
      if (colon >= 0) {
        user = Uri.decodeComponent(cred.substring(0, colon));
        pass = Uri.decodeComponent(cred.substring(colon + 1));
      } else {
        user = Uri.decodeComponent(cred);
      }
    }

    String host;
    int port;
    final colon = s.lastIndexOf(':');
    if (colon > 0 && !s.endsWith(']')) {
      host = s.substring(0, colon);
      port = int.tryParse(s.substring(colon + 1)) ?? _defaultPort(scheme);
    } else {
      host = s;
      port = _defaultPort(scheme);
    }
    // 去 IPv6 方括号
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host.isEmpty) return null;
    return ProxyConfig(
      scheme: scheme,
      host: host,
      port: port,
      username: user,
      password: pass,
    );
  }

  static int _defaultPort(ProxyScheme scheme) =>
      scheme == ProxyScheme.http ? 8080 : 1080;
}

/// 把 [ProxyConfig] 应用到 Dio 实例，按 host 缓存已配置的适配器与 client。
class ProxyClient {
  ProxyClient._();

  static final Map<String, IOHttpClientAdapter> _adapters = {};
  static final Map<String, HttpClient> _clients = {};

  /// 配置 dio 走代理；需要认证时补充 Proxy-Authorization 头。
  ///
  /// RFC 7235：HTTP 代理在转发请求前应剥离 Proxy-* 头，且 [findProxyValue]
  /// 返回 PROXY 时请求必经代理，故该头不会泄漏到目标服务器。
  /// 配置 dio 走代理；[trustAll] 为 true 时在同一适配器内一并放行证书，
  /// 避免证书放行适配器覆盖掉代理设置。
  static void apply(Dio dio, ProxyConfig cfg, {bool trustAll = false}) {
    try {
      final key = '${cfg.cacheKey}|$trustAll';
      final adapter =
          _adapters.putIfAbsent(key, () => _build(cfg, key, trustAll));
      dio.httpClientAdapter = adapter;
      final auth = cfg.proxyAuthorization;
      if (auth != null) {
        dio.options.headers['Proxy-Authorization'] = auth;
      }
    } catch (_) {
      // Web / 无 dart:io 环境：安全降级，不替换适配器也不抛异常
    }
  }

  static IOHttpClientAdapter _build(
      ProxyConfig cfg, String key, bool trustAll) {
    return IOHttpClientAdapter(
      createHttpClient: () {
        final cached = _clients[key];
        if (cached != null) return cached;
        final client = HttpClient();
        client.findProxy = (_) => cfg.findProxyValue;
        if (trustAll) {
          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
        }
        if (cfg.hasAuth) {
          // 代理 407 挑战时自动携带 Basic 凭据（realm 由代理声明，空串为兜底）
          client.addProxyCredentials(
            cfg.host,
            cfg.port,
            '',
            HttpClientBasicCredentials(cfg.username!, cfg.password ?? ''),
          );
        }
        _clients[key] = client;
        return client;
      },
      validateCertificate: trustAll
          ? (X509Certificate? cert, String host, int port) => true
          : null,
    );
  }

  /// 从书源请求头中提取 `proxy` 配置并剥离该头（不作为普通请求头发往目标
  /// 服务器），返回可传给 [apply] 的配置；不存在时返回 null。
  static ProxyConfig? fromHeaders(Map<String, String> headers) {
    String? proxyKey;
    for (final k in headers.keys) {
      if (k.toLowerCase() == 'proxy') {
        proxyKey = k;
        break;
      }
    }
    if (proxyKey == null) return null;
    final raw = headers.remove(proxyKey);
    if (raw == null) return null;
    return ProxyConfig.parse(raw);
  }

  /// 便捷组合：提取 + 应用 + 返回配置。
  static ProxyConfig? applyFromHeaders(Dio dio, Map<String, String> headers) {
    final cfg = fromHeaders(headers);
    if (cfg != null) apply(dio, cfg);
    return cfg;
  }
}
