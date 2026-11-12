import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/help/source/replace_rule_service.dart';

void main() {
  group('替换规则模型 ReplaceRule.kt', () {
    test('fromMap 兼容上游字段别名且不丢 group/excludeScope/timeout', () {
      final r = ReplaceRule.fromMap({
        'name': '去广告',
        'group': '净化',
        'pattern': '广告',
        'replacement': '',
        'scope': '我的书源',
        'scopeTitle': true,
        'scopeContent': false,
        'excludeScope': '排除源',
        'isEnabled': false,
        'isRegex': false,
        'timeoutMillisecond': 1500,
        'sortOrder': 7,
      });
      expect(r.replaceSummary, '去广告');
      expect(r.group, '净化');
      expect(r.replaceRule, '广告');
      expect(r.scope, '我的书源');
      expect(r.excludeScope, '排除源');
      expect(r.isTitle, isTrue);
      expect(r.isContent, isFalse);
      expect(r.enable, isFalse);
      expect(r.isRegex, isFalse);
      expect(r.timeoutMillisecond, 1500);
      expect(r.order, 7);
    });

    test('toMap 持久化新字段，toLegadoJson 输出上游字段名', () {
      final r = ReplaceRule(
        replaceSummary: '规则',
        replaceRule: 'abc',
        replacement: 'x',
        group: '分组A',
        excludeScope: '源B',
        timeoutMillisecond: 800,
        order: 3,
      );
      expect(r.toMap()['group_name'], '分组A');
      expect(r.toMap()['excludeScope'], '源B');
      expect(r.toMap()['timeoutMillisecond'], 800);
      final j = r.toLegadoJson();
      expect(j['name'], '规则');
      expect(j['group'], '分组A');
      expect(j['pattern'], 'abc');
      expect(j['excludeScope'], '源B');
      expect(j['timeoutMillisecond'], 800);
      expect(j['order'], 3);
      // 上游字段再导入回来应等价
      final back = ReplaceRule.fromMap(Map<String, dynamic>.from(j));
      expect(back.group, '分组A');
      expect(back.excludeScope, '源B');
      expect(back.timeoutMillisecond, 800);
      expect(back.order, 3);
    });

    test('isValid 与上游一致：空/非法正则/尾部竖线无效', () {
      expect(ReplaceRule(replaceSummary: '', replaceRule: '', replacement: '').isValid(), isFalse);
      expect(ReplaceRule(replaceSummary: '', replaceRule: '(', replacement: '').isValid(), isFalse);
      expect(ReplaceRule(replaceSummary: '', replaceRule: 'abc|', replacement: '').isValid(), isFalse);
      expect(ReplaceRule(replaceSummary: '', replaceRule: r'abc\|', replacement: '').isValid(), isTrue);
      // 非正则不编译正则，括号是合法字面量
      expect(ReplaceRule(replaceSummary: '', replaceRule: '(', replacement: '', isRegex: false).isValid(), isTrue);
    });

    test('validTimeoutMillisecond <=0 回退 3000；displayNameWithGroup 带分组', () {
      final r = ReplaceRule(replaceSummary: 'A', replaceRule: 'x', replacement: '', timeoutMillisecond: 0, group: 'G');
      expect(r.validTimeoutMillisecond, 3000);
      expect(r.displayNameWithGroup, 'A (G)');
      final r2 = ReplaceRule(replaceSummary: 'B', replaceRule: 'x', replacement: '');
      expect(r2.displayNameWithGroup, 'B');
      expect(r2.validTimeoutMillisecond, 3000);
    });
  });

  group('替换执行细节', () {
    final svc = ReplaceRuleService();

    test('非正则必须按字面量替换（此前被误当 RegExp）', () {
      final r = ReplaceRule(replaceSummary: '', replaceRule: '.', replacement: '-', isRegex: false);
      expect(svc.applyRules('a.b.c', [r]), 'a-b-c');
      final rr = ReplaceRule(replaceSummary: '', replaceRule: r'\.', replacement: '-');
      expect(svc.applyRules('a.b.c', [rr]), 'a-b-c');
    });

    test('scope 语义：规则 scope 含书名/源名才生效，all 与空表示全部', () {
      final r = ReplaceRule(replaceSummary: '', replaceRule: 'x', replacement: 'y', scope: '我的书源,另一个源');
      expect(svc.applyRules('x', [r], scope: '我的书源', name: '某书'), 'y');
      expect(svc.applyRules('x', [r], scope: '不相关源', name: '别的书'), 'x');
      final all = ReplaceRule(replaceSummary: '', replaceRule: 'x', replacement: 'y', scope: 'all');
      expect(svc.applyRules('x', [all], scope: '任意'), 'y');
      final none = ReplaceRule(replaceSummary: '', replaceRule: 'x', replacement: 'y');
      expect(svc.applyRules('x', [none]), 'y');
    });

    test('excludeScope 命中书名或书源时排除该规则', () {
      final r = ReplaceRule(replaceSummary: '', replaceRule: 'x', replacement: 'y', excludeScope: '某书');
      expect(svc.applyRules('x', [r], scope: '我的书源', name: '某书'), 'x');
      expect(svc.applyRules('x', [r], scope: '我的书源', name: '别的书'), 'y');
    });

    test('isTitle / isContent 分通道生效', () {
      final titleOnly = ReplaceRule(replaceSummary: '', replaceRule: 'x', replacement: 'y', isTitle: true, isContent: false);
      expect(svc.applyRules('x', [titleOnly], isTitle: true), 'y');
      expect(svc.applyRules('x', [titleOnly]), 'x');
      final contentOnly = ReplaceRule(replaceSummary: '', replaceRule: 'x', replacement: 'y');
      expect(svc.applyRules('x', [contentOnly]), 'y');
      expect(svc.applyRules('x', [contentOnly], isTitle: true), 'x');
    });

    test('按 order(sortOrder) 升序应用；禁用与无效规则跳过', () {
      final r1 = ReplaceRule(replaceSummary: '', replaceRule: 'B', replacement: 'C', order: 2);
      final r2 = ReplaceRule(replaceSummary: '', replaceRule: 'A', replacement: 'B', order: 1);
      expect(svc.applyRules('A', [r1, r2]), 'C');
      final off = ReplaceRule(replaceSummary: '', replaceRule: 'A', replacement: 'Z', enable: false);
      expect(svc.applyRules('A', [off]), 'A');
      final bad = ReplaceRule(replaceSummary: '', replaceRule: 'A|', replacement: 'Z');
      expect(svc.applyRules('A', [bad]), 'A');
    });

    test('fromJson / toJson 跨端往返不丢字段', () {
      final json = ReplaceRuleService.toJson([
        ReplaceRule(replaceSummary: 'n', replaceRule: 'p', replacement: 'r', group: 'g', excludeScope: 'e', timeoutMillisecond: 900),
      ]);
      expect(json.single['group'], 'g');
      expect(json.single['excludeScope'], 'e');
      expect(json.single['timeoutMillisecond'], 900);
      final back = ReplaceRuleService.fromJson(json);
      expect(back.single.group, 'g');
      expect(back.single.excludeScope, 'e');
      expect(back.single.timeoutMillisecond, 900);
    });

    test('testRule 拒绝无效规则；testRuleWithTimeout 在超时内完成', () async {
      final bad = ReplaceRule(replaceSummary: '', replaceRule: 'abc|', replacement: 'z');
      expect(svc.testRule('abc', bad), contains('规则无效'));
      final ok = ReplaceRule(replaceSummary: '', replaceRule: 'a', replacement: 'X');
      expect(svc.testRule('abc', ok), 'Xbc');
      expect(await svc.testRuleWithTimeout('abc', ok), 'Xbc');
    });
  });
}
