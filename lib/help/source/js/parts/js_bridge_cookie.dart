/// 由 offline_js_bridge.dart 按「一类一文件」拆出的 JsBridgeCookie。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../offline_js_bridge.dart';


/// 对齐 cookie 对象：按 host 归并 Cookie，支持 getKey(url, name) 取单值。
class JsBridgeCookie {
  final Map<String, String> _jar = <String, String>{};

  /// 合并写入 Cookie（同 host 同名覆盖，对齐桥 __ingestSetCookie）。
  void setCookie(String url, String cookieStr) {
    final host = _hostOf(url);
    final jar = _pairs(_jar[host] ?? '');
    jar.addAll(_pairs(cookieStr));
    _jar[host] = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 读取 host（含子域匹配）的完整 Cookie 串。
  String getCookie(String url) => _jar[_matchHost(_hostOf(url))] ?? '';

  /// 删除某 host 的 Cookie。
  void removeCookie(String url) => _jar.remove(_matchHost(_hostOf(url)));

  /// 取 Cookie 中指定 name 的值（对齐桥 cookie.getKey 的正则语义）。
  String getKey(String url, String name) {
    final c = getCookie(url);
    final m = RegExp('(?:^|;\\s*)${RegExp.escape(name)}=([^;]*)').firstMatch(c);
    return m?.group(1) ?? '';
  }

  String _matchHost(String host) {
    if (host.isEmpty) return '';
    if (_jar.containsKey(host)) return host;
    for (final k in _jar.keys) {
      if (host == k || host.endsWith('.$k') || k.endsWith('.$host')) return k;
    }
    return '';
  }

  static Map<String, String> _pairs(String str) {
    final out = <String, String>{};
    for (final part in str.split(RegExp(r'[;\n]'))) {
      final p = part.trim();
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      final name = p.substring(0, idx).trim();
      if (RegExp(r'^(path|domain|expires|max-age|secure|httponly|samesite)$',
              caseSensitive: false)
          .hasMatch(name)) {
        continue;
      }
      out[name] = p.substring(idx + 1).trim();
    }
    return out;
  }

  static String _hostOf(String url) {
    final s = url.trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) {
      return Uri.tryParse(s)?.host ?? s;
    }
    final first = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').split('/').first;
    return first.replaceFirst(RegExp(r':\d+$'), '');
  }
}
