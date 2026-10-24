import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/storage/import_old_data.dart';

/// C1 旧版数据迁移：规则语法转换（对齐 E ImportOldData.toNewRule/toNewUrl）。
void main() {
  group('toNewRule（# → ##、| → ||、& → &&）', () {
    test('#正则#替换 → ##正则##替换', () {
      expect(ImportOldData.toNewRule('tag.a@text#\\s#'), r'tag.a@text##\s##');
    });

    test('| → ||', () {
      expect(ImportOldData.toNewRule('tag.a|tag.b'), 'tag.a||tag.b');
    });

    test('& → &&（http 与 / 开头除外）', () {
      expect(ImportOldData.toNewRule('a&b'), 'a&&b');
      expect(ImportOldData.toNewRule('http://a.com?x=1&y=2'), 'http://a.com?x=1&y=2');
      expect(ImportOldData.toNewRule('/html&body'), '/html&body');
    });

    test('## 与 || 已存在时保持', () {
      expect(ImportOldData.toNewRule('a##b##c'), 'a##b##c');
      expect(ImportOldData.toNewRule('a||b'), 'a||b');
    });

    test('特殊前缀跳过转换', () {
      expect(ImportOldData.toNewRule('@css:a#b'), '@css:a#b');
      expect(ImportOldData.toNewRule('//div[@class="a"]'), '//div[@class="a"]');
      expect(ImportOldData.toNewRule('@js:result'), '@js:result');
      expect(ImportOldData.toNewRule(':a|b'), ':a|b');
    });

    test('- 反选与 + 合并前缀保留', () {
      expect(ImportOldData.toNewRule('-tag.a'), '-tag.a');
      expect(ImportOldData.toNewRule('+tag.a'), '+tag.a');
    });

    test('null/空 返回 null', () {
      expect(ImportOldData.toNewRule(null), null);
      expect(ImportOldData.toNewRule(''), null);
      expect(ImportOldData.toNewRule('  '), null);
    });

    test('## 段落内 | 只替换选择器部分', () {
      expect(ImportOldData.toNewRule('tag.a|tag.b##x##y'), 'tag.a||tag.b##x##y');
    });
  });

  group('toNewUrl（searchKey/searchPage → {{}}、Header/方法选项）', () {
    test('searchKey → {{key}}、searchPage → {{page}}', () {
      expect(
        ImportOldData.toNewUrl('https://s.com/search?q=searchKey&p=searchPage'),
        'https://s.com/search?q={{key}}&p={{page}}',
      );
    });

    test('searchPage±1 → {{page±1}}', () {
      expect(
        ImportOldData.toNewUrl('https://s.com/p<searchPage-1>'),
        r'https://s.com/p{{page-1}}',
      );
      expect(
        ImportOldData.toNewUrl('https://s.com/psearchPage+1'),
        r'https://s.com/p{{page+1}}',
      );
    });

    test('@Header:{...} → ,{"headers":...}', () {
      expect(
        ImportOldData.toNewUrl('https://s.com,@Header:{"User-Agent":"UA"}'),
        'https://s.com,{"headers":{"User-Agent":"UA"}}',
      );
    });

    test('|charset=utf-8 → ,{"charset":"utf-8"}', () {
      expect(
        ImportOldData.toNewUrl('https://s.com|charset=utf-8'),
        'https://s.com,{"charset":"utf-8"}',
      );
    });

    test('url@body → ,{"method":"POST","body":body}', () {
      expect(
        ImportOldData.toNewUrl('https://s.com@{"key":"{{key}}"}'),
        'https://s.com,{"method":"POST","body":"{\\"key\\":\\"{{key}}\\"}"}',
      );
    });

    test('{{...}} JS 块内 searchKey/searchPage 还原', () {
      expect(
        ImportOldData.toNewUrl('https://s.com,{{java.ajax(searchKey+searchPage)}}'),
        'https://s.com,{{java.ajax(key+page)}}',
      );
    });

    test('<js> 开头原样返回', () {
      expect(ImportOldData.toNewUrl('<js>result</js>'), '<js>result</js>');
    });
  });

  group('toNewUrls', () {
    test('单条直接转', () {
      expect(ImportOldData.toNewUrls('https://s.com?k=searchKey'), 'https://s.com?k={{key}}');
    });

    test('&& / 换行分隔逐条转换', () {
      expect(
        ImportOldData.toNewUrls('https://a.com?k=searchKey&&https://b.com?p=searchPage'),
        'https://a.com?k={{key}}\nhttps://b.com?p={{page}}',
      );
    });

    test('@js:/<js> 开头原样返回', () {
      expect(ImportOldData.toNewUrls('@js:java.ajax("x")'), '@js:java.ajax("x")');
    });
  });

  group('fromOldBookSource', () {
    test('旧书源字段映射为新模型', () {
      final source = ImportOldData.fromOldBookSource({
        'bookSourceUrl': 'https://source.com',
        'bookSourceName': '测试源',
        'bookSourceGroup': '分组',
        'httpUserAgent': 'Mozilla/5.0',
        'ruleSearchUrl': 'https://source.com/search?q=searchKey',
        'ruleSearchList': 'tag.div',
        'ruleSearchName': 'tag.a@text',
        'ruleFindUrl': 'https://source.com/find',
        'ruleBookContent': r'$.content',
        'enable': true,
        'serialNumber': 5,
      })!;
      expect(source.bookSourceUrl, 'https://source.com');
      expect(source.bookSourceName, '测试源');
      expect(source.bookSourceGroup, '分组');
      expect(source.header, '{"User-Agent":"Mozilla/5.0"}');
      expect(source.searchUrl, 'https://source.com/search?q={{key}}');
      expect(source.customOrder, 5);
      expect(source.enabled, true);
      expect(source.enabledExplore, true);
      expect(source.ruleSearch!['bookList'], 'tag.div');
      expect(source.ruleSearch!['name'], 'tag.a@text');
      expect(source.ruleContent!['content'], r'$.content'); // $. 开头不剥离（E 同）
      expect(source.ruleBookInfo!['tocUrl'], null);
    });

    test('AUDIO 类型映射为 1', () {
      final source = ImportOldData.fromOldBookSource({
        'bookSourceUrl': 'https://a.com',
        'bookSourceType': 'AUDIO',
      })!;
      expect(source.bookSourceType, 1);
    });

    test('缺 bookSourceUrl 返回 null', () {
      expect(ImportOldData.fromOldBookSource({'bookSourceName': 'x'}), null);
    });

    test('isOldSourceMap 识别', () {
      expect(ImportOldData.isOldSourceMap({'ruleSearchUrl': 'x'}), true);
      expect(ImportOldData.isOldSourceMap({'searchUrl': 'x'}), false);
      expect(
          ImportOldData.isOldSourceMap({'ruleSearchUrl': 'x', 'searchUrl': 'y'}), false);
    });
  });

  group('uaToHeader', () {
    test('UA 转 header JSON', () {
      expect(ImportOldData.uaToHeader('Mozilla/5.0'), '{"User-Agent":"Mozilla/5.0"}');
    });

    test('null/空 返回 null', () {
      expect(ImportOldData.uaToHeader(null), null);
      expect(ImportOldData.uaToHeader(''), null);
    });
  });

  group('bookFromOldMap', () {
    test('旧书架字段映射', () {
      final book = ImportOldData.bookFromOldMap({
        'noteUrl': 'http://book.com/1',
        'tag': 'loc_book',
        'bookInfoBean': {
          'name': '测试书籍',
          'author': '作者',
          'origin': '本地',
          'coverUrl': 'http://cover',
          'introduce': '简介',
        },
        'lastChapterName': '第十章',
        'durChapter': 9,
        'durChapterPage': 2,
        'finalDate': 1234567890,
        'allowUpdate': true,
        'serialNumber': 3,
      })!;
      expect(book.bookUrl, 'http://book.com/1');
      expect(book.name, '测试书籍');
      expect(book.author, '作者');
      expect(book.origin, 'loc_book');
      expect(book.originName, '本地');
      expect(book.local, true);
      expect(book.coverUrl, 'http://cover');
      expect(book.intro, '简介');
      expect(book.lastChapter, '第十章');
      expect(book.durChapterIndex, 9);
      expect(book.durChapterPos, 2);
      expect(book.durChapterTime, 1234567890);
      expect(book.canUpdate, true);
      expect(book.order, 3);
    });

    test('AUDIO 类型', () {
      final book = ImportOldData.bookFromOldMap({
        'noteUrl': 'http://book.com/2',
        'bookInfoBean': {'name': '有声书', 'bookSourceType': 'AUDIO'},
      })!;
      expect(book.type, 1);
    });

    test('缺 noteUrl 返回 null', () {
      expect(ImportOldData.bookFromOldMap({'bookInfoBean': {'name': 'x'}}), null);
    });
  });
}
