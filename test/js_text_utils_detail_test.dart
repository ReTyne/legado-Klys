import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/js_text_utils.dart';

/// 对照上游 legado-E：
///  * `utils/StringUtils.kt`（fullToHalf / stringToInt / chineseNumToInt）
///  * `constant/AppPattern.kt` + `help/JsExtensions.kt`（toNumChapter）
///  * `utils/HtmlFormatter.kt`（formatKeepImg）
///  * `help/JsExtensions.kt`（strToBytes / bytesToStr / replaceFont）
void main() {
  group('StringUtils 语义', () {
    test('fullToHalf：全角空格与全角 ASCII 转半角', () {
      expect(JsTextUtils.fullToHalf('ＡＢＣ１２３'), 'ABC123');
      expect(JsTextUtils.fullToHalf('Ａ\u3000Ｂ'), 'A B');
      expect(JsTextUtils.fullToHalf('abc'), 'abc');
      // 上游 if (code in 65281..65374)：全角逗号 U+FF0C 在范围内 → 半角，
      // 全角句号 U+3002 不在范围内 → 原样。
      expect(JsTextUtils.fullToHalf('，'), ',');
      expect(JsTextUtils.fullToHalf('。'), '。');
    });

    test('stringToInt：全角数字、阿拉伯数字、空白', () {
      expect(JsTextUtils.stringToInt('１２３'), 123);
      expect(JsTextUtils.stringToInt(' 1 2 3 '), 123);
      expect(JsTextUtils.stringToInt(null), -1);
      // 上游 parseInt("") 失败 → chineseNumToInt("") → 0
      expect(JsTextUtils.stringToInt(''), 0);
    });

    test('stringToInt：中文数字回落', () {
      expect(JsTextUtils.stringToInt('一零二五'), 1025);
      expect(JsTextUtils.stringToInt('一千零二十五'), 1025);
      expect(JsTextUtils.stringToInt('一千二'), 1200);
      expect(JsTextUtils.stringToInt('壹佰'), 100);
      expect(JsTextUtils.stringToInt('abc'), -1);
    });

    test('chineseNumToInt：逐字拼接 / 带单位 / 亿与万', () {
      expect(JsTextUtils.chineseNumToInt('一零二五'), 1025);
      expect(JsTextUtils.chineseNumToInt('一千零二十五'), 1025);
      expect(JsTextUtils.chineseNumToInt('一千二'), 1200);
      expect(JsTextUtils.chineseNumToInt('两百三'), 230);
      expect(JsTextUtils.chineseNumToInt('一亿'), 100000000);
      expect(JsTextUtils.chineseNumToInt('一'), 1);
      expect(JsTextUtils.chineseNumToInt(''), 0);
      expect(JsTextUtils.chineseNumToInt('未知'), -1);
    });
  });

  group('toNumChapter（对齐 AppPattern.titleNumPattern = (第)(.+?)(章)）', () {
    test('中文数字章节转阿拉伯数字（上游只返回 group1+数字+group3，丢后缀）', () {
      expect(JsTextUtils.toNumChapter('第一章 觉醒'), '第1章');
      expect(JsTextUtils.toNumChapter('第一百零二章 风起'), '第102章');
      expect(JsTextUtils.toNumChapter('第一千二章'), '第1200章');
    });

    test('阿拉伯/全角数字章节规范化', () {
      expect(JsTextUtils.toNumChapter('第0012章'), '第12章');
      expect(JsTextUtils.toNumChapter('第１２章'), '第12章');
    });

    test('无「第..章」或 null 时原样返回', () {
      expect(JsTextUtils.toNumChapter('序章 楔子'), '序章 楔子');
      expect(JsTextUtils.toNumChapter(''), '');
      expect(JsTextUtils.toNumChapter(null), isNull);
    });
  });

  group('htmlFormat（对齐 HtmlFormatter.formatKeepImg）', () {
    test('保留 <img> 并规范化 src', () {
      final s = JsTextUtils.htmlFormat(
          '<p>正文</p><img src="https://x/a.jpg" width="20">');
      expect(s, contains('<img src="https://x/a.jpg">'));
      expect(s, isNot(contains('<p>')));
      expect(s, isNot(contains('width=')));
      expect(s, contains('正文'));
    });

    test('懒加载 data-src 优先于占位 src', () {
      final s = JsTextUtils.htmlFormat(
          '<img src="placeholder.gif" data-src="real.jpg">');
      expect(s, contains('<img src="real.jpg">'));
      expect(s, isNot(contains('placeholder.gif')));
    });

    test('支持 data-original / 任意 data-* 兜底', () {
      expect(
          JsTextUtils.htmlFormat('<img data-original="o.jpg">'),
          contains('<img src="o.jpg">'));
      expect(
          JsTextUtils.htmlFormat('<img data-echo="e.jpg">'),
          contains('<img src="e.jpg">'));
    });

    test('块级标签转换行、段首两个全角空格、去实体与注释', () {
      final s = JsTextUtils.htmlFormat(
          '<div>第一段</div><p>第二段&nbsp;尾部</p><!-- c --><span>x</span>');
      expect(s, contains('第一段'));
      expect(s, contains('第二段'));
      expect(s, isNot(contains('<span>')));
      expect(s, isNot(contains('&nbsp;')));
      expect(s, isNot(contains('<!--')));
      expect(s.startsWith('　　'), isTrue);
    });

    test('空输入', () {
      // 上游 format("")：所有 replace 均无匹配，返回空串（indent2 需 ^[\n\s]+ 命中）。
      expect(JsTextUtils.htmlFormat(null), '');
      expect(JsTextUtils.htmlFormat(''), '');
    });
  });

  group('strToBytes / bytesToStr（Java charset 语义）', () {
    test('默认 UTF-8', () {
      final bytes = JsTextUtils.strToBytes('中文');
      expect(bytes.length, 6);
      expect(JsTextUtils.bytesToStr(bytes), '中文');
      expect(JsTextUtils.strToBytes('ABC'), [65, 66, 67]);
    });

    test('GBK 家族往返，别名归一化', () {
      for (final cs in ['GBK', 'GB2312', 'GB_2312', 'gb-2312', 'gb18030', 'cp936']) {
        final bytes = JsTextUtils.strToBytes('中文', charset: cs);
        expect(bytes.length, 4, reason: '$cs 应为双字节/字');
        expect(JsTextUtils.bytesToStr(bytes, charset: cs), '中文',
            reason: '$cs 往返');
      }
    });

    test('Latin-1 家族往返', () {
      final bytes = JsTextUtils.strToBytes('ABC', charset: 'ISO-8859-1');
      expect(bytes, [65, 66, 67]);
      expect(JsTextUtils.bytesToStr(bytes, charset: 'ISO_8859_1'), 'ABC');
    });

    test('UTF-8 别名与未知字符集回退', () {
      expect(JsTextUtils.bytesToStr(JsTextUtils.strToBytes('中文', charset: 'UTF-8')),
          '中文');
      expect(JsTextUtils.strToBytes('中文', charset: 'unknown-xyz').length, 6);
    });
  });

  group('JS 桥与协议接线契约（防止回退为假实现）', () {
    final bridge = File('lib/help/source/js/bridge/legado_bridge_js_08.dart')
        .readAsStringSync();
    final runtime = File('lib/help/source/js/parts/web_view_legado_js.dart')
        .readAsStringSync();
    final runtimeLib = File('lib/help/source/js/legado_js_runtime.dart')
        .readAsStringSync();

    test('4 个扩展函数均转交 legado://charset', () {
      expect(bridge, contains('legado://charset?op=htmlFormat'));
      expect(bridge, contains('legado://charset?op=toNumChapter'));
      expect(bridge, contains('legado://charset?op=encode'));
      expect(bridge, contains('legado://charset?op=decode'));
    });

    test('旧的「一刀切去标签 / parseInt / 忽略 charset」实现已移除', () {
      // htmlFormat 无论主路径还是降级路径都必须保留 <img>：
      // 旧的「去所有标签」模式 .replace(/<[^>]+>/g, "") 不应再出现。
      expect(bridge.contains(r'.replace(/<[^>]+>/g, "")'), isFalse,
          reason: 'htmlFormat 不应再把所有标签（含 img）一刀切去掉');
      expect(bridge, contains('(?!img'),
          reason: '降级路径应用负向前瞻保留 img 标签');
      expect(bridge.contains('parseInt(m[2], 10)'), isFalse,
          reason: 'toNumChapter 不应只做去前导零');
      expect(bridge.contains('new TextEncoder().encode(String(str'),
          isTrue, reason: 'TextEncoder 仅作为协议不可用时的 UTF-8 兜底');
      expect(bridge, contains('charset || "UTF-8"'),
          reason: 'strToBytes/bytesToStr 必须把 charset 传给 Dart 侧');
    });

    test('协议分发与 Dart 侧真实消费 JsTextUtils', () {
      // 主库文件提供 import（part 文件共享其命名空间）
      expect(runtimeLib, contains('js_text_utils.dart'));
      expect(runtime, contains("url.startsWith('legado://charset')"));
      expect(runtime, contains('_handleCharset'));
      expect(runtime, contains('JsTextUtils.strToBytes'));
      expect(runtime, contains('JsTextUtils.bytesToStr'));
      expect(runtime, contains('JsTextUtils.htmlFormat'));
      expect(runtime, contains('JsTextUtils.toNumChapter'));
    });

    test('replaceFont 明确标注 TTF 轮廓反查无法等价实现', () {
      expect(bridge, contains('QueryTTF'));
      expect(bridge, contains('Flutter'));
    });
  });
}
