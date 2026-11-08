/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 AwsPollyTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// AWS Polly TTS
class AwsPollyTtsProvider extends CloudTtsProvider {
  AwsPollyTtsProvider(super.engine);

  @override
  String get name => 'AWS Polly';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        engine.url ?? 'https://polly.${engine.region ?? 'us-east-1'}.amazonaws.com/v1/speech',
        data: {'Text': text, 'OutputFormat': 'mp3', 'VoiceId': voice ?? engine.voice ?? 'Zhiyu', 'SampleRate': '16000'},
        options: Options(responseType: ResponseType.bytes, headers: {'Authorization': engine.apiKey ?? ''}),
      );
      return await saveAudio(response.data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async => ['Zhiyu', 'Zhizhen', 'Zhiwei', 'Joanna', 'Matthew', 'Salli'];
}
