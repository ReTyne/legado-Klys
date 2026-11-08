/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 VolcengineTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// 火山引擎TTS
class VolcengineTtsProvider extends CloudTtsProvider {
  VolcengineTtsProvider(CloudTtsEngine engine) : super(engine);

  @override
  String get name => '火山引擎';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        engine.url ?? 'https://openspeech.bytedance.com/api/v1/tts',
        data: jsonEncode({
          'app': {'appid': engine.apiKey ?? '', 'token': '', 'cluster': 'volcano_tts'},
          'user': {'uid': 'legado'},
          'audio': {'voice_type': voice ?? engine.voice ?? 'BV001_streaming', 'encoding': 'mp3', 'speed_ratio': rate ?? 1.0, 'volume_ratio': 1.0, 'pitch_ratio': pitch ?? 1.0},
          'request': {'reqid': DateTime.now().millisecondsSinceEpoch.toString(), 'text': text, 'text_type': 'plain', 'operation': 'query'},
        }),
        options: Options(responseType: ResponseType.bytes, headers: {'Content-Type': 'application/json'}),
      );
      return await saveAudio(response.data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async => ['BV001_streaming', 'BV002_streaming', 'BV003_streaming', 'BV004_streaming', 'BV005_streaming', 'BV006_streaming', 'BV007_streaming', 'BV008_streaming'];
}
