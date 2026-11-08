/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 OpenAiTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// OpenAI TTS
class OpenAiTtsProvider extends CloudTtsProvider {
  OpenAiTtsProvider(super.engine);

  @override
  String get name => 'OpenAI';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        engine.url ?? 'https://api.openai.com/v1/audio/speech',
        data: {'model': 'tts-1', 'input': text, 'voice': voice ?? engine.voice ?? 'alloy', 'response_format': 'mp3', 'speed': rate ?? 1.0},
        options: Options(responseType: ResponseType.bytes, headers: {'Authorization': 'Bearer ${engine.apiKey ?? ''}', 'Content-Type': 'application/json'}),
      );
      return await saveAudio(response.data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async => ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
}
