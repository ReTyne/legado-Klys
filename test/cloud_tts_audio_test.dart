import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/readaloud/cloud_tts_providers.dart';

/// 回归：云 TTS 各厂商响应必须能被识别为音频字节并落地为文件。
/// 修复前所有厂商都 `return response.data.toString()`，而 tts_service 用
/// DeviceFileSource(path) 播放，导致除免费谷歌外全部播放失败。
void main() {
  group('云TTS 音频负载识别', () {
    final audio = <int>[0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00]; // 'ID3' mp3 头
    final b64 = base64Encode(audio);

    test('字节流响应（阿里云/Azure/OpenAI/AWS）按音频原样处理', () {
      expect(CloudTtsProvider.audioBytes(audio), equals(audio));
    });

    test('Map 形式的 base64（腾讯云 Audio / 火山 data）可解出字节', () {
      expect(CloudTtsProvider.audioBytes({'Audio': b64}), equals(audio));
      expect(CloudTtsProvider.audioBytes({'data': b64}), equals(audio));
    });

    test('ResponseType.bytes 下的 JSON 报文也能解出字节', () {
      final jsonBytes = utf8.encode(jsonEncode({'data': b64}));
      expect(CloudTtsProvider.audioBytes(jsonBytes), equals(audio));
    });

    test('Gemini 嵌套结构可解出字节', () {
      final jsonBytes = utf8.encode(jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'inlineData': {'data': b64}}
              ]
            }
          }
        ]
      }));
      expect(CloudTtsProvider.audioBytes(jsonBytes), equals(audio));
    });

    test('纯 base64 字符串可解出字节', () {
      expect(CloudTtsProvider.audioBytes(b64), equals(audio));
    });

    test('非音频响应返回 null（调用方跳过该段，而非拿杂串去播放）', () {
      expect(CloudTtsProvider.audioBytes(null), isNull);
      expect(CloudTtsProvider.audioBytes('no-audio'), isNull);
      expect(CloudTtsProvider.audioBytes({'error': 'unauthorized'}), isNull);
    });
  });
}
