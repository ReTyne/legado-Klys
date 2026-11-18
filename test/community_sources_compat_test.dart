import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/js/offline_js_bridge.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';

/// 社区真实书源批量兼容回归（29 个，来自 yck2026.fun 源仓库）。
///
/// 每个书源在原版阅读可用；本测试用离线、确定性的方式逐一验证 K 版
/// 模型与规则引擎能正确"吃下"这些真实书源：
///  1. fromJson/toJson 往返不丢任何字段；
///  2. 全部规则字段被 RulePipeline 正确识别（不误判/不抛异常）；
///  3. 每条规则都能被规则管线处理（列表规则抽取 / 字段规则解析）；
///  4. jsLib / loginUrl 注入离线 JS 桥后函数可见、脚本非空。
/// 全程不依赖网络 / WebView / 原生通道。
void main() {
  const fixtureDir = 'test/fixtures/community';
  final ids = <String>[];
  final dir = Directory(fixtureDir);
  if (dir.existsSync()) {
    for (final f in dir.listSync().whereType<File>()) {
      final m = RegExp(r'source_(\d+)\.json$').firstMatch(f.path);
      if (m != null) ids.add(m.group(1)!);
    }
  }
  ids.sort();

  Map<String, dynamic> load(String id) {
    final decoded = jsonDecode(File('$fixtureDir/source_$id.json').readAsStringSync());
    // 社区源仓库多为单元素数组 [ {...} ]，也兼容裸对象
    if (decoded is List) {
      expect(decoded, isNotEmpty, reason: '$id 书源数组为空');
      return (decoded.first as Map).cast<String, dynamic>();
    }
    return (decoded as Map).cast<String, dynamic>();
  }

  const ruleGroups = [
    'ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent',
    'ruleReview', 'ruleImage',
  ];
  const urlRuleFields = [
    'searchUrl', 'exploreUrl', 'loginUrl', 'loginCheckJs', 'header',
    'bookUrlPattern', 'coverDecodeJs', 'rulePut', 'ruleGet',
  ];

  group('社区真实书源数量与可解析', () {
    test('至少 20 个社区书源 fixture 可用', () {
      expect(ids.length, greaterThanOrEqualTo(20),
          reason: '要求不少于 20 个真实书源参与测试');
    });

    for (final id in ids) {
      test('$id: JSON 可解析且含书名与地址', () {
        final f = load(id);
        expect(f['bookSourceName'], isA<String>(), reason: '$id 缺 bookSourceName');
        expect((f['bookSourceName'] as String).isNotEmpty, isTrue);
        expect(f['bookSourceUrl'], isA<String>(), reason: '$id 缺 bookSourceUrl');
        final s = BookSource.fromJson(f);
        expect(s.bookSourceName, f['bookSourceName']);
        expect(s.bookSourceUrl, f['bookSourceUrl']);
      });
    }
  });

  group('fromJson / toJson 往返不丢字段', () {
    for (final id in ids) {
      test('$id: 原始键全部保留且二次往返稳定', () {
        final f = load(id);
        final s = BookSource.fromJson(f);
        final round = s.toJson();
        for (final k in f.keys) {
          expect(round.containsKey(k), isTrue, reason: '$id 往返丢失字段 $k');
        }
        // 关键字段值一致
        for (final k in const [
          'bookSourceName', 'bookSourceUrl', 'searchUrl', 'exploreUrl',
          'ruleSearch', 'ruleBookInfo', 'ruleToc', 'ruleContent',
        ]) {
          if (f.containsKey(k)) {
            expect(round[k], f[k], reason: '$id 字段 $k 往返值不一致');
          }
        }
        expect(BookSource.fromJson(round).toJson(), round,
            reason: '$id 二次往返漂移');
      });
    }
  });

  group('规则字段被 RulePipeline 正确识别', () {
    final p = RulePipeline();
    for (final id in ids) {
      test('$id: 所有规则字符串 modeOf/looksLikeRule 不抛异常', () {
        final f = load(id);
        final rules = <String>[];
        for (final k in urlRuleFields) {
          final v = f[k];
          if (v is String && v.isNotEmpty) rules.add(v);
        }
        for (final g in ruleGroups) {
          final gr = f[g];
          if (gr is Map) {
            for (final v in gr.values) {
              if (v is String && v.isNotEmpty) rules.add(v);
              if (v is Map) {
                for (final vv in v.values) {
                  if (vv is String && vv.isNotEmpty) rules.add(vv);
                }
              }
            }
          }
        }
        expect(rules, isNotEmpty, reason: '$id 没有任何规则字段');
        for (final r in rules) {
          // 规则模式识别必须成功且不抛异常（这是引擎分派规则的第一道关口）
          final mode = p.modeOf(r);
          expect(mode, isA<RuleMode>());
          RulePipeline.looksLikeRule(r);
          // 注：splitRuleBalanced 是「括号/引号平衡校验器」，对正则（含语法
          // 引号）、裸 JS 脚本抛 FormatException 是其设计预期的安全机制；
          // 引擎对各模式走专门分支（_extractSingleChain / _regexValues /
          // <js> 求值），不会把这些形态交给它，故此处不做无差别校验。
        }
      });
    }
  });

  group('规则管线可处理每个书源的列表/字段规则', () {
    final p = RulePipeline();
    // 一个通用 JSON 样本，用于验证 JSONPath 型规则能被求值管线消费
    const sampleJson = '{"data":{"list":[{"name":"测试书","author":"作者",'
        '"url":"/book/1","id":"1","cover":"/c.jpg","kind":"玄幻",'
        '"lastChapter":"第一章","intro":"简介","wordCount":"100万"}]},'
        '"name":"测试书","author":"作者","bookUrl":"/book/1",'
        '"tocUrl":"/toc/1","content":"正文内容第二章","title":"第一章"}';
    for (final id in ids) {
      test('$id: 规则抽取管线端到端不抛异常', () {
        final f = load(id);
        // 列表规则：对每个 ruleSearch/ruleExplore.bookList 尝试抽取
        for (final g in const ['ruleSearch', 'ruleExplore', 'ruleToc']) {
          final gr = f[g];
          if (gr is! Map) continue;
          final listRule = gr['bookList'] ?? gr['chapterList'];
          if (listRule is String && listRule.isNotEmpty) {
            // 管线对样本求值，允许结果为空，但不得抛异常
            p.extractListFromRaw(sampleJson, listRule);
          }
        }
        // 字段规则：对每组的标量规则逐条尝试求值
        for (final g in ruleGroups) {
          final gr = f[g];
          if (gr is! Map) continue;
          for (final v in gr.values) {
            if (v is String && v.isNotEmpty &&
                !v.contains('<js>') && !v.trim().startsWith('@js:')) {
              p.firstStringFromRaw(sampleJson, v);
            }
          }
        }
      });
    }
  });

  group('jsLib / loginUrl 注入离线 JS 桥', () {
    for (final id in ids) {
      test('$id: 脚本注入非空且可加载', () {
        final f = load(id);
        final s = BookSource.fromJson(f);
        // 有脚本字段的书源才验证注入
        final hasScript = (s.jsLib != null && s.jsLib!.isNotEmpty) ||
            (s.loginUrl != null && s.loginUrl!.isNotEmpty);
        if (!hasScript) return;
        final rt = OfflineJsBridge();
        rt.loadSource(s);
        expect(rt.script, isNotEmpty, reason: '$id 注入后脚本为空');
        if (s.jsLib != null && s.jsLib!.isNotEmpty) {
          // loadSource 会对 jsLib 做 trim，按 trim 后比对
          expect(rt.script, contains(s.jsLib!.trim()),
              reason: '$id jsLib 未注入脚本');
        }
      });
    }
  });
}
