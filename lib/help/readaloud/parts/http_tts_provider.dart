/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 HttpTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// 自定义 HTTP TTS 适配器（把 `http_tts` 表的 [HttpTTS] 配置接入统一朗读链路）。
///
/// legado 书源的 httpTTS 约定：url / headers / body 里可含占位符
/// `{{text}}`、`{{speakText}}`、`{{speakSpeed}}`，合成时用实际文本替换。
/// 支持 GET（占位符拼进 URL）与 POST（占位符拼进 body，按 JSON 或表单发送）。
/// 响应统一经基类 `saveAudio` 落地为本地音频文件，供 TtsService 播放。
class HttpTtsProvider extends CloudTtsProvider {
  HttpTtsProvider(HttpTTS cfg)
      : _cfg = cfg,
        super(CloudTtsEngine(
          name: cfg.name,
          type: 'http',
          url: cfg.url,
          enabled: cfg.enabled,
        ));

  final HttpTTS _cfg;

  @override
  String get name => _cfg.name;

  Map<String, String> _headers(String text) {
    final raw = _cfg.headers;
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(_substitute(raw, text));
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return <String, String>{};
  }

  String _substitute(String template, String text) => template
      .replaceAll('{{text}}', Uri.encodeComponent(text))
      .replaceAll('{{speakText}}', Uri.encodeComponent(text))
      .replaceAll('{{speakSpeed}}', '1')
      .replaceAll('\${text}', Uri.encodeComponent(text));

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.bytes,
      ));
      final url = _substitute(_cfg.url, text);
      final method = (_cfg.method ?? 'GET').toUpperCase();
      final headers = _headers(text);
      final Response<dynamic> resp;
      if (method == 'POST') {
        var body = _substitute(_cfg.body ?? '', text);
        dynamic data = body;
        final jsonHeader = headers.entries.any((e) =>
            e.key.toLowerCase() == 'content-type' &&
            e.value.toLowerCase().contains('json'));
        if (jsonHeader || body.trim().startsWith('{')) {
          try {
            data = jsonDecode(body.replaceAll(Uri.encodeComponent(text), text));
          } catch (_) {}
        }
        resp = await dio.post(url, data: data, options: Options(headers: headers));
      } else {
        resp = await dio.get(url, options: Options(headers: headers));
      }
      return await saveAudio(resp.data);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async => const <String>['default'];
}
