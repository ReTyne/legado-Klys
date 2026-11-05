import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/opds_engine.dart';
import 'package:legado_md3/ui/main/discover/opds_catalog_screen.dart';

/// 回归：OpdsEngine 此前全库无调用方（孤儿实现），且 search() 只遍历 entry.links，
/// 找不到标准 OPDS 放在 feed 级的 <link rel="search">。本轮接入发现页并修复搜索。
const String _feed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>示例 OPDS</title>
  <link rel="search" href="/opds/search?q={searchTerms}" type="application/atom+xml"/>
  <entry>
    <title>科幻分类</title>
    <id>urn:cat:scifi</id>
    <link rel="subsection" href="/opds/scifi" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  </entry>
  <entry>
    <title>三体</title>
    <id>urn:book:1</id>
    <author><name>刘慈欣</name></author>
    <summary>地球往事三部曲</summary>
    <link rel="http://opds-spec.org/image" href="/covers/1.jpg" type="image/jpeg"/>
    <link rel="http://opds-spec.org/acquisition" href="/books/1.epub" type="application/epub+zip"/>
    <category label="科幻" term="scifi"/>
  </entry>
</feed>''';

void main() {
  OpdsEngine engine() => OpdsEngine(baseUrl: 'https://example.com/opds');

  test('parseAtom 解析导航型与书籍型条目（离线，无需网络）', () {
    final list = engine().parseAtom(_feed);
    expect(list, hasLength(2));

    final nav = list[0];
    expect(nav.title, '科幻分类');
    expect(nav.navigationUrl, 'https://example.com/opds/scifi');
    expect(nav.downloadUrl, isNull);

    final book = list[1];
    expect(book.title, '三体');
    expect(book.author, '刘慈欣');
    expect(book.summary, '地球往事三部曲');
    expect(book.cover, 'https://example.com/covers/1.jpg');
    expect(book.downloadUrl, 'https://example.com/books/1.epub');
    expect(book.categories, contains('科幻'));
    expect(book.navigationUrl, isNull);
  });

  test('feed 级 search 模板可被提取，且 {searchTerms} 不被 URL 转义', () {
    final tpl = engine().parseSearchTemplate(_feed);
    expect(tpl, isNotNull);
    expect(tpl, contains('{searchTerms}'));
    expect(tpl, startsWith('https://example.com/'));
    // 替换后即为可请求的搜索地址
    expect(tpl!.replaceAll('{searchTerms}', '三体'),
        'https://example.com/opds/search?q=三体');
  });

  test('相对链接统一解析为绝对地址', () {
    final book = engine().parseAtom(_feed)[1];
    expect(book.links.every((l) => l.href.startsWith('https://')), isTrue);
  });

  test('UI→引擎→导入 的调用链契约（源码锁定，防止再次成为孤儿）', () {
    final discover = File('lib/ui/main/discover/discover_screen.dart').readAsStringSync();
    expect(discover, contains('OpdsCatalogScreen'));
    expect(discover, contains('OPDS 目录'));

    final screen = File('lib/ui/main/discover/opds_catalog_screen.dart').readAsStringSync();
    expect(screen, contains('engine.fetchCatalog'));
    expect(screen, contains('engine.search'));
    expect(screen, contains('engine.downloadBook'));
    expect(screen, contains('ImportBookService().importPath'));

    final engineSrc = File('lib/help/source/opds_engine.dart').readAsStringSync();
    expect(engineSrc, contains('List<OpdsEntry> parseAtom('));
    expect(engineSrc, contains('parseSearchTemplate'));
  });

  testWidgets('OPDS 目录页无地址时渲染引导态，不发起网络请求', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OpdsCatalogScreen()));
    await tester.pumpAndSettle();
    expect(find.text('OPDS 目录'), findsOneWidget);
    expect(find.textContaining('输入 OPDS 目录地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
