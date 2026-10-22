import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/url_option.dart';

void main() {
  group('UrlOptions - 裸 URL', () {
    test('普通 URL 不带选项', () {
      final u = UrlOptions.parse('https://a.com/x?y=1');
      expect(u.url, 'https://a.com/x?y=1');
      expect(u.options, isEmpty);
      expect(u.method, 'GET');
    });

    test('# 注释被剥除', () {
      final u = UrlOptions.parse('https://a.com/x#这是注释');
      expect(u.url, 'https://a.com/x');
      expect(u.options, isEmpty);
    });

    test('data: URI 里的 # 不剥', () {
      final u = UrlOptions.parse('data:;base64,5L2g5aW9#frag');
      expect(u.url, 'data:;base64,5L2g5aW9#frag');
    });
  });

  group('UrlOptions - url,{json}', () {
    test('解析 method/body/charset/headers', () {
      final u = UrlOptions.parse('https://a.com/s,{"method":"POST","body":"k=v","charset":"gbk","headers":{"X-T":"1"}}');
      expect(u.url, 'https://a.com/s');
      expect(u.method, 'POST');
      expect(u.str('body'), 'k=v');
      expect(u.str('charset'), 'gbk');
      expect((u.options['headers'] as Map)['X-T'], '1');
    });

    test('body 里含逗号时括号配平', () {
      final u = UrlOptions.parse('https://a.com/s,{"method":"POST","body":"a=1,b=2,c=3"}');
      expect(u.url, 'https://a.com/s');
      expect(u.str('body'), 'a=1,b=2,c=3');
    });

    test('非法 json 时忽略选项但保留 URL', () {
      final u = UrlOptions.parse('https://a.com/s,{不是json}');
      expect(u.url, 'https://a.com/s');
      expect(u.options, isEmpty);
    });
  });

  group('UrlOptions - url,POST:body', () {
    test('解析方法与请求体', () {
      final u = UrlOptions.parse('https://a.com/s,POST:name=test');
      expect(u.url, 'https://a.com/s');
      expect(u.method, 'POST');
      expect(u.str('body'), 'name=test');
    });

    test('小写方法也识别', () {
      final u = UrlOptions.parse('https://a.com/s,post:a=1');
      expect(u.method, 'POST');
      expect(u.str('body'), 'a=1');
    });

    test('无 body 的 POST', () {
      final u = UrlOptions.parse('https://a.com/s,POST');
      expect(u.method, 'POST');
      expect(u.str('body'), isNull);
    });
  });

  group('UrlOptions - {{key=value}}', () {
    test('单个选项', () {
      final u = UrlOptions.parse('https://a.com/s?q=1,{{charset=gbk}}');
      expect(u.url, 'https://a.com/s?q=1');
      expect(u.str('charset'), 'gbk');
    });

    test('多个选项可任意顺序', () {
      final u = UrlOptions.parse('https://a.com/s?q=1,{{method=POST}},{{charset=gbk}},{{retry=3}}');
      expect(u.url, 'https://a.com/s?q=1');
      expect(u.method, 'POST');
      expect(u.str('charset'), 'gbk');
      expect(u.str('retry'), '3');
    });

    test('选项可插在 URL 中间', () {
      final u = UrlOptions.parse('https://a.com/{{host=backup.b.com}}/s?q=1');
      expect(u.url, 'https://a.com//s?q=1');
      expect(u.str('host'), 'backup.b.com');
    });

    test('header.X=Y 归入 headers', () {
      final u = UrlOptions.parse('https://a.com/s,{{header.X-Token=abc}},{{header.Accept=json}}');
      final h = u.options['headers'] as Map;
      expect(h['X-Token'], 'abc');
      expect(h['Accept'], 'json');
      expect(u.url, 'https://a.com/s');
    });

    test('true/false 归一为布尔', () {
      final u = UrlOptions.parse('https://a.com/s,{{webView=true}},{{strict=false}}');
      expect(u.options['webview'], true);
      expect(u.options['strict'], false);
    });

    test('引号包裹的值会去掉引号', () {
      final u = UrlOptions.parse('https://a.com/s,{{ua="Mozilla/5.0 Custom"}}');
      expect(u.str('ua'), 'Mozilla/5.0 Custom');
    });

    test('无值选项 {{webView}} 视为 true', () {
      final u = UrlOptions.parse('https://a.com/s,{{webView}}');
      expect(u.options['webview'], true);
    });

    test('未知名 {{...}} 保留在 URL 里（防止误删未替换模板）', () {
      final u = UrlOptions.parse('https://a.com/s?q={{key}}&p={{page}}');
      expect(u.url, 'https://a.com/s?q={{key}}&p={{page}}');
      expect(u.options, isEmpty);
    });

    test('json 与 {{}} 组合', () {
      final u = UrlOptions.parse('https://a.com/s,{"method":"POST"},{{charset=gbk}}');
      expect(u.url, 'https://a.com/s');
      expect(u.method, 'POST');
      expect(u.str('charset'), 'gbk');
    });

    test('选项名大小写不敏感', () {
      final u = UrlOptions.parse('https://a.com/s,{{Charset=gbk}},{{Method=post}}');
      expect(u.str('charset'), 'gbk');
      expect(u.method, 'POST');
    });
  });

  group('UrlOptions - 边界', () {
    test('尾随逗号清理', () {
      final u = UrlOptions.parse('https://a.com/s,');
      expect(u.url, 'https://a.com/s');
    });

    test('空字符串不崩', () {
      final u = UrlOptions.parse('');
      expect(u.url, '');
    });

    test('仅有空白的 URL', () {
      final u = UrlOptions.parse('   ');
      expect(u.url, '');
    });

    test('恶意大量 {{}} 不会死循环', () {
      final u = UrlOptions.parse('https://a.com/{{a}}{{b}}{{c}}');
      expect(u.url, 'https://a.com/{{a}}{{b}}{{c}}');
    });
  });
}
