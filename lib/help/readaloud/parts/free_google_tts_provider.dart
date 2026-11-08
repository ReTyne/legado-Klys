/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 FreeGoogleTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// 云TTS提供商工厂
/// 免费谷歌朗读（translate_tts，免 key），返回本地 mp3 路径
class FreeGoogleTtsProvider extends CloudTtsProvider {
  FreeGoogleTtsProvider(CloudTtsEngine engine) : super(engine);

  @override
  String get name => '免费谷歌朗读';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      final tl = engine.voice ?? 'zh-CN';
      final q = Uri.encodeComponent(text);
      final url = 'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=$tl&q=$q';
      final resp = await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes, headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
            'Referer': 'https://translate.google.com/',
          }));
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async =>
      ['zh-CN', 'zh-TW', 'en-US', 'en-GB', 'ja-JP', 'ko-KR', 'fr-FR', 'de-DE', 'es-ES', 'ru-RU'];
}
