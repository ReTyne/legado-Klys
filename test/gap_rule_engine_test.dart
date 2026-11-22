import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/parts/engine_primitives.dart';
import 'package:legado_md3/help/source/rule_data.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/source/source_engine.dart';

void main() {
  group('缺口1：变量长短值互斥写入', () {
    test('短值不被旧大值遮蔽', () {
      final rd = RuleData();
      final long = 'X' * RuleData.bigValueThreshold;
      rd.putVariable('k', long);
      expect(rd.getVariable('k'), long);
      expect(rd.layerSnapshot('ruleData').containsKey('k'), isFalse);

      rd.putVariable('k', 'short');
      expect(rd.getVariable('k'), 'short');
      expect(rd.getBigVariable('k'), 'short');
      expect(rd.variableMap['k'], 'short');
    });

    test('长值从所有层移除并只进外置存储', () {
      final rd = RuleData();
      rd.putVariable('k', 'old', layer: 'book');
      final long = 'Y' * (RuleData.bigValueThreshold + 1);
      rd.putVariable('k', long);
      expect(rd.getVariable('k'), long);
      expect(rd.layerSnapshot('book').containsKey('k'), isFalse);
      expect(rd.layerSnapshot('ruleData').containsKey('k'), isFalse);

      rd.putVariable('k', 'new');
      expect(rd.getVariable('k'), 'new');
    });

    test('null 删除变量，空值写入层并支持回退', () {
      final rd = RuleData();
      rd.putVariable('k', 'v');
      rd.putVariable('k', null);
      expect(rd.getVariable('k'), '');
      expect(rd.variableMap.containsKey('k'), isFalse);

      rd.putInLayer('book', 'k', 'bk');
      rd.putInLayer('chapter', 'k', '');
      expect(rd.getVariable('k'), 'bk');
    });
  });

  group('缺口2：@get 上下文取值与回退', () {
    RulePipeline withContext() => RulePipeline(contextValueResolver: (key) {
          switch (key) {
            case 'bookName':
              return '测试书名';
            case 'title':
              return '第一章';
            case 'layered':
              return '分层值';
            default:
              return null;
          }
        });

    test('bookName/title 特殊键由回调提供', () {
      final p = withContext();
      expect(p.substituteGets('@get:{bookName}'), '测试书名');
      expect(p.substituteGets('@get:{title}'), '第一章');
    });

    test('其余键先本地后回调，默认值仍生效', () {
      final p = withContext();
      p.variables['local'] = '本地值';
      expect(p.substituteGets('@get:{local}'), '本地值');
      expect(p.substituteGets('@get:{layered}'), '分层值');
      expect(p.substituteGets('@get:{missing||兜底}'), '兜底');
      expect(p.substituteGets('@get:{missing}'), '');
    });

    test('无回调时行为不变', () {
      final p = RulePipeline();
      p.variables['k'] = 'v';
      expect(p.substituteGets('@get:{k}'), 'v');
      expect(p.substituteGets('@get:{bookName}'), '');
      expect(p.substituteGets('@get:{bookName||默认}'), '默认');
    });
  });

  group('缺口3：html getter 与属性去重', () {
    test('@css:...@html 返回 outerHtml 并剔除 script/style', () {
      const raw =
          '<div class="c"><p>正文</p><script>bad()</script><style>.x{}</style></div>';
      final out = RulePipeline().extractStringFromRaw(raw, '@css:.c@html');
      expect(out, isNotNull);
      expect(out, contains('<div'));
      expect(out, contains('正文'));
      expect(out, isNot(contains('bad')));
      expect(out, isNot(contains('.x{}')));
    });

    test('joinedHtmlAll 合并整组 outerHtml', () {
      expect(RulePipeline().joinedHtmlAll('<p>A</p><p>B</p>', '@css:p@html'),
          '<p>A</p><p>B</p>');
    });

    test('属性 getter 去重且保持顺序', () {
      const raw = '<a href="/1">一</a><a href="/1">二</a><a href="/2">三</a>';
      expect(RulePipeline().extractListFromRaw(raw, '@css:a@href'),
          ['/1', '/2']);
    });
  });

  group('缺口4：刷新目录标记消费', () {
    test('prelude 定义能力，标记可被识别', () {
      final prelude = buildPreUpdateJsPrelude();
      expect(prelude, contains(kReGetBookMarker));
      expect(prelude, contains(kRefreshTocUrlMarker));
      expect(preUpdateRequestsRefreshTocUrl('$prelude refreshTocUrl();'),
          isTrue);
      expect(preUpdateRequestsRefreshTocUrl('none'), isFalse);
      expect(preUpdateRequestsReGetBook('$prelude reGetBook();'), isTrue);
    });
  });

  group('缺口5：HTML 实体反转义', () {
    test('unescape 选项解码命名与数字实体，默认关闭', () {
      final p = RulePipeline();
      const raw = 'Tom &amp; &#x4E2D;&#25991; &unknown;';
      expect(p.extractStringFromRaw(raw, '', unescape: true),
          'Tom & 中文 &unknown;');
      expect(p.extractStringFromRaw(raw, ''), raw);
    });
  });

  group('缺口6：关键词占位符替换', () {
    test('{{key}} 使用原始未编码关键字', () {
      expect(
          BookSourceEngine.processUrlTemplate(
              'https://x.com/s?q={{key}}&p={{page}}', '中文', 3),
          'https://x.com/s?q=中文&p=3');
      expect(
          BookSourceEngine.processUrlTemplate(
              'https://x.com/s?q={{key}}', 'a b', 1),
          'https://x.com/s?q=a b');
      expect(
          BookSourceEngine.processUrlTemplate(
              'https://x.com/s?n={{ (page-1)*10 }}', '中', 4),
          'https://x.com/s?n={{ (page-1)*10 }}');
      expect(
          BookSourceEngine.processUrlTemplate(
              'https://x.com/s?n={{(page-1)*10}}', '中', 4),
          'https://x.com/s?n=30');
      expect(
          BookSourceEngine.processUrlTemplate(
              'https://x.com/s?k={{searchKey}}', '中文', 1),
          'https://x.com/s?k=${Uri.encodeComponent('中文')}');
    });
  });

  group('缺口7：URL 规则 JS 块链式执行', () {
    test('无 JS 块时原样返回', () async {
      final out = await BookSourceEngine.resolveUrlJsChain(
          'https://x.com/s?q={{key}}', (script, result) async => null);
      expect(out, 'https://x.com/s?q={{key}}');
    });

    test('单块结果作为 URL，尾部 @result 片段替换结果', () async {
      final out = await BookSourceEngine.resolveUrlJsChain(
          '<js>"https://x.com/s";</js>@result?p=1', (script, result) async {
        expect(result, contains('<js>'));
        return 'https://x.com/s';
      });
      expect(out, 'https://x.com/s?p=1');
    });

    test('脚本未产出有效结果时返回空串', () async {
      final out = await BookSourceEngine.resolveUrlJsChain(
          '<js>fail</js>', (script, result) async => null);
      expect(out, '');
    });

    test('多块链式：字面段替换 @result 后覆盖结果', () async {
      final seen = <String>[];
      final out = await BookSourceEngine.resolveUrlJsChain(
        '<js>base</js>/mid/@result/<js>result + "-end"</js>',
        (script, result) async {
          if (script.trim() == 'base') return 'A';
          seen.add(result);
          return '$result-end';
        },
      );
      expect(seen, ['/mid/A/']);
      expect(out, '/mid/A/-end');
    });

    test('@js: 前缀吞掉后续内容作为脚本', () async {
      final out = await BookSourceEngine.resolveUrlJsChain(
          '@js:build();', (script, result) async {
        expect(script, 'build();');
        return 'https://x.com/final';
      });
      expect(out, 'https://x.com/final');
    });
  });
}
