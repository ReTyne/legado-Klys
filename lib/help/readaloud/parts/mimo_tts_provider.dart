/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 MimoTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// Mimo TTS
class MimoTtsProvider extends CloudTtsProvider {
  MimoTtsProvider(CloudTtsEngine engine) : super(engine);

  @override
  String get name => 'Mimo';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        engine.url ?? 'https://api.mimo.ai/v1/tts',
        data: {'text': text, 'voice': voice ?? engine.voice ?? 'default', 'format': 'mp3'},
        options: Options(responseType: ResponseType.bytes, headers: {'Authorization': 'Bearer ${engine.apiKey ?? ''}'}),
      );
      return await saveAudio(response.data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async => ['default', 'male_1', 'male_2', 'female_1', 'female_2'];
}
