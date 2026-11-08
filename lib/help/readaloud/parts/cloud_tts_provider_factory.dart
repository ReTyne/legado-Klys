/// 由 cloud_tts_providers.dart 按「一类一文件」拆出的 CloudTtsProviderFactory。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../cloud_tts_providers.dart';


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
