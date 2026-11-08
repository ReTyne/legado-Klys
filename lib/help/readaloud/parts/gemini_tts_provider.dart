/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 GeminiTtsProvider。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


/// Google Gemini TTS
class GeminiTtsProvider extends CloudTtsProvider {
  GeminiTtsProvider(super.engine);

  @override
  String get name => 'Gemini';

  @override
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch}) async {
    try {
      final dio = Dio();
      // 必须使用 Gemini 的 TTS 专用接口（responseModalities: AUDIO），
      // 而非 generateContent 文本接口，否则只返回文本、永远拿不到音频。
      final voiceName = voice ?? engine.voice ?? 'Kore';
      final response = await dio.post(
        engine.url ?? 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent',
        queryParameters: {'key': engine.apiKey ?? ''},
        data: {
          'contents': [
            {'parts': [{'text': text}]}
          ],
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {'prebuiltVoiceConfig': {'voiceName': voiceName}}
            }
          }
        },
        options: Options(responseType: ResponseType.bytes),
      );
      // Gemini TTS 以 base64 把 16-bit PCM@24kHz mono 放在 inlineData.data，
      // 父类 audioBytes 已能正确提取该 PCM 字节。
      final pcm = CloudTtsProvider.audioBytes(response.data);
      if (pcm == null || pcm.isEmpty) return null;
      // 真实音频是裸 PCM 而非 mp3，封装为 WAV 方可被播放器识别。
      final wav = _pcmToWav(pcm, sampleRate: 24000, channels: 1, bitsPerSample: 16);
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav');
      await file.writeAsBytes(wav);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async =>
      ['Kore', 'Zephyr', 'Puck', 'Charon', 'Fenrir', 'Aoede', 'Leda', 'Orus'];

  /// 将裸 PCM 字节封装为标准 WAV 文件头（小端 16-bit）。
  static List<int> _pcmToWav(List<int> pcm,
      {required int sampleRate, required int channels, required int bitsPerSample}) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcm.length;
    final header = <int>[
      ...ascii.encode('RIFF'),
      ..._u32(36 + dataSize),
      ...ascii.encode('WAVE'),
      ...ascii.encode('fmt '),
      ..._u32(16),
      ..._u16(1), // PCM
      ..._u16(channels),
      ..._u32(sampleRate),
      ..._u32(byteRate),
      ..._u16(blockAlign),
      ..._u16(bitsPerSample),
      ...ascii.encode('data'),
      ..._u32(dataSize),
    ];
    return [...header, ...pcm];
  }

  static List<int> _u32(int v) =>
      [(v) & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  static List<int> _u16(int v) => [(v) & 0xff, (v >> 8) & 0xff];
}
