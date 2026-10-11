import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:legado_md3/data/model/cloud_tts_engine.dart';

/// 云TTS提供商基类
abstract class CloudTtsProvider {
  final CloudTtsEngine engine;
  CloudTtsProvider(this.engine);

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
        options: Options(headers: {
          'X-NLS-Token': engine.apiKey ?? '',
          'Content-Type': 'application/json',
        }),
      );
      return response.data.toString();
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
        options: Options(headers: {'X-TC-Action': 'TextToVoice', 'X-TC-Version': '2019-08-23', 'Authorization': engine.apiKey ?? ''}),
      );
      return response.data['Audio']?.toString();
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
        options: Options(headers: {
          'Ocp-Apim-Subscription-Key': engine.apiKey ?? '',
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
        }),
      );
      return response.data.toString();
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
        options: Options(headers: {'Authorization': 'Bearer ${engine.apiKey ?? ''}', 'Content-Type': 'application/json'}),
      );
      return response.data.toString();
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
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return response.data['data']?.toString();
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
        options: Options(headers: {'Authorization': engine.apiKey ?? ''}),
      );
      return response.data.toString();
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
      final response = await dio.post(
        engine.url ?? 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent',
        data: {'contents': [{'parts': [{'text': '请朗读以下文本：$text'}]}]},
        queryParameters: {'key': engine.apiKey ?? ''},
      );
      return response.data.toString();
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getVoices() async => ['default', 'male', 'female'];
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
        options: Options(headers: {'Authorization': 'Bearer ${engine.apiKey ?? ''}'}),
      );
      return response.data.toString();
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
