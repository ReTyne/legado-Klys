/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 AzureTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// Azure语音TTS
class AzureTtsProvider extends CloudTtsProvider {
  AzureTtsProvider(super.engine);

  @override
  String get name => 'Azure';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      final ssml = '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="zh-CN"><voice name="${voice ?? engine.voice ?? 'zh-CN-XiaoxiaoNeural'}"><prosody rate="${rate ?? 1.0}" pitch="${pitch ?? 0}Hz">$text</prosody></voice></speak>';
      final response = await dio.post(
        engine.url ?? 'https://${engine.region ?? 'eastasia'}.tts.speech.microsoft.com/cognitiveservices/v1',
        data: ssml,
        options: Options(responseType: ResponseType.bytes, headers: {
          'Ocp-Apim-Subscription-Key': engine.apiKey ?? '',
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
        }),
      );
      return await saveAudio(response.data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async => ['zh-CN-XiaoxiaoNeural', 'zh-CN-YunxiNeural', 'zh-CN-YunjianNeural', 'zh-CN-XiaoyiNeural', 'zh-CN-YunyangNeural'];
}
