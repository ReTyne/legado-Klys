import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:legado_md3/data/model/db_models.dart';
/// 云TTS提供商基类
abstract class CloudTtsProvider {
  final CloudTtsEngine engine;
  CloudTtsProvider(this.engine);

  /// 把云厂商响应落地为本地音频文件并返回路径。
  /// 各厂商返回形态不一：有的直接是音频字节，有的返回含 base64 的 JSON，
  /// 有的直接返回 base64 字符串。这里统一识别后写盘，保证调用方
  /// （tts_service 用 DeviceFileSource(path) 播放）拿到的是可播放的本地路径。
  Future<String?> saveAudio(dynamic data, {String ext = 'mp3'}) async {
    final bytes = audioBytes(data);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 从响应体中提取音频字节；无法识别为音频时返回 null（调用方跳过该段）。
  static List<int>? audioBytes(dynamic data) {
    if (data == null) return null;
    if (data is List<int>) {
      // 少数厂商虽返回字节流，但内容是包裹 base64 的 JSON 文本，需再解析一次
      if (_looksLikeJson(data)) return audioBytes(_decodeJson(data));
      return data;
    }
    if (data is String) return _tryBase64(data);
    if (data is Map) return _bytesFromMap(data);
    return null;
  }

  /// 从 Map 中取音频：优先常见 base64 字段，兼容 Gemini 的嵌套结构。
  static List<int>? _bytesFromMap(Map<dynamic, dynamic> m) {
    const keys = [
      'Audio', 'audio', 'audioContent', 'audio_content', 'data', 'Data',
      'result', 'content'
    ];
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) {
        final b = _tryBase64(v);
        if (b != null) return b;
      } else if (v is List<int> && v.isNotEmpty) {
        return v;
      }
    }
    // Gemini：candidates[0].content.parts[0].inlineData.data
    final cands = m['candidates'];
    if (cands is List && cands.isNotEmpty) {
      final first = cands.first;
      if (first is Map) {
        final content = first['content'];
        if (content is Map) {
          final parts = content['parts'];
          if (parts is List && parts.isNotEmpty) {
            final part = parts.first;
            if (part is Map) {
              final inline = part['inlineData'] ?? part['inline_data'];
              if (inline is Map) {
                final d = inline['data'];
                if (d is String) return _tryBase64(d);
              }
            }
          }
        }
      }
    }
    return null;
  }

  /// 首字符为 '{' 或 '[' 视为 JSON 文本（跳过空白）
  static bool _looksLikeJson(List<int> data) {
    for (final b in data) {
      if (b == 32 || b == 10 || b == 13 || b == 9) continue;
      return b == 0x7B || b == 0x5B;
    }
    return false;
  }

  static dynamic _decodeJson(List<int> data) {
    try {
      return jsonDecode(utf8.decode(data, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  /// 尝试按 base64 解码；非法 base64 返回 null
  static List<int>? _tryBase64(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    if (t.length % 4 != 0) return null;
    if (!RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(t)) return null;
    try {
      return base64Decode(t);
    } catch (_) {
      return null;
    }
  }

  /// 合成语音，返回音频URL或本地路径
  Future<String?> synthesize(String text, {String? voice, double? rate, double? pitch});

  /// 获取可用语音列表
  Future<List<String>> getVoices();

  /// 提供商名称
  String get name;
}

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

/// Azure语音TTS
class AzureTtsProvider extends CloudTtsProvider {
  AzureTtsProvider(CloudTtsEngine engine) : super(engine);

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

/// OpenAI TTS
class OpenAiTtsProvider extends CloudTtsProvider {
  OpenAiTtsProvider(CloudTtsEngine engine) : super(engine);

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

/// AWS Polly TTS
class AwsPollyTtsProvider extends CloudTtsProvider {
  AwsPollyTtsProvider(CloudTtsEngine engine) : super(engine);

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

/// Google Gemini TTS
class GeminiTtsProvider extends CloudTtsProvider {
  GeminiTtsProvider(CloudTtsEngine engine) : super(engine);

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

class CloudTtsProviderFactory {
  static CloudTtsProvider? create(CloudTtsEngine engine) {
    switch (engine.type.toLowerCase()) {
      case 'aliyun':
      case 'alibaba':
        return AlibabaCloudTtsProvider(engine);
      case 'tencent':
        return TencentCloudTtsProvider(engine);
      case 'azure':
      case 'microsoft':
        return AzureTtsProvider(engine);
      case 'openai':
        return OpenAiTtsProvider(engine);
      case 'volcengine':
      case 'bytedance':
        return VolcengineTtsProvider(engine);
      case 'aws':
      case 'polly':
        return AwsPollyTtsProvider(engine);
      case 'gemini':
      case 'google':
        return GeminiTtsProvider(engine);
      case 'mimo':
        return MimoTtsProvider(engine);
      case 'free_google':
      case 'free':
        return FreeGoogleTtsProvider(engine);
      default:
        return null;
    }
  }

  static List<String> get allProviderTypes => [
    'aliyun', 'tencent', 'azure', 'openai', 'volcengine', 'aws', 'gemini', 'mimo', 'free_google',
  ];

  static String getProviderName(String type) {
    switch (type.toLowerCase()) {
      case 'aliyun': return '阿里云';
      case 'tencent': return '腾讯云';
      case 'azure': return 'Azure';
      case 'openai': return 'OpenAI';
      case 'volcengine': return '火山引擎';
      case 'aws': return 'AWS Polly';
      case 'gemini': return 'Gemini';
      case 'mimo': return 'Mimo';
      case 'free_google': case 'free': return '免费谷歌朗读(免Key)';
      default: return type;
    }
  }
}
