import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 翻译服务：默认使用免费谷歌翻译端点（无需 API Key），
/// 也支持在设置中配置自定义端点。结果带内存缓存，避免重复请求。
class TranslationService {
  TranslationService._internal();
  static final TranslationService instance = TranslationService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (s) => s != null && s < 500,
  ));

  /// 原文(源语言_目标语言) -> 译文 的内存缓存
  final Map<String, String> _memCache = {};

  bool _enabled = false;
  String _target = 'zh-CN';
  String _source = 'auto';
  String _customUrl = '';
  String _apiKey = '';

  bool get enabled => _enabled;
  String get targetLang => _target;

  /// 从偏好设置加载翻译配置
  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool('translate_enabled') ?? p.getBool('tr_enabled') ?? false;
    _target = p.getString('tr_target') ?? 'zh-CN';
    _source = p.getString('tr_source') ?? 'auto';
    _customUrl = p.getString('tr_api_url') ?? '';
    _apiKey = p.getString('tr_api_key') ?? '';
  }

  /// 翻译单段文本。失败时返回原文，保证阅读不中断。
  Future<String> translate(String text, {String? source, String? target}) async {
    final src = source ?? _source;
    final tgt = target ?? _target;
    if (text.trim().isEmpty) return text;
    final key = '${src}_$tgt::$text';
    if (_memCache.containsKey(key)) return _memCache[key]!;
    try {
      String result;
      if (_customUrl.isNotEmpty) {
        result = await _translateCustom(text, src, tgt);
      } else {
        result = await _translateGoogle(text, src, tgt);
      }
      _memCache[key] = result;
      return result;
    } catch (_) {
      return text; // 网络失败回退原文
    }
  }

  /// 按段落批量翻译并保持换行结构
  Future<String> translateParagraphs(String content, {String? source, String? target}) async {
    final paras = content.split(RegExp(r'\n+'));
    final out = <String>[];
    for (final p in paras) {
      if (p.trim().isEmpty) {
        out.add(p);
      } else {
        out.add(await translate(p, source: source, target: target));
      }
    }
    return out.join('\n\n');
  }

  Future<String> _translateGoogle(String text, String src, String tgt) async {
    final resp = await _dio.get(
      'https://translate.googleapis.com/translate_a/single',
      queryParameters: {'client': 'gtx', 'sl': src, 'tl': tgt, 'dt': 't', 'q': text},
      options: Options(headers: {'User-Agent': 'Mozilla/5.0'}),
    );
    final data = resp.data;
    final dynamic decoded = data is String ? jsonDecode(data) : data;
    if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
      final sb = StringBuffer();
      for (final seg in decoded[0]) {
        if (seg is List && seg.isNotEmpty && seg[0] != null) sb.write(seg[0]);
      }
      return sb.toString();
    }
    return text;
  }

  /// 自定义端点：以 {text}/{from}/{to}/{key} 占位，兼容常见自建翻译网关
  Future<String> _translateCustom(String text, String src, String tgt) async {
    var url = _customUrl
        .replaceAll('{text}', Uri.encodeQueryComponent(text))
        .replaceAll('{from}', src)
        .replaceAll('{to}', tgt)
        .replaceAll('{key}', _apiKey);
    final resp = await _dio.get(url);
    final data = resp.data;
    if (data is String) {
      final dynamic j = jsonDecode(data);
      if (j is Map) {
        return (j['translatedText'] ?? j['result'] ?? j['data'] ?? text).toString();
      }
      return data;
    }
    if (data is Map) return (data['translatedText'] ?? data['result'] ?? data['data'] ?? text).toString();
    return text;
  }

  void clearCache() => _memCache.clear();
}
