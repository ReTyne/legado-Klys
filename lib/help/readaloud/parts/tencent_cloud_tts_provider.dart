/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 TencentCloudTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// 腾讯云TTS
class TencentCloudTtsProvider extends CloudTtsProvider {
  TencentCloudTtsProvider(CloudTtsEngine engine) : super(engine);

  @override
  String get name => '腾讯云';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        engine.url ?? 'https://tts.tencentcloudapi.com',
        data: {'Text': text, 'VoiceType': voice ?? engine.voice ?? '101001', 'Codec': 'mp3'},
        options: Options(responseType: ResponseType.bytes, headers: {'X-TC-Action': 'TextToVoice', 'X-TC-Version': '2019-08-23', 'Authorization': engine.apiKey ?? ''}),
      );
      return await saveAudio(response.data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async => ['101001', '101002', '101003', '101004', '101005'];
}
