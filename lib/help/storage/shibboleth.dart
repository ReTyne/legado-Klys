import 'dart:convert';

/// 分享口令支持的资源类型。
///
/// [token] 是写入口令的短标记；[importType] 与
/// `DeepLinkService.importRaw(type:)` 归一化后期望的类型名一致。
enum ShareType {
  bookSource('bs', 'bookSource'),
  rssSource('rs', 'rss'),
  dictRule('dc', 'dictRule'),
  replaceRule('rp', 'replaceRule'),
  tocRule('tc', 'txtRule'),
  ttsRule('tt', 'httpTts');

  const ShareType(this.token, this.importType);

  final String token;
  final String importType;

  static ShareType? fromToken(String token) {
    for (final t in ShareType.values) {
      if (t.token == token) return t;
    }
    return null;
  }
}

/// 一条解析后的分享口令。
class SharePayload {
  const SharePayload({
    required this.url,
    required this.type,
    this.expiresAt,
  });

  /// 生成口令时传入的资源访问地址。
  final String url;

  /// 资源类型标记。
  final ShareType type;

  /// null 表示永久有效。
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !DateTime.now().isBefore(expiresAt!);

  String get importType => type.importType;
}

/// 分享口令工具：把资源访问地址混淆成可分享的 `#L:` 口令，并提供唯一解析入口。
///
/// 口令格式（`#L:` 之后的部分）：
/// ```text
/// base64url( utf8( json({"v":1,"t":typeToken,"e":expiryEpochMs,"u":url}) ) )
/// ```
/// - `e == 0`：永久有效；
/// - `e > 0`：到期的毫秒时间戳。
///
/// bootstrap_service 去掉 `#L:` 前缀后调用 [Shibboleth.tryParse]，
/// 因此生成与导入共用同一套解析，不会漂移。
class Shibboleth {
  static const String prefix = '#L:';
  static const int _version = 1;

  /// 生成口令。空地址与负的有效期天数视为非法输入。
  static String generateShareCode(
    String url,
    ShareType type, {
    int expiryDays = 0,
  }) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(url, 'url', '分享地址不能为空');
    }
    if (expiryDays < 0) {
      throw ArgumentError.value(expiryDays, 'expiryDays', '有效期天数不能为负');
    }
    final expiry = expiryDays == 0
        ? 0
        : DateTime.now().add(Duration(days: expiryDays)).millisecondsSinceEpoch;
    final payload = <String, dynamic>{
      'v': _version,
      't': type.token,
      'e': expiry,
      'u': trimmed,
    };
    return '$prefix${base64Url.encode(utf8.encode(jsonEncode(payload)))}';
  }

  /// 解析口令；非法或内容损坏时返回 null。同时接受带/不带 `#L:` 前缀的输入。
  static SharePayload? tryParse(String code) {
    var body = code.trim();
    if (body.startsWith(prefix)) body = body.substring(prefix.length).trim();
    if (body.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(body));
      final obj = jsonDecode(decoded);
      if (obj is! Map) return null;
      if (obj['v'] != _version) return null;
      final type = ShareType.fromToken((obj['t'] ?? '').toString());
      if (type == null) return null;
      final url = (obj['u'] ?? '').toString().trim();
      if (url.isEmpty) return null;
      final rawExpiry = obj['e'];
      final int? epoch = rawExpiry is int
          ? rawExpiry
          : (rawExpiry is num ? rawExpiry.toInt() : null);
      final expiresAt = (epoch == null || epoch <= 0)
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch);
      return SharePayload(url: url, type: type, expiresAt: expiresAt);
    } catch (_) {
      return null;
    }
  }
}

/// 顶层便捷函数，签名与调用方约定一致。
String generateShareCode(String url, ShareType type, {int expiryDays = 0}) =>
    Shibboleth.generateShareCode(url, type, expiryDays: expiryDays);

/// 顶层便捷函数，测试可直接调用验证往返。
SharePayload? tryParse(String code) => Shibboleth.tryParse(code);
