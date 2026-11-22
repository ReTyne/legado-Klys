import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/audio/audio_playback_controller.dart';
import 'package:legado_md3/help/readaloud/cloud_tts_providers.dart';
import 'package:legado_md3/help/readaloud/tts_service.dart';
import 'package:legado_md3/ui/book/video/video_player_screen.dart';

void main() {
  group('朗读清洗与简繁一致', () {
    test('HTML 正文被剥离且保留段落结构', () {
      final text = TtsService.cleanForReadAloud(
          '<p>第一段</p><p>第二段</p>', converterMode: 0);
      expect(text, contains('第一段'));
      expect(text, contains('第二段'));
      expect(text, isNot(contains('<p>')));
    });

    test('整段纯标点/空白不参与朗读', () {
      final text = TtsService.cleanForReadAloud('正文\n！！！\n……\n结尾');
      expect(text, contains('正文'));
      expect(text, contains('结尾'));
      expect(text, isNot(contains('！！！')));
      expect(TtsService.notReadAloudRe.hasMatch('  。！？ '), isTrue);
    });

    test('简繁模式透传到朗读文本', () {
      final plain = TtsService.cleanForReadAloud('汉字转换', converterMode: 0);
      final traditional = TtsService.cleanForReadAloud('汉字转换', converterMode: 2);
      expect(plain, '汉字转换');
      expect(traditional, isNot(plain));
    });
  });

  group('HTTP TTS 语速占位符', () {
    const tpl = 'https://x/tts?text={{text}}&speed={{speakSpeed}}';
    test('speakSpeed 为整数且随语速变化（1.0 倍 = 10）', () {
      expect(substituteHttpTts(tpl, '你好', 1.0), contains('speed=10'));
      expect(substituteHttpTts(tpl, '你好', 1.5), contains('speed=15'));
      expect(substituteHttpTts(tpl, '你好', 0.5), contains('speed=5'));
    });

    test('文本占位符做 URL 编码', () {
      final out = substituteHttpTts(tpl, '你 好', 1.0);
      expect(out, isNot(contains('text=你 好')));
      expect(out, contains(Uri.encodeComponent('你 好')));
    });
  });

  group('视频倍速弹幕联动', () {
    test('播放倍速越高弹幕滚动系数越小', () {
      expect(danmakuSpeedFactor(1.0), 1.0);
      expect(danmakuSpeedFactor(2.0), lessThan(danmakuSpeedFactor(1.0)));
      expect(danmakuSpeedFactor(6.0), greaterThanOrEqualTo(0.2));
    });

    test('线路地址解析与非法地址识别', () {
      expect(resolveCurrentPlayUrl([' a.mp4 ', 'b.mp4'], 0), 'a.mp4');
      expect(resolveCurrentPlayUrl([], 3), '');
      expect(parsePlayUrl('https://x/a.m3u8')?.scheme, 'https');
    });
  });

  group('音频片头片尾按书', () {
    test('不同书生成不同持久化键', () {
      final a = audioSkipKey('audio_skip_start', '书A', '作者甲');
      final b = audioSkipKey('audio_skip_start', '书B', '作者甲');
      expect(a, isNot(b));
      expect(a, contains('书A'));
    });
  });
}
