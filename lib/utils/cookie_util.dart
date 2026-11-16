/// Cookie 分域与 Set-Cookie 解析工具。
///
/// 以 eTLD+1（[getSubDomain]）作为 Cookie 域键，避免 `.com.cn` 等多段公共
/// 后缀导致跨站串域。本文件为纯函数工具集，不持有状态。
library;

/// 常见「多段公共后缀」（Public Suffix List 的精简子集）。
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

/// 仅 http/https，截到首个 `/`。
String? getBaseUrl(String url) {
  final lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return null;
  }
  final index = url.indexOf('/', 9);
  return index == -1 ? url : url.substring(0, index);
}

/// 严格 IPv4：首字符 1-9、恰好 3 个点、每段 0..255。
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

/// IPv6 含冒号。
bool isIPv6Address(String? input) => input != null && input.contains(':');

bool isIPAddress(String? input) => isIPv4Address(input) || isIPv6Address(input);

/// eTLD+1：先查两/三段公共后缀，命中则多取一段，否则取最后两段。
String _effectiveTldPlusOne(String host) {
  final parts = host.split('.');
  if (parts.length <= 2) return host;
  final last2 = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  final last3 = parts.length >= 3 ? '${parts[parts.length - 3]}.$last2' : '';
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

/// 非法或非 http(s) URL 返回 null。
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

/// 取 URL 的完整 host。
String getDomain(String url) {
  final baseUrl = getBaseUrl(url);
  if (baseUrl == null) return url;
  try {
    return Uri.parse(baseUrl).host;
  } catch (_) {
    return baseUrl;
  }
}

// =====================================================================
// Cookie 头 <-> Map
// =====================================================================

/// 把 `a=1; b=2` 形式的 Cookie 头解析为 map（value 中允许含 `=`）。
Map<String, String> cookieToMap(String? cookie) {
  final result = <String, String>{};
  if (cookie == null) return result;
  for (final part in cookie.split(';')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final idx = p.indexOf('=');
    if (idx <= 0) continue;
    final name = p.substring(0, idx).trim();
    if (name.isEmpty) continue;
    result[name] = p.substring(idx + 1).trim();
  }
  return result;
}

/// 把 map 序列化为 `a=1; b=2` Cookie 头。
String mapToCookie(Map<String, String> map) =>
    map.entries.map((e) => '${e.key}=${e.value}').join('; ');

// =====================================================================
// Set-Cookie 解析
// =====================================================================

const Map<String, int> _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

int? _monthOf(String name) {
  if (name.length < 3) return null;
  return _months[name.substring(0, 3).toLowerCase()];
}

/// 解析 HTTP-date（RFC 1123 / RFC 850 / asctime），也兼容 ISO-8601；
/// 失败返回 null（由调用方按会话或未过期处理，绝不抛异常）。
DateTime? parseHttpDate(String value) {
  final s = value.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toUtc();
  // RFC 1123 / RFC 850：09 Jun 2027 10:18:14 / 09-Jun-21 10:18:14
  final dmy = RegExp(
          r'(\d{1,2})[\s-]+([A-Za-z]{3})[\s-]+(\d{2,4})\s+(\d{1,2}):(\d{2}):(\d{2})')
      .firstMatch(s);
  if (dmy != null) {
    final month = _monthOf(dmy.group(2)!);
    if (month != null) {
      var year = int.parse(dmy.group(3)!);
      if (year < 100) year += year >= 70 ? 1900 : 2000;
      return DateTime.utc(
          year,
          month,
          int.parse(dmy.group(1)!),
          int.parse(dmy.group(4)!),
          int.parse(dmy.group(5)!),
          int.parse(dmy.group(6)!));
    }
  }
  // asctime：Wed Jun  9 10:18:14 2021
  final asc =
      RegExp(r'([A-Za-z]{3})\s+(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(\d{4})')
          .firstMatch(s);
  if (asc != null) {
    final month = _monthOf(asc.group(1)!);
    if (month != null) {
      return DateTime.utc(
          int.parse(asc.group(6)!),
          month,
          int.parse(asc.group(2)!),
          int.parse(asc.group(3)!),
          int.parse(asc.group(4)!),
          int.parse(asc.group(5)!));
    }
  }
  return null;
}

/// 单条 Set-Cookie 的结构化属性。
class SetCookie {
  SetCookie({
    required this.name,
    required this.value,
    this.domain,
    required this.path,
    this.expires,
    this.maxAge,
    this.secure = false,
    this.httpOnly = false,
  });

  final String name;
  final String value;
  final String? domain;
  final String path;
  final DateTime? expires;
  final int? maxAge;
  final bool secure;
  final bool httpOnly;

  /// 无 expires / max-age 即为会话 cookie。
  bool get isSession => expires == null && maxAge == null;
}

/// 解析一条 Set-Cookie；[defaultPath] 为 RFC 6265 的默认路径。
/// 无有效 `name=value` 时返回 null。
SetCookie? parseSetCookie(String raw, {String defaultPath = '/'}) {
  if (raw.trim().isEmpty) return null;
  final segments = raw.split(';');
  final first = segments.first.trim();
  final eq = first.indexOf('=');
  if (eq <= 0) return null;
  final name = first.substring(0, eq).trim();
  final value = first.substring(eq + 1).trim();
  if (name.isEmpty) return null;

  String? domain;
  var path = defaultPath;
  DateTime? expires;
  int? maxAge;
  var secure = false;
  var httpOnly = false;

  for (var i = 1; i < segments.length; i++) {
    final seg = segments[i].trim();
    if (seg.isEmpty) continue;
    final c = seg.indexOf('=');
    final key = (c < 0 ? seg : seg.substring(0, c)).trim().toLowerCase();
    final val = c < 0 ? '' : seg.substring(c + 1).trim();
    switch (key) {
      case 'domain':
        if (val.isNotEmpty) {
          var d = val.toLowerCase();
          if (d.startsWith('.')) d = d.substring(1);
          domain = d;
        }
        break;
      case 'path':
        if (val.isNotEmpty) path = val;
        break;
      case 'expires':
        expires = parseHttpDate(val);
        break;
      case 'max-age':
        maxAge = int.tryParse(val);
        break;
      case 'secure':
        secure = true;
        break;
      case 'httponly':
        httpOnly = true;
        break;
    }
  }
  return SetCookie(
    name: name,
    value: value,
    domain: domain,
    path: path,
    expires: expires,
    maxAge: maxAge,
    secure: secure,
    httpOnly: httpOnly,
  );
}

/// 请求 URL 的默认 cookie path：去掉最后一段，保留到最后一个 `/`。
String defaultCookiePath(String url) {
  try {
    final p = Uri.parse(url).path;
    if (p.isEmpty || !p.startsWith('/')) return '/';
    final last = p.lastIndexOf('/');
    if (last <= 0) return '/';
    return p.substring(0, last);
  } catch (_) {
    return '/';
  }
}

/// RFC 6265 路径匹配（简化）：请求路径落在 cookie path 之内。
bool cookiePathMatch(String requestPath, String cookiePath) {
  var rp = requestPath;
  if (rp.isEmpty || !rp.startsWith('/')) rp = '/';
  final cp = cookiePath;
  if (cp.isEmpty || !cp.startsWith('/')) return true;
  if (rp == cp) return true;
  if (!rp.startsWith(cp)) return false;
  return cp.endsWith('/') || rp[cp.length] == '/';
}

/// 请求 host 是否落在 cookie 的 domain 作用域内（null 表示 host-only）。
bool cookieDomainMatch(String requestHost, String? cookieDomain) {
  if (cookieDomain == null || cookieDomain.isEmpty) return true;
  final h = requestHost.toLowerCase();
  var d = cookieDomain.toLowerCase();
  if (d.startsWith('.')) d = d.substring(1);
  if (h == d) return true;
  return h.endsWith('.$d');
}
