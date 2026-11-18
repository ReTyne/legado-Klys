import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网址拦截：在书源/订阅源导入前按域名黑名单过滤不良网址。
///
/// 名单由随包内置清单与用户自定义清单合并而成，开关状态与自定义清单
/// 持久化在 SharedPreferences（键见 [keyEnabled] / [keyCustomDomains]）。
class UrlGuard {
  UrlGuard._();

  static final UrlGuard instance = UrlGuard._();

  static const String keyEnabled = 'oc_urlBlockEnabled';
  static const String keyCustomDomains = 'oc_urlBlockList';
  static const String assetPath = 'assets/url_block_list.txt';

  Set<String> _builtIn = <String>{};
  Set<String> _custom = <String>{};
  bool _enabled = true;
  Future<void>? _initFuture;

  bool get enabled => _enabled;

  List<String> get builtInDomains => _sorted(_builtIn);

  List<String> get customDomains => _sorted(_custom);

  /// 预加载内置名单与用户配置；内部只执行一次，可安全重复调用。
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(keyEnabled) ?? true;
    _custom = normalize(prefs.getString(keyCustomDomains)?.split(RegExp(r'[\r\n]+')) ??
        const <String>[]);
    try {
      _builtIn = decodeDomains(await rootBundle.loadString(assetPath));
    } catch (_) {
      // 内置清单读取失败时降级为空名单，不影响其余过滤逻辑。
      _builtIn = <String>{};
    }
  }

  /// 将每行一个域名的文本规范化为去重的小写域名集合。
  static Set<String> normalize(Iterable<String> lines) {
    final result = <String>{};
    for (final line in lines) {
      final domain = line.trim().toLowerCase();
      if (domain.isNotEmpty && domain.contains('.')) result.add(domain);
    }
    return result;
  }

  static List<String> _sorted(Set<String> set) => set.toList()..sort();

  /// 解码随包携带的 base64 域名清单；解码失败返回空集合。
  static Set<String> decodeDomains(String base64Content) {
    try {
      final text = utf8.decode(base64.decode(base64Content.trim()));
      return normalize(text.split(RegExp(r'[\r\n]+')));
    } catch (_) {
      return <String>{};
    }
  }

  /// 取 URL 的主域+后缀（www.example.com → example.com）。
  static String? mainDomain(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return null;
    Uri? uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      uri = Uri.tryParse('http://$raw');
    }
    final host = uri?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;
    final clean = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    final parts = clean.split('.');
    if (parts.length < 2) return null;
    return parts.sublist(parts.length - 2).join('.');
  }

  /// 命中黑名单返回 true；名单为空、URL 非法或功能关闭时返回 false。
  /// [domains] 可直接注入名单（便于测试），不传时使用内置名单+自定义名单。
  bool isBlocked(String url, {List<String>? domains}) {
    if (!_enabled) return false;
    final list = domains ?? <String>[..._builtIn, ..._custom];
    if (list.isEmpty) return false;
    final domainSet = normalize(list);
    if (domainSet.isEmpty) return false;
    final main = mainDomain(url);
    if (main == null) return false;
    return domainSet.contains(main);
  }

  Future<void> setCustomDomains(List<String> domains) async {
    _custom = normalize(domains);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyCustomDomains, _sorted(_custom).join('\n'));
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyEnabled, value);
  }
}
