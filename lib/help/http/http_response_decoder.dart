import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:enough_convert/enough_convert.dart';
import 'package:legado_md3/utils/encoding_detect.dart';

/// HTTP 响应解码器 —— 对齐 legado-E 的三段细节链：
///
/// 1. `help/http/DecompressInterceptor.kt`：请求未带 `Accept-Encoding` 且未带
///    `Range` 时透明解压 `gzip` / `deflate`（含 raw deflate，`Inflater(true)`）；
///    `Range` 请求（206 分片）跳过解压；解压后 `Content-Encoding` 与
///    `Content-Length` 头失效（本解码器只消费 `content-type`，天然不受影响）。
/// 2. `utils/Utf8BomUtils.kt`：`removeUTF8BOM(bytes)` 去掉 UTF-8 BOM，
///    同时兼容 UTF-16 LE/BE BOM 并按其字节序解码。
/// 3. `help/http/OkHttpUtils.kt` 的 `ResponseBody.text()` 与
///    `utils/EncodingDetect.kt` 的 `getHtmlEncode()`：编码优先级
///    `forcedCharset > Content-Type charset > HTML <meta> charset > 统计探测`。
///
/// 全部为纯函数，不发起网络请求，便于单元回归。
class HttpResponseDecoder {
  HttpResponseDecoder._();

  /// 完整解码入口。
  ///
  /// [headers] 为 Dio 的 `response.headers.map`（键大小写不敏感）。
  /// [forcedCharset] 对应上游 `ResponseBody.text(encode)` 显式编码，优先级最高。
  /// [rangeRequested] 对应上游 DecompressInterceptor 的 `Range` 保护。
  /// [skipDecompress] 用于底层（如 Dio）已处理解压的场景，避免二次解压。
  static String decode(
    List<int> bytes, {
    Map<String, List<String>>? headers,
    String? forcedCharset,
    bool rangeRequested = false,
    bool skipDecompress = false,
  }) {
    if (bytes.isEmpty) return '';
    final contentEncoding = _header(headers, 'content-encoding');
    final data = skipDecompress
        ? bytes
        : decompress(bytes,
            contentEncoding: contentEncoding, rangeRequested: rangeRequested);
    final cleaned = removeBom(data);
    final charset = resolveCharset(
      cleaned.bytes,
      headers: headers,
      forcedCharset: forcedCharset,
      bomCharset: cleaned.charset,
    );
    return decodeText(cleaned.bytes, charset: charset);
  }

