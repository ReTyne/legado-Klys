import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:legado_md3/data/model/db_models.dart';

part 'parts/alibaba_cloud_tts_provider.dart';
part 'parts/tencent_cloud_tts_provider.dart';
part 'parts/azure_tts_provider.dart';
part 'parts/open_ai_tts_provider.dart';
part 'parts/volcengine_tts_provider.dart';
part 'parts/aws_polly_tts_provider.dart';
part 'parts/gemini_tts_provider.dart';
part 'parts/mimo_tts_provider.dart';
part 'parts/free_google_tts_provider.dart';
part 'parts/cloud_tts_provider_factory.dart';
part 'parts/http_tts_provider.dart';

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
