/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 AlibabaCloudTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// 阿里云TTS
class AlibabaCloudTtsProvider extends CloudTtsProvider {
  AlibabaCloudTtsProvider(CloudTtsEngine engine) : super(engine);

  @override
  String get name => '阿里云';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        engine.url ?? 'https://nls-gateway.cn-shanghai.aliyuncs.com/stream/v1/tts',
        data: {
          'text': text,
          'voice': voice ?? engine.voice ?? 'xiaoyun',
          'rate': rate ?? (engine.rate ?? 0),
          'pitch': pitch ?? (engine.pitch ?? 0),
          'format': 'mp3',
          'sample_rate': 16000,
        },
        options: Options(responseType: ResponseType.bytes, headers: {
          'X-NLS-Token': engine.apiKey ?? '',
          'Content-Type': 'application/json',
        }),
      );
      return await saveAudio(response.data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async {
    return ['xiaoyun', 'xiaogang', 'xiaomeng', 'xiaoyan', 'xiaofeng', 'xiaomei', 'xiaolin', 'xiaorui'];
  }
}
