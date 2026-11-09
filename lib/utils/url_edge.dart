/// 批次 6 · URL 边界工具（对齐 legado-E `utils/NetworkUtils.kt:59-190`）。
///
/// 真实消费点：本轮由 `test/detail_batch6_test.dart` 覆盖契约。
/// 生产接线（JS bridge 的 getAbsoluteURL / HTTP 响应解码链路）不在本轮文件
/// 所有权内（`lib/help/source/**` 与 `lib/help/http/**` 由主代理负责），
/// 故此处只提供纯函数工具，供后续统一接入，不做「只写不读」的假接线。
library;

/// Query 保留集（对齐 `NetworkUtils.kt:70`）：`!$&()*+,-./:;=?@[\]^_`{|}~`
const String _queryReserved = r'!$&()*+,-./:;=?@[\]^_`{|}~';

/// Form 保留集（对齐 `NetworkUtils.kt:87`）：`*-._`
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

/// 对齐 `NetworkUtils.encodedQuery/encodedForm`（:99-149）：
/// 逐字符判定是否已 URL 编码；`%` 后两位须均为 16 进制字符，
/// 否则视为「需编码」。0-9A-Za-z 与 [reserved] 中的字符视为已编码。
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

/// Query 保留集判定（NetworkUtils.kt:99-123）。
bool encodedQuery(String str) => _isEncoded(str, _queryReserved);

/// Form 保留集判定（NetworkUtils.kt:125-149，仅 `*-._` 四个额外保留字符）。
bool encodedForm(String str) => _isEncoded(str, _formReserved);

bool _isAbsUrl(String s) {
  final l = s.toLowerCase();
  return l.startsWith('http://') || l.startsWith('https://');
}

bool _isDataUrl(String s) => s.toLowerCase().startsWith('data:');

/// 对齐 `NetworkUtils.getAbsoluteURL`（:161-190）四类边界分支：
///  * baseURL 为空 → 返回 trim 后的相对路径；
///  * 逗号截断 baseURL（`data:` URL 选项场景，:165）；
///  * 绝对 URL / Data URL → 原样返回（:178-179）；
///  * `javascript:` → 返回空串（:180）；
///  * 其余按 base 解析相对路径（:183）。
String getAbsoluteURL(String? baseURL, String relativePath) {
  final trimmed = relativePath.trim();
  if (baseURL == null || baseURL.isEmpty) return trimmed;
  final base = baseURL.split(',').first;
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