  /// 大小写不敏感地取响应头第一个值。
  static String _header(Map<String, List<String>>? headers, String key) {
    if (headers == null) return '';
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == key && e.value.isNotEmpty) {
        return e.value.join(';');
      }
    }
    return '';
  }

  /// 细节 1：透明解压。
  ///
  /// - `Content-Encoding: gzip` 或 gzip 魔数 → GZip 解压；
  /// - `Content-Encoding: deflate` → 先按 zlib 包裹尝试，再按 raw deflate 尝试
  ///   （对齐上游 `Inflater(true)` 的 nowrap 语义）；
  /// - 无响应头但字节以 gzip / zlib 魔数开头时（Dio 未自动解压）同样兜底解压；
  /// - [rangeRequested] 为 true 时直接返回原字节（206 分片不可解压）；
  /// - 任何解压失败都安全返回原字节，交由后续编码链处理，不抛异常。
  static List<int> decompress(
    List<int> bytes, {
    String contentEncoding = '',
    bool rangeRequested = false,
  }) {
    if (rangeRequested || bytes.isEmpty) return bytes;
    final enc = contentEncoding.toLowerCase().trim();
    final isGzipMagic = bytes.length >= 2 &&
        bytes[0] == 0x1F && bytes[1] == 0x8B;
    final isZlibMagic = _isZlibHeader(bytes);

    if (enc == 'gzip' || enc.contains('gzip') || isGzipMagic) {
      final out = _tryGzip(bytes);
      if (out != null) return out;
    }
    if (enc == 'deflate' || enc.contains('deflate')) {
      final wrapped = _tryZlib(bytes);
      if (wrapped != null) return wrapped;
      final raw = _tryRawDeflate(bytes);
      if (raw != null) return raw;
    } else if (isZlibMagic && !isGzipMagic) {
      // 无 Content-Encoding 但明显是 zlib 流：兜底解压
      final wrapped = _tryZlib(bytes);
      if (wrapped != null) return wrapped;
    }
    return bytes;
  }

  static bool _isZlibHeader(List<int> b) {
    if (b.length < 2) return false;
    final cmf = b[0] & 0xFF;
    final flg = b[1] & 0xFF;
    return (cmf & 0x0F) == 8 && ((cmf << 8) | flg) % 31 == 0 && (cmf >> 4) <= 7;
  }

  static List<int>? _tryGzip(List<int> b) {
    try {
      return archive.GZipDecoder().decodeBytes(b);
    } catch (_) {
      return null;
    }
  }

  static List<int>? _tryZlib(List<int> b) {
    try {
      return const archive.ZLibDecoder().decodeBytes(b);
    } catch (_) {
      return null;
    }
  }

  static List<int>? _tryRawDeflate(List<int> b) {
    try {
      return archive.Inflate(b).getBytes();
    } catch (_) {
      return null;
    }
  }

  /// 细节 2：去 BOM（上游 Utf8BomUtils）。
  /// 返回去掉 BOM 的字节，以及 BOM 隐含的编码（UTF-16 时用于字节序解码）。
  static ({List<int> bytes, String? charset}) removeBom(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return (bytes: bytes.sublist(3), charset: 'utf-8');
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return (bytes: bytes.sublist(2), charset: 'utf-16le');
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return (bytes: bytes.sublist(2), charset: 'utf-16be');
    }
    return (bytes: bytes, charset: null);
  }

  /// 细节 3：编码判定，严格按上游优先级。
  /// `forcedCharset > BOM > Content-Type charset > HTML meta charset > 统计探测`。
  static String resolveCharset(
    List<int> bytes, {
    Map<String, List<String>>? headers,
    String? forcedCharset,
    String? bomCharset,
  }) {
    final forced = forcedCharset?.trim();
    if (forced != null && forced.isNotEmpty) return _normalize(forced);
    // UTF-16 BOM 的字节序必须优先于 HTML meta（meta 是单字节文本，无法描述 UTF-16）
    if (bomCharset == 'utf-16le') return 'utf-16le';
    if (bomCharset == 'utf-16be') return 'utf-16be';
    final ct = _header(headers, 'content-type').toLowerCase();
    final m = RegExp(r'charset\s*=\s*["\x27]?([a-z0-9_\-]+)').firstMatch(ct);
    if (m != null) return _normalize(m.group(1)!);

    // HTML meta：对齐 EncodingDetect.getHtmlEncode，先看 <head> 内，
    // 支持 <meta charset="gbk"> 与 <meta http-equiv=... content="...;charset=gbk">
    final meta = _metaCharset(bytes);
    if (meta != null) return _normalize(meta);

    if (bomCharset == 'utf-8') return 'utf-8';
    // ICU 统计探测的等价实现（EncodingDetector）
    return EncodingDetector.detect(Uint8List.fromList(bytes));
  }

  static String _normalize(String cs) {
    final c = cs.toLowerCase().trim();
    if (c == 'gb2312' || c == 'gb18030' || c == 'gb_2312' || c == 'cp936' ||
        c == 'gbk') return 'gbk';
    if (c == 'big-5' || c == 'big5' || c == 'cp950') return 'big5';
    if (c == 'iso-8859-1' || c == 'latin1' || c == 'l1') return 'latin1';
    if (c == 'utf16le' || c == 'utf-16le' || c == 'unicodefffe') return 'utf-16le';
    if (c == 'utf16be' || c == 'utf-16be') return 'utf-16be';
    if (c == 'utf8' || c == 'utf-8' || c == 'us-ascii' || c == 'ascii') return 'utf-8';
    return c;
  }

  /// 从 HTML 头部提取 meta charset（只扫描前 4KB，避免大正文开销）。
  static String? _metaCharset(List<int> bytes) {
    final head = _ascii(bytes, 4096).toLowerCase();
    // <meta charset="gbk"> / <meta charset=gbk> / <meta charset='gbk'>
    final direct = RegExp(
            r'''<meta[^>]*\bcharset\s*=\s*["\x27]?\s*([a-z0-9_\-]+)''')
        .firstMatch(head);
    if (direct != null) return direct.group(1);
    // <meta http-equiv="Content-Type" content="text/html; charset=gbk">
    final equiv = RegExp(
            r'''<meta[^>]*http-equiv\s*=\s*["\x27]?content-type[^>]*content\s*=\s*["\x27][^"\x27]*charset\s*=\s*([a-z0-9_\-]+)''')
        .firstMatch(head);
    if (equiv != null) return equiv.group(1);
    return null;
  }

  static String _ascii(List<int> bytes, int limit) {
    final n = bytes.length < limit ? bytes.length : limit;
    return String.fromCharCodes(bytes.take(n).map((b) => b & 0xFF));
  }

  /// 按编码名解码文本；声明编码失败时回退到统计探测，再回退到 utf8 宽松模式。
  static String decodeText(List<int> bytes, {String? charset}) {
    final cs = charset == null ? null : _normalize(charset);
    if (cs != null) {
      final decoded = _decodeWith(bytes, cs);
      if (decoded != null) return decoded;
    }
    // 声明编码解不出来（站点乱声明 charset）→ 统计探测
    final detected = EncodingDetector.detect(Uint8List.fromList(bytes));
    final byDetect = _decodeWith(bytes, detected);
    if (byDetect != null) return byDetect;
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static String? _decodeWith(List<int> bytes, String cs) {
    try {
      switch (cs) {
        case 'utf-8':
          return utf8.decode(bytes, allowMalformed: false);
        case 'gbk':
          return const GbkCodec().decode(bytes);
        case 'big5':
          return const Big5Codec().decode(bytes);
        case 'latin1':
          return latin1.decode(bytes);
        case 'utf-16le':
          return _utf16(bytes, littleEndian: true);
        case 'utf-16be':
          return _utf16(bytes, littleEndian: false);
        default:
          // 未知名编码（如 shift_jis）：尝试 utf8 严格校验，失败交回上层探测
          return utf8.decode(bytes, allowMalformed: false);
      }
    } catch (_) {
      return null;
    }
  }

  static String _utf16(List<int> b, {required bool littleEndian}) {
    final codes = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      codes.add(littleEndian
          ? (b[i] & 0xFF) | ((b[i + 1] & 0xFF) << 8)
          : ((b[i] & 0xFF) << 8) | (b[i + 1] & 0xFF));
    }
    return String.fromCharCodes(codes);
  }
}
