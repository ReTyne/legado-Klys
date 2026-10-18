/// 云端 TTS 提供者抽象与通用数据结构
abstract class CloudTtsProvider {
  /// 提供者标识
  String get id;
  /// 展示名称
  String get name;
  /// 是否需要密钥
  bool get needKey;
  /// 获取可用音色列表
  Future<List<CloudVoice>> voices();
  /// 合成语音，返回音频字节
  Future<List<int>?> synthesize(String text, {required String voice, double rate = 1.0});
}

/// 音色
class CloudVoice {
  final String id;
  final String name;
  final String? locale;
  final String? gender;
  const CloudVoice({required this.id, required this.name, this.locale, this.gender});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'locale': locale, 'gender': gender};
  factory CloudVoice.fromJson(Map<String, dynamic> j) => CloudVoice(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    locale: j['locale']?.toString(),
    gender: j['gender']?.toString(),
  );
}
