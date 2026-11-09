import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';

/// 对照上游 AnalyzeRule 的内联规则语义链：
/// splitPutRule（@put JSON）、replaceRegex（## / ###）、
/// 捕获组 $N、`{{}}` 插值、`<js>` 与结尾 @js:。
void main() {
  RulePipeline pipeline() => RulePipeline();

  group('@put 变量：标准 JSON 与宽松格式（splitPutRule）', () {
    test('标准 JSON @put:{"k":"v"} 解析为正确键值', () {
      final p = pipeline();
      final entries = p.parsePutEntries('"uid":"42","token":"abc"');
      expect(entries.map((e) => e.key), ['uid', 'token']);
      expect(entries.map((e) => e.value), ['42', 'abc']);
    });

    test('JSON 值中的 : 与 , 不被误切分', () {
      final p = pipeline();
      final entries = p.parsePutEntries('"url":"http://a.com/x,y","k":"v:2"');
      expect(entries.length, 2);
      expect(entries[0].value, 'http://a.com/x,y');
      expect(entries[1].value, 'v:2');
    });

    test('宽松 key:rule 格式仍可用（GSON 非标准回退）', () {
      final p = pipeline();
      final entries = p.parsePutEntries('uid:42,token:abc');
      expect(entries.map((e) => e.key), ['uid', 'token']);
      expect(entries.map((e) => e.value), ['42', 'abc']);
    });

    test('含 <js>/@get 的复杂 put 值回退宽松格式，不误判 JSON', () {
      final p = pipeline();
      final entries = p.parsePutEntries('key:<js>"abc"</js>,other:xx');
      expect(entries.length, 2);
      expect(entries[0].key, 'key');
      expect(entries[0].value, '<js>"abc"</js>');
    });

    test('@put + @get 端到端：变量写入并读出', () {
      final p = pipeline();
      const rule = '@put:{"token":"abc123"}&&@get:{token}';
      expect(p.extractStringFromRaw('<html></html>', rule), 'abc123');
    });

    test('@put 宽松格式 + @get 端到端', () {
      final p = pipeline();
      const rule = '@put:{token:hello}&&@get:{token}';
      expect(p.extractStringFromRaw('<html></html>', rule), 'hello');
    });
  });

  group('## 后处理：replace / remove / match / replaceFirst', () {
    test('##regex##replacement 全局替换', () {
      final p = pipeline();
      final ops = p.parseFieldParts('class.a##foo##bar').ops;
      expect(p.applyFieldOps('foo and foo', ops), 'bar and bar');
    });

    test('单独 ##regex 为删除', () {
      final p = pipeline();
      final ops = p.parseFieldParts('class.a##\\s+').ops;
      expect(p.applyFieldOps('a b  c', ops), 'abc');
    });

    test('###regex 只取首个匹配（2 段形式，项目既有语义）', () {
      final p = pipeline();
      final ops = p.parseFieldParts('class.a###\\d+').ops;
      expect(ops.single.kind, 'match');
      expect(p.applyFieldOps('第1章 第2章', ops), '1');
    });

    test('##match##replace### 4 段为 replaceFirst（上游 replaceFirst=true）', () {
      final p = pipeline();
      final ops = p.parseFieldParts('class.a##foo##bar###').ops;
      expect(ops.single.kind, 'replaceFirst');
      expect(ops.single.pattern, 'foo');
      expect(ops.single.replacement, 'bar');
    });

    test('replaceFirst 只处理第一个匹配，结果为其替换文本', () {
      final p = pipeline();
      final ops = p.parseFieldParts('class.x##第(\\d+)章##Chapter \$1###').ops;
      expect(p.applyFieldOps('第1章 正文 第2章', ops), 'Chapter 1');
    });

    test('replaceFirst 无匹配返回空串', () {
      final p = pipeline();
      final ops = p.parseFieldParts('class.x##ZZZ##YY###').ops;
      expect(p.applyFieldOps('abc', ops), '');
    });

    test('修复：4 段 ### 不再产生空正则 match 清空结果', () {
      final p = pipeline();
      final ops = p.parseFieldParts('class.a##foo##bar###').ops;
      // 旧实现会是 [replace, match("")]，把值清空
      expect(ops.length, 1);
      expect(ops.any((o) => o.kind == 'match' && o.pattern.isEmpty), isFalse);
    });

    test('捕获组 \$1 在全局替换中展开', () {
      final p = pipeline();
      final ops = p.parseFieldParts('class.x##(\\d+)##[\$1]').ops;
      expect(p.applyFieldOps('a1 b2', ops), 'a[1] b[2]');
    });
  });

  group('JS 与模板插值', () {
    test('整段 <js> 交给 JS 求值', () {
      final p = pipeline();
      expect(p.extractStringFromRaw('Hello', '<js>"X" + result.length</js>'),
          isNotEmpty);
    });

    test('结尾 @js: 清洗', () {
      final p = pipeline();
      final parts = p.parseFieldParts('class.a@js:result + "!"');
      expect(parts.tailJs, isNotNull);
    });

    test('{{}} 插值标记', () {
      final p = pipeline();
      final parts = p.parseFieldParts('前缀{{result}}后缀');
      expect(parts.hasInterpolation, isTrue);
    });

    test('模式前缀判定：@css / // / \$. / : 正则', () {
      final p = pipeline();
      expect(p.modeOf('@css:.a@text'), RuleMode.css);
      expect(p.modeOf('//div/a'), RuleMode.xpath);
      expect(p.modeOf('\$.data[*]'), RuleMode.json);
      expect(p.modeOf('@js:result'), RuleMode.js);
    });
  });

  group('组合连接符', () {
    test('|| 取第一个非空', () {
      final p = pipeline();
      const html = '<div class="a">A</div>';
      expect(p.extractStringFromRaw(html, 'class.b@text||class.a@text'), 'A');
    });

    test('&& 合并', () {
      final p = pipeline();
      const html = '<div class="a">A</div><div class="b">B</div>';
      final out = p.extractStringFromRaw(html, 'class.a@text&&class.b@text');
      expect(out, isNotNull);
      expect(out!.contains('A'), isTrue);
      expect(out.contains('B'), isTrue);
    });
  });
}
