/// URL 边界工具：查询/表单编码判定、参数编码、相对地址解析。
library;

import 'dart:convert';

/// Query 保留集 `!$&()*+,-./:;=?@[\]^_`{|}~`。
const String _queryReserved = r'!$&()*+,-./:;=?@[\]^_`{|}~';

/// Form 保留集 `*-._`。
const String _formReserved = '*-._';

bool _isAsciiLetterOrDigit(int code) =>
    (code >= 0x61 && code <= 0x7A) ||
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x30 && code <= 0x39);

bool _isHex16(int code) =>
    (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x46) ||
    (code >= 0x61 && code <= 0x66);

bool _isDigit16Char(String s, int i) =>
    i < s.length && _isHex16(s.codeUnitAt(i));

/// 逐字符判定字符串是否已 URL 编码：`%` 后两位须均为 16 进制字符，
/// 否则视为「需编码」；0-9A-Za-z 与 [reserved] 中的字符视为已编码。
bool _isEncoded(String str, String reserved) {
  final reservedCodes = reserved.codeUnits.toSet();
  var i = 0;
  while (i < str.length) {
    final c = str.codeUnitAt(i);
    if (_isAsciiLetterOrDigit(c) || reservedCodes.contains(c)) {
      i++;
      continue;
    }
    if (c == 0x25 && i + 2 < str.length) {
      if (_isDigit16Char(str, i + 1) && _isDigit16Char(str, i + 2)) {
        i += 3;
        continue;
      }
    }
    return false;
  }
  return true;
}

/// Query 保留集判定。
bool encodedQuery(String str) => _isEncoded(str, _queryReserved);

/// Form 保留集判定（仅 `*-._` 四个额外保留字符）。
bool encodedForm(String str) => _isEncoded(str, _formReserved);

bool _isAbsUrl(String s) {
  final l = s.toLowerCase();
  return l.startsWith('http://') || l.startsWith('https://');
}

bool _isDataUrl(String s) => s.toLowerCase().startsWith('data:');

/// 相对地址解析为绝对 URL。
///
/// 分支：baseURL 为空 → 返回 trim 后的相对路径；逗号截断 baseURL；
/// 绝对 URL / Data URL → 原样返回；`javascript:` → 返回空串；
/// 其余按 base 解析相对路径。
///
/// [redirectUrl] 非空时优先作为解析基址（用于重定向后的地址）。
String getAbsoluteURL(String? baseURL, String relativePath,
    {String? redirectUrl}) {
  final trimmed = relativePath.trim();
  final effectiveBase =
      (redirectUrl != null && redirectUrl.isNotEmpty) ? redirectUrl : baseURL;
  if (effectiveBase == null || effectiveBase.isEmpty) return trimmed;
  final base = effectiveBase.split(',').first;
  Uri? baseUri;
  try {
    baseUri = Uri.parse(base);
  } catch (_) {
    return trimmed;
  }
  if (_isAbsUrl(trimmed)) return trimmed;
  if (_isDataUrl(trimmed)) return trimmed;
  if (trimmed.toLowerCase().startsWith('javascript')) return '';
  try {
    return baseUri.resolve(trimmed).toString();
  } catch (_) {
    return trimmed;
  }
}

/// 把参数 Map 编码为 `key=value&...` 请求体/查询串（URLEncoder 语义）。
///
/// * 已编码的值（含合法 `%XX`）不重复编码；
/// * 普通字符集：空格编码为 `+`，其余非保留字节按 UTF-8 `%XX` 大写；
/// * [charset] 为 `escape` 时：空格编码为 `%20`，非 ASCII 走百分号大写编码。
String encodeParams(Map<String, dynamic> params, {String charset = 'utf-8'}) {
  final escape = charset.toLowerCase() == 'escape';
  final parts = <String>[];
  for (final e in params.entries) {
    final k = _encodeParam(e.key.toString(), escape);
    final v = _encodeParam(e.value?.toString() ?? '', escape);
    parts.add('$k=$v');
  }
  return parts.join('&');
}

const Set<int> _unreserved = <int>{0x2A, 0x2D, 0x2E, 0x5F};

String _encodeParam(String s, bool escape) {
  // 已编码（或仅含 unreserved 字符）时无需再编码。
  if (encodedForm(s)) return s;
  final bytes = utf8.encode(s);
  final sb = StringBuffer();
  for (final b in bytes) {
    if (_isAsciiLetterOrDigit(b) || _unreserved.contains(b)) {
      sb.writeCharCode(b);
    } else if (b == 0x20 && !escape) {
      sb.write('+');
    } else {
      sb.write('%');
      sb.write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return sb.toString();
}
