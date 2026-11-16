import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/entities/dict_rule.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/help/source/replace_rule_service.dart';
import 'package:legado_md3/help/source/txt_parser.dart';
import 'package:legado_md3/help/storage/rule_sub_auto_update.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/ui/config/dict_rule_screen.dart';

/// 书源管理 / 换源配套规则能力的单元验证，覆盖替换、字典、TxtToc、
/// RSS 分类、Web 接口字段往返与订阅对比预览。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReplaceRuleService.clearDebugLog();
    TxtParserService.clearDebugLog();
    RssService.removeSortCache();
  });

  // ==================== 替换规则 ====================

  group('替换规则服务', () {
    test('正则替换展开 \$1..\$9 捕获组', () {
      final rule = ReplaceRule(
        replaceSummary: '分组',
        replaceRule: r'(\w+)@(\w+)',
        replacement: r'$2-$1',
      );
      final svc = ReplaceRuleService([rule]);
      expect(svc.apply('mail: ab@cd', scope: 'content'), 'mail: cd-ab');
    });

    test('@js: 替换路径存在并执行注入的求值回调', () {
      final rule = ReplaceRule(
        replaceSummary: 'js',
        replaceRule: 'foo',
        replacement: '@js:result.toUpperCase()',
      );
      final seen = <String>[];
      final out = ReplaceRuleService([rule]).apply(
        'a foo b',
        scope: 'content',
        jsEval: (script, match, groups) {
          seen.add('$script|$match|${groups.length}');
          return 'JS(${match.toUpperCase()})';
        },
      );
      expect(out, 'a JS(FOO) b');
      expect(seen.single, contains('result.toUpperCase()'));
    });

    test('@js: 无运行时时安全降级为原值并记录日志', () {
      final rule = ReplaceRule(
        replaceSummary: 'js',
        replaceRule: 'foo',
        replacement: '@js:x',
      );
      final out = ReplaceRuleService([rule]).apply(
        'a foo b',
        scope: 'content',
        jsEnabled: false,
      );
      expect(out, 'a foo b');
      expect(ReplaceRuleService.debugLog.any((e) => e.contains('降级')), isTrue);
    });

    test('scope / excludeScope / group 与 isTitle / isContent 分通道生效', () {
      final scoped = ReplaceRule(
        replaceSummary: 's',
        replaceRule: '广告',
        replacement: '',
        scope: '玄幻',
      );
      expect(
        ReplaceRuleService([scoped])
            .apply('广告内容', scope: 'content', group: '玄幻'),
        '内容',
      );
      expect(
        ReplaceRuleService([scoped])
            .apply('广告内容', scope: 'content', group: '都市'),
        '广告内容',
      );

      final excl = ReplaceRule(
        replaceSummary: 'e',
        replaceRule: '广告',
        replacement: '',
        excludeScope: 'VIP',
      );
      expect(
        ReplaceRuleService([excl])
            .apply('广告', scope: 'content', bookName: 'VIP书'),
        '广告',
      );
      expect(
        ReplaceRuleService([excl])
            .apply('广告', scope: 'content', bookName: '普通书'),
        isEmpty,
      );

      final titleRule = ReplaceRule(
        replaceSummary: 't',
        replaceRule: '第',
        replacement: '§',
        isTitle: true,
        isContent: false,
      );
      expect(
        ReplaceRuleService([titleRule]).apply('第一章', scope: 'title'),
        '§一章',
      );
      expect(
        ReplaceRuleService([titleRule]).apply('第一章', scope: 'content'),
        '第一章',
      );
    });

    test('超时预算耗尽时返回原文并记录超时日志', () {
      final rule = ReplaceRule(
        replaceSummary: 't',
        replaceRule: 'foo',
        replacement: 'bar',
      );
      final out = ReplaceRuleService([rule]).apply(
        'a foo b',
        scope: 'content',
        timeout: Duration.zero,
      );
      expect(out, 'a foo b');
      expect(ReplaceRuleService.debugLog.any((e) => e.contains('超时')), isTrue);
    });

    test('applyRules 按 order 升序批量应用', () {
      final r1 = ReplaceRule(
          replaceSummary: 'first',
          replaceRule: 'A',
          replacement: 'B',
          order: 1);
      final r2 = ReplaceRule(
          replaceSummary: 'second',
          replaceRule: 'B',
          replacement: 'C',
          order: 2);
      final svc = ReplaceRuleService([r2, r1]);
      expect(
        svc.applyRules('A', [r2, r1]),
        'C',
      );
    });
  });

  // ==================== 字典三段规则 ====================

  group('字典三段规则', () {
    test('DictRuleSegments 支持 JSON 与 ||| 分隔的解析和编码', () {
      final seg = DictRuleSegments.parse(
        'https://d/{word}|||@css:.content|||copy',
      );
      expect(seg.urlRule, 'https://d/{word}');
      expect(seg.showRule, '@css:.content');
      expect(seg.buttonClick, 'copy');

      final round = DictRuleSegments.parse(seg.encode());
      expect(round.urlRule, seg.urlRule);
      expect(round.showRule, seg.showRule);
      expect(round.buttonClick, seg.buttonClick);
    });

    test('buildUrl / extractShow / clickAction 三段规则引擎生效', () {
      final engine = DictRuleEngine(
        jsEval: (script, result) => 'SHOW[$result]',
      );
      final rule = DictRule(
        name: '词典',
        url: 'https://fallback/{word}',
        rule: jsonEncode({
          'urlRule': 'https://dict/{word}',
          'showRule': '@js:result',
          'buttonClick': 'copy',
        }),
      );
      expect(engine.buildUrl(rule, '你好'), 'https://dict/%E4%BD%A0%E5%A5%BD');
      expect(engine.extractShow('<b>abc</b>', rule), 'SHOW[<b>abc</b>]');
      expect(engine.clickAction(rule, 'w').type, DictClickType.copy);
    });

    test('三段规则为空时回退 {word} 模板与净化原文', () {
      final engine = DictRuleEngine();
      final rule = DictRule(
        name: '旧版',
        url: 'https://x/?q={word}',
      );
      expect(engine.buildUrl(rule, 'a b'), 'https://x/?q=a%20b');
      expect(engine.extractShow('<p>hello &amp; hi</p>', rule), 'hello & hi');
      expect(engine.clickAction(rule, 'w').type, DictClickType.none);

      final singleRule = DictRule(
        name: '单段',
        url: '',
        rule: '@css:.x',
      );
      // 单段规则按 showRule 处理，buttonClick 为空时应为 none
      expect(engine.clickAction(singleRule, 'w').type, DictClickType.none);
    });

    test('buttonClick 的 open 动作展开 {word} 模板', () {
      final engine = DictRuleEngine();
      final rule = DictRule(
        name: 'o',
        url: '',
        rule: jsonEncode({
          'urlRule': '',
          'showRule': '',
          'buttonClick': 'https://open/{word}',
        }),
      );
      final action = engine.clickAction(rule, '关键词');
      expect(action.type, DictClickType.open);
      expect(action.value, contains(Uri.encodeComponent('关键词')));
    });
  });

  // ==================== TxtTocRule ====================

  group('TxtToc 规则', () {
    test('按命中数评分并自动选最优 TocRule，示例可匹配', () {
      const content = '第一章 开始\n正文\n第二章 继续\n正文\n第三章 结束';
      final good =
          TxtTocRule(name: '中文', chapterRule: r'^第[一二三]章', enable: true);
      final bad = TxtTocRule(name: '空', chapterRule: r'^XYZ', enable: true);
      expect(TxtParserService.scoreRule(content, good), 3);
      expect(TxtParserService.scoreRule(content, bad), 0);
      expect(TxtParserService.pickBestRule(content, [bad, good])?.name, '中文');
      expect(
        TxtParserService.matchesExample(TxtTocRule(
          name: 'e',
          chapterRule: r'^第\d+章',
          example: '第9章 测试',
        )),
        isTrue,
      );
    });

    test('replacement 净化支持 \$1 分组且 JS 块无运行时时降级', () {
      expect(
        TxtParserService.purifyTitle(
          '第1章 序',
          pattern: r'^第(\d+)章.*',
          replacement: 'CH\$1',
        ),
        'CH1',
      );
      final out = TxtParserService.purifyTitle(
        '第1章',
        replacement: '@js:whatever',
        jsEval: (script, title) => null,
      );
      expect(out, '第1章');
      expect(TxtParserService.debugLog.any((e) => e.contains('降级')), isTrue);
    });

    test('卷规则命中的行插入 isVolume 卷标章节', () {
      final rule = TxtTocRule(
        name: 'v',
        chapterRule: r'^第\d+章.*',
        volumeRule: r'^第.+卷.*',
        enable: true,
      );
      const content = '第一卷 风云\n引言\n第1章 开端\n正文\n第2章 发展\n正文';
      final chapters = TxtParserService().parseChapters(content, rule: rule);
      expect(chapters.where((c) => c.isVolume).length, 1);
      final vol = chapters.firstWhere((c) => c.isVolume);
      expect(vol.title, '第一卷 风云');
      expect(vol.url, startsWith('local://volume/'));
      expect(chapters.where((c) => !c.isVolume).length, 2);
    });
  });

  // ==================== RSS sortUrls ====================

  group('RSS sortUrls', () {
    test('parseSortText 支持 && / 换行 / title::url 与空结果回退', () {
      final parsed = RssService.parseSortText(
        '推荐::https://a && 最新::https://b\n科技::https://c',
        sourceUrl: 'https://fallback',
      );
      expect(parsed.length, 3);
      expect(parsed[0].name, '推荐');
      expect(parsed[0].rawUrl, 'https://a');
      expect(parsed[2].name, '科技');
      expect(parsed[2].rawUrl, 'https://c');

      final empty = RssService.parseSortText(
        '   ',
        sourceUrl: 'https://fallback',
      );
      expect(empty.length, 1);
      expect(empty.first.rawUrl, 'https://fallback');
    });

    test('sortUrls 求值 <js> / @js: 并按内容哈希缓存，removeSortCache 可失效', () async {
      var calls = 0;
      final src = RssSource(
        sourceUrl: 'https://rss.example',
        sourceName: 'r',
        sortUrl: '推荐::<js>A</js>&&最新::<js>B</js>',
      );
      final svc = RssService();
      final r1 = await svc.sortUrls(
        src,
        jsEval: (script) async {
          calls++;
          return 'https://rss.example/$script';
        },
      );
      expect(r1.length, 2);
      expect(r1[0].name, '推荐');
      expect(r1[0].rawUrl, 'https://rss.example/A');
      expect(r1[1].rawUrl, 'https://rss.example/B');
      expect(calls, 2);

      // 第二次命中缓存，求值回调不再触发
      final r2 = await svc.sortUrls(
        src,
        jsEval: (script) async {
          calls++;
          return 'x';
        },
      );
      expect(calls, 2);
      expect(r2.length, 2);

      // 清空缓存后重新求值
      RssService.removeSortCache();
      await svc.sortUrls(src, jsEval: (script) async {
        calls++;
        return 'y';
      });
      expect(calls, 4);

      // 整段 @js: 前缀求值
      final jsSrc = RssSource(
        sourceUrl: 'https://rss.example2',
        sourceName: 'r2',
        sortUrl: '@js:build()',
      );
      final r3 = await svc.sortUrls(
        jsSrc,
        jsEval: (script) async => '甲::https://a&&乙::https://b',
      );
      expect(r3.length, 2);
      expect(r3[0].name, '甲');
    });

    test('JS 求值降级为空时回退到 sourceUrl，缓存键随内容变化', () async {
      final src = RssSource(
        sourceUrl: 'https://rss.example3',
        sourceName: 'r3',
        sortUrl: '@js:whatever',
      );
      final r = await RssService().sortUrls(
        src,
        jsEval: (script) async => '',
      );
      expect(r.length, 1);
      expect(r.first.rawUrl, 'https://rss.example3');

      final k1 = RssService.sortCacheKey('https://a', 'x');
      final k2 = RssService.sortCacheKey('https://a', 'y');
      expect(k1, isNot(k2));
      expect(RssService.sortCacheKey('https://a', 'x'), k1);
    });
  });

  // ==================== Web API 全字段往返 ====================

  group('Web API 字段往返', () {
    test('rssSourceFromWeb / rssSourceToWeb 往返不丢规则字段', () {
      final src = RssSource(
        sourceName: '测试源',
        sourceUrl: 'https://r.example',
        sourceGroup: '新闻',
        sortUrl: '推荐::https://r.example/a',
        ruleArticles: '@css:.list',
        ruleTitle: '@css:.t',
        ruleDescription: '@css:.d',
        ruleContent: '@css:.c',
        startJs: 'window.x=1',
        variable: 'v=2',
        enabled: true,
      );
      final web = rssSourceToWeb(src);
      final restored = rssSourceFromWeb(Map<String, dynamic>.from(web));
      expect(restored.sourceName, '测试源');
      expect(restored.sourceUrl, 'https://r.example');
      expect(restored.sortUrl, '推荐::https://r.example/a');
      expect(restored.ruleArticles, '@css:.list');
      expect(restored.ruleTitle, '@css:.t');
      expect(restored.ruleDescription, '@css:.d');
      expect(restored.ruleContent, '@css:.c');
      expect(restored.startJs, 'window.x=1');
      expect(restored.variable, 'v=2');
    });

    test('bookSourcesToWeb 含 rulePut/ruleGet 且 baseURL 提取去重', () {
      final a = BookSource(
        bookSourceUrl: 'https://b.example/a',
        bookSourceName: 'A',
        rulePut: 'putRule',
        ruleGet: 'getRule',
      );
      final b = BookSource(
        bookSourceUrl: 'https://b.example/b',
        bookSourceName: 'B',
      );
      final list = bookSourcesToWeb([a, b]);
      expect(list.length, 2);
      expect(list[0]['rulePut'], 'putRule');
      expect(list[0]['ruleGet'], 'getRule');
      expect(bookSourceBaseUrls([a, b]), ['https://b.example']);
    });
  });

  // ==================== 订阅对比预览 ====================

  group('订阅对比预览', () {
    test('computeDiff 计算新增 / 变更 / 删除三类', () {
      final diff = RuleSubAutoUpdate.computeDiff(
        type: 0,
        incoming: [
          {'bookSourceUrl': 'https://a', 'bookSourceName': 'A'},
          {'bookSourceUrl': 'https://b', 'bookSourceName': 'B2'},
          {'bookSourceUrl': 'https://c', 'bookSourceName': 'C'},
        ],
        local: [
          {'bookSourceUrl': 'https://a', 'bookSourceName': 'A'},
          {'bookSourceUrl': 'https://b', 'bookSourceName': 'B'},
          {'bookSourceUrl': 'https://d', 'bookSourceName': 'D'},
        ],
      );
      expect(diff.addedCount, 1);
      expect(diff.changedCount, 1);
      expect(diff.deletedCount, 1);
      expect(diff.added, ['https://c']);
      expect(diff.changed, ['https://b']);
      expect(diff.deleted, ['https://d']);
      expect(diff.total, 3);
    });

    test('previewImport 用注入的本地快照生成预览摘要', () async {
      final preview = await RuleSubAutoUpdate.previewImport(
        0,
        '[{"bookSourceUrl":"https://x","bookSourceName":"X"}]',
        localOverride: [
          {'bookSourceUrl': 'https://y', 'bookSourceName': 'Y'},
        ],
      );
      expect(preview.diff.addedCount, 1);
      expect(preview.diff.deletedCount, 1);
      expect(preview.summary, '新增 1 · 变更 0 · 删除 1');
      expect(preview.incoming.length, 1);
      expect(preview.local.length, 1);
    });

    test('silentUpdate 与冲突保留本地修改开关可持久化', () async {
      expect(await RuleSubAutoUpdate.isSilentUpdate(), isFalse);
      await RuleSubAutoUpdate.setSilentUpdate(true);
      expect(await RuleSubAutoUpdate.isSilentUpdate(), isTrue);
      expect(await RuleSubAutoUpdate.keepLocalOnConflict(), isTrue);
      await RuleSubAutoUpdate.setKeepLocalOnConflict(false);
      expect(await RuleSubAutoUpdate.keepLocalOnConflict(), isFalse);
    });
  });
}
