/// 批次 6 · Cookie 分域（对齐 legado-E `utils/NetworkUtils.kt:212-236`
/// 与 `help/http/CookieStore.kt:26-35`）：用 eTLD+1 作为 Cookie 的域键，
/// 避免 `.com.cn` 等多段公共后缀导致跨站串域。
///
/// 真实消费点：本轮由 `test/detail_batch6_test.dart` 覆盖契约。
/// 生产接线目标是 `lib/help/http/cookie_manager.dart`（本轮文件所有权不含
/// `lib/help/http/**`，由主代理统一接入），故此处只提供纯函数工具，不改动
/// 现有 Cookie 存储实现。
library;

/// 常见「多段公共后缀」（Public Suffix List 的精简子集）。
/// 上游用 OkHttp `PublicSuffixDatabase.getEffectiveTldPlusOne`；纯 Dart 无
/// 等价内置数据库，且本轮不能修改 pubspec.yaml 引入依赖，故采用精简表降级：
/// 命中两/三段公共后缀则按其长度取 eTLD+1，未命中按「最后两段」通用规则。
const Set<String> _multiPartPublicSuffixes = <String>{
  // 两段公共后缀
  'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn', 'ac.cn', 'mil.cn',
  'com.hk', 'net.hk', 'org.hk', 'edu.hk', 'gov.hk', 'idv.hk',
  'com.tw', 'net.tw', 'org.tw', 'edu.tw', 'gov.tw', 'idv.tw',
  'com.sg', 'net.sg', 'org.sg', 'edu.sg', 'per.sg',
  'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'ad.jp', 'go.jp', 'gr.jp', 'lg.jp',
  'co.kr', 'ne.kr', 'or.kr', 're.kr', 'pe.kr', 'go.kr',
  'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk', 'net.uk', 'sch.uk',
  'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au', 'asn.au', 'id.au',
  'co.nz', 'net.nz', 'org.nz', 'govt.nz', 'ac.nz', 'geek.nz',
  'com.br', 'net.br', 'org.br', 'gov.br', 'edu.br',
  'com.mx', 'org.mx', 'gob.mx', 'edu.mx', 'net.mx',
  'co.in', 'net.in', 'org.in', 'gen.in', 'firm.in', 'ind.in', 'gov.in',
  'co.za', 'org.za', 'net.za', 'gov.za', 'ac.za',
  'com.tr', 'net.tr', 'org.tr', 'gov.tr', 'edu.tr',
  'com.ru', 'net.ru', 'org.ru', 'msk.ru', 'spb.ru',
  'com.ua', 'net.ua', 'org.ua', 'gov.ua', 'edu.ua',
  'com.pl', 'net.pl', 'org.pl', 'gov.pl', 'edu.pl',
  'com.es', 'nom.es', 'org.es', 'gob.es', 'edu.es',
  'co.id', 'or.id', 'go.id', 'web.id', 'sch.id',
  'com.vn', 'net.vn', 'org.vn', 'edu.vn', 'gov.vn',
  'com.ph', 'net.ph', 'org.ph', 'gov.ph', 'edu.ph',
  'com.my', 'net.my', 'org.my', 'gov.my', 'edu.my',
  'github.io', 'gitlab.io', 'pages.dev', 'appspot.com', 'herokuapp.com',
  'cloudfront.net', 'azurewebsites.net',
  // 三段公共后缀（命中时保留 4 段）
  's3.amazonaws.com', 'k12.ak.us', 'k12.ma.us',
};

/// 对齐 `NetworkUtils.getBaseUrl`（:192-203）：仅 http/https，截到首个 `/`。
String? getBaseUrl(String url) {
  final lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return null;
  }
  final index = url.indexOf('/', 9);
  return index == -1 ? url : url.substring(0, index);
}

/// 严格 IPv4（对齐 `NetworkUtils.isIPv4Address` :278-283）：
/// 首字符 1-9、恰好 3 个点、每段 0..255。
bool isIPv4Address(String? input) {
  if (input == null || input.isEmpty) return false;
  if (input.codeUnitAt(0) < 0x31 || input.codeUnitAt(0) > 0x39) return false;
  final parts = input.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}

/// IPv6 含冒号（上游用 `Validator.isIpv6`，纯 Dart 降级为冒号判定）。
bool isIPv6Address(String? input) => input != null && input.contains(':');

bool isIPAddress(String? input) =>
    isIPv4Address(input) || isIPv6Address(input);

/// eTLD+1：先查两/三段公共后缀，命中则多取一段，否则取最后两段。
String _effectiveTldPlusOne(String host) {
  final parts = host.split('.');
  if (parts.length <= 2) return host;
  final last2 = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  final last3 = parts.length >= 3
      ? '${parts[parts.length - 3]}.$last2'
      : '';
  final int suffixLen;
  if (last3.isNotEmpty && _multiPartPublicSuffixes.contains(last3)) {
    suffixLen = 3;
  } else if (_multiPartPublicSuffixes.contains(last2)) {
    suffixLen = 2;
  } else {
    suffixLen = 1; // 普通单段 TLD（com / net / org / cn ...）
  }
  final take = suffixLen + 1;
  if (parts.length <= take) return host;
  return parts.sublist(parts.length - take).join('.');
}

/// 对齐 `NetworkUtils.getSubDomain`（:212-223）：
/// IP 直接返回 host；否则取 eTLD+1；解析失败回退 baseUrl。
/// 例：`www.biquge.com.cn → biquge.com.cn`，
/// `www.content.example.com → example.com`，`1.2.3.4 → 1.2.3.4`。
String getSubDomain(String url) {
  final baseUrl = getBaseUrl(url);
  if (baseUrl == null) return url;
  try {
    final host = Uri.parse(baseUrl).host;
    if (host.isEmpty) return baseUrl;
    if (isIPAddress(host)) return host;
    return _effectiveTldPlusOne(host);
  } catch (_) {
    return baseUrl;
  }
}

/// 对齐 `NetworkUtils.getSubDomainOrNull`（:225-236）。
String? getSubDomainOrNull(String url) {
  final baseUrl = getBaseUrl(url);
  if (baseUrl == null) return null;
  try {
    final host = Uri.parse(baseUrl).host;
    if (isIPAddress(host)) return host;
    return _effectiveTldPlusOne(host);
  } catch (_) {
    return null;
  }
}

/// 对齐 `NetworkUtils.getDomain`（:238-243）。
String getDomain(String url) {
  final baseUrl = getBaseUrl(url);
  if (baseUrl == null) return url;
  try {
    return Uri.parse(baseUrl).host;
  } catch (_) {
    return baseUrl;
  }
}
