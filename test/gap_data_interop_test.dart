import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/constant/book_type.dart';
import 'package:legado_md3/data/entities/book_group.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source_part.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';

/// 跨端备份数据互通的纯数据回归：只做 Map ↔ 模型的宽松解析与往返，
/// 不初始化任何 Flutter binding / 平台通道。
void main() {
  group('1 Book 宽松解析、字段别名与新增字段', () {
    test('bool/字符串字数/数字分组/章节标题别名均可读且往返保真', () {
      final book = Book.fromMap(<String, dynamic>{
        'name': '十日终焉',
        'author': '杀虫队队员',
        'canUpdate': true,
        'wordCount': '12万字',
        'group': 3,
        'latestChapterTitle': '第 100 章',
        'tocUrl': 'https://example.com/toc',
        'durChapterTitle': '第 99 章',
        'customTag': '悬疑',
        'customIntro': '自定义简介',
        'charset': 'GBK',
        'durVolumeIndex': 2,
        'chapterInVolumeIndex': 5,
        'totalChapterNum': 100,
        'lastCheckCount': 7,
        'originOrder': 9,
        'syncTime': 1700000000000,
      });
      expect(book.canUpdate, isTrue);
      expect(book.wordCount, 12);
      expect(book.group, '3');
      expect(book.lastChapter, '第 100 章');
      expect(book.tocUrl, 'https://example.com/toc');
      expect(book.noteUrl, 'https://example.com/toc');
      expect(book.durChapterTitle, '第 99 章');
      expect(book.customTag, '悬疑');
      expect(book.customIntro, '自定义简介');
      expect(book.charset, 'GBK');
      expect(book.durVolumeIndex, 2);
      expect(book.chapterInVolumeIndex, 5);
      expect(book.totalChapterNum, 100);
      expect(book.lastCheckCount, 7);
      expect(book.originOrder, 9);
      expect(book.syncTime, 1700000000000);

      final back = Book.fromMap(book.toMap());
      expect(back.canUpdate, book.canUpdate);
      expect(back.wordCount, book.wordCount);
      expect(back.lastChapter, book.lastChapter);
      expect(back.tocUrl, book.tocUrl);
      expect(back.customTag, book.customTag);
      expect(back.syncTime, book.syncTime);
      expect(back.originOrder, book.originOrder);
    });

    test('坏数据不抛异常并走安全回退', () {
      final book = Book.fromMap(<String, dynamic>{
        'name': 'n',
        'author': 'a',
        'canUpdate': 'not-a-bool',
        'wordCount': 'abc',
        'type': 'bad',
        'local': 'true',
      });
      expect(book.canUpdate, isTrue);
      expect(book.wordCount, isNull);
      expect(book.type, 0);
      expect(book.local, isTrue);
    });
  });

  group('2 & 3 toUpstreamMap 与旧类型重映射', () {
    test('导出 type 为位标志并携带跨端字段别名', () {
      final book = Book(
        name: 'n',
        author: 'a',
        type: Book.typeAudio,
        local: true,
        origin: 'loc_book/x',
        lastChapter: '第 3 章',
        noteUrl: 'https://x/note',
      );
      final map = book.toUpstreamMap();
      expect(map['type'], BookType.audio | BookType.local);
      expect(map['latestChapterTitle'], '第 3 章');
      expect(map['tocUrl'], isNotNull);
    });

    test('备份来源的旧顺序类型经位标志还原为本地枚举', () {
      final book = Book.fromMap(<String, dynamic>{
        'name': 'n',
        'author': 'a',
        'type': 1,
        'canUpdate': true,
      });
      expect(book.type, Book.typeAudio);
      final localBook = Book.fromMap(<String, dynamic>{
        'name': 'n',
        'author': 'a',
        'type': 0,
        'tocUrl': 'https://x/toc',
        'origin': 'loc_book/x',
      });
      expect(localBook.type, Book.typeLocal);
      // 本地库顺序枚举未被误重映射
      expect(Book.fromMap(<String, dynamic>{'name': 'n', 'author': 'a', 'type': 2}).type, 2);
    });
  });

  group('4 Bookmark 宽松解析与原文位', () {
    test('time/chapterPos/chapterName 别名与 bookText 往返', () {
      final mark = Bookmark.fromMap(<String, dynamic>{
        'bookName': '书',
        'bookAuthor': '作者',
        'chapterPos': 3,
        'chapterName': '第三章',
        'pagePos': 2,
        'time': 123456,
        'content': '划线内容',
        'bookText': '原文片段',
      });
      expect(mark.chapterIndex, 3);
      expect(mark.chapterTitle, '第三章');
      expect(mark.pageIndex, 2);
      expect(mark.createTime, 123456);
      expect(mark.bookText, '原文片段');
      final map = mark.toMap();
      expect(map['bookText'], '原文片段');
      expect(Bookmark.fromMap(map).createTime, 123456);
      expect(
        () => Bookmark.fromMap(<String, dynamic>{
          'bookName': '书',
          'bookAuthor': '作者',
          'createTime': 'bad',
          'chapterIndex': '2',
        }),
        returnsNormally,
      );
    });
  });

  group('5 BookChapter 分片与插图字段', () {
    test('addFields 写入 toMap 并从 Map 还原', () {
      final chapter = BookChapter(
        title: '第三章',
        url: 'https://x/3',
        index: 3,
        wordCount: 1200,
        startFragmentId: 'frag-start',
        endFragmentId: 'frag-end',
        imgUrl: 'https://x/3.png',
        titleMD5: 'abc123',
      );
      final map = chapter.toMap('书', '作者');
      expect(map['wordCount'], 1200);
      expect(map['startFragmentId'], 'frag-start');
      expect(map['endFragmentId'], 'frag-end');
      expect(map['imgUrl'], 'https://x/3.png');
      expect(map['titleMD5'], 'abc123');
      final back = BookChapter.fromMap(map);
      expect(back.wordCount, 1200);
      expect(back.startFragmentId, 'frag-start');
      expect(back.endFragmentId, 'frag-end');
      expect(back.imgUrl, 'https://x/3.png');
      expect(back.titleMD5, 'abc123');
      expect(chapter.toJson()['imgUrl'], 'https://x/3.png');
    });

    test('字符串标志与索引宽松解析', () {
      final back = BookChapter.fromMap(<String, dynamic>{
        'title': 't',
        'url': 'u',
        'chapter_index': '4',
        'isVip': 'true',
        'wordCount': '999',
      });
      expect(back.index, 4);
      expect(back.isVip, isTrue);
      expect(back.wordCount, 999);
    });
  });

  group('6 ReadRecord 跨设备字段', () {
    test('deviceId/readTime/lastRead 往返且宽松解析', () {
      final record = ReadRecord.fromMap(<String, dynamic>{
        'bookName': '书',
        'author': '作者',
        'duration': 100,
        'date': 200,
        'deviceId': 'device-a',
        'readTime': 300,
        'lastRead': 400,
      });
      expect(record.deviceId, 'device-a');
      expect(record.readTime, 300);
      expect(record.lastRead, 400);
      final back = ReadRecord.fromMap(record.toMap());
      expect(back.deviceId, 'device-a');
      expect(back.lastRead, 400);
    });
  });

  group('7 BookGroup 分组配置字段与别名', () {
    test('groupId/groupName 等别名与开关往返', () {
      final group = BookGroup.fromMap(<String, dynamic>{
        'groupId': 8,
        'groupName': '玄幻',
        'order': 2,
        'enableRefresh': 0,
        'bookSort': 1,
        'onlyUpdateRead': 1,
      });
      expect(group.groupId, 8);
      expect(group.name, '玄幻');
      expect(group.enableRefresh, isFalse);
      expect(group.bookSort, 1);
      expect(group.onlyUpdateRead, isTrue);
      final map = group.toMap();
      expect(map['enableRefresh'], 0);
      expect(map['onlyUpdateRead'], 1);
      expect(BookGroup.fromMap(map).name, '玄幻');
    });
  });

  group('8 RssSource 默认值、开关与样式分离', () {
    test('三个开关默认 true，showWebLog 字段可往返', () {
      final source = RssSource();
      expect(source.enabledCookieJar, isTrue);
      expect(source.enableJs, isTrue);
      expect(source.loadWithBaseUrl, isTrue);
      expect(source.showWebLog, isTrue);
      expect(source.toMap()['showWebLog'], 1);
      expect(RssSource.fromMap(source.toMap()).showWebLog, isTrue);
    });

    test('Map/Json 中 articleStyle 与 startStyle 分别解析导出', () {
      final fromMap = RssSource.fromMap(<String, dynamic>{
        'name': 'r',
        'url': 'u',
        'articleStyle': 2,
        'startStyle': 'body{}',
        'enabledCookieJar': 0,
      });
      expect(fromMap.articleStyle, 2);
      expect(fromMap.startStyle, 'body{}');
      expect(fromMap.enabledCookieJar, isFalse);

      final fromJson = RssSource.fromJson(<String, dynamic>{
        'sourceName': 'r',
        'sourceUrl': 'u',
        'articleStyle': 3,
        'startStyle': '.list{}',
      });
      expect(fromJson.articleStyle, 3);
      expect(fromJson.startStyle, '.list{}');
      expect(fromJson.toJson()['startStyle'], '.list{}');
      expect(fromJson.toJson()['articleStyle'], 3);
    });
  });

  group('9 TxtTocRule rule 别名与 replacement', () {
    test('字符串 id、rule 别名、替换表达式往返', () {
      final rule = TxtTocRule.fromMap(<String, dynamic>{
        'id': '5',
        'name': '通用',
        'rule': '第.+章',
        'replacement': '章',
      });
      expect(rule.id, 5);
      expect(rule.chapterRule, '第.+章');
      expect(rule.replacement, '章');
      expect(rule.toMap()['replacement'], '章');
    });
  });

  group('10 ReplaceRule 跨端 JSON 键导出与还原', () {
    test('toLegadoJson 使用通用键名且能被 fromMap 读回', () {
      final rule = ReplaceRule(
        replaceSummary: '清理广告',
        replaceRule: '广告',
        replacement: '',
        enable: true,
        isRegex: true,
        isContent: true,
      );
      final json = rule.toLegadoJson();
      expect(json['name'], '清理广告');
      expect(json['pattern'], '广告');
      expect(json['isEnabled'], isTrue);
      expect(json['scopeContent'], isTrue);
      final back = ReplaceRule.fromMap(json);
      expect(back.replaceSummary, '清理广告');
      expect(back.replaceRule, '广告');
    });
  });

  group('11 BookSourcePart 运行状态投影字段', () {
    test('投影字段宽松解析并回填 BookSource', () {
      final part = BookSourcePart.fromMap(<String, dynamic>{
        'bookSourceUrl': 'https://x',
        'lastUpdateTime': '123',
        'respondTime': '180000',
        'weight': '5',
        'eventListener': 1,
      });
      expect(part.lastUpdateTime, 123);
      expect(part.respondTime, 180000);
      expect(part.weight, 5);
      expect(part.eventListener, isTrue);
      final source = part.toBookSource();
      expect(source.weight, 5);
      expect(source.eventListener, isTrue);
    });
  });

  group('12 RssArticle 扩展字段与字符串 pubDate', () {
    test('扩展字段往返，pubDate 字符串兼容且坏数据不崩溃', () {
      final article = RssArticle.fromMap(<String, dynamic>{
        'title': '标题',
        'link': 'https://x/1',
        'pubDate': '1700000000000',
        'origin': 'o',
        'sort': '2',
        'order': 3,
        'group': 'g',
        'variable': 'v',
        'type': 4,
        'durPos': 0.5,
        'isRead': 1,
      });
      expect(article.pubDate, 1700000000000);
      expect(article.origin, 'o');
      expect(article.sort, '2');
      expect(article.order, 3);
      expect(article.group, 'g');
      expect(article.variable, 'v');
      expect(article.type, 4);
      expect(article.durPos, 0.5);
      expect(article.read, isTrue);
      final map = article.toMap();
      expect(map['durPos'], 0.5);
      expect(RssArticle.fromMap(map).origin, 'o');
      expect(
        () => RssArticle.fromMap(<String, dynamic>{
          'title': 't',
          'link': 'l',
          'pubDate': 'bad',
        }),
        returnsNormally,
      );
    });
  });

  group('13 默认数据种子幂等', () {
    test('五张表各有一条空表门控的插入语句', () {
      expect(DefaultDataSeed.sqls, hasLength(5));
      final all = DefaultDataSeed.sqls.join('\n');
      for (final table in const [
        'http_tts',
        'txt_toc_rules',
        'rss_sources',
        'dict_rules',
        'keyboard_assists',
      ]) {
        expect(all, contains(table));
      }
      for (final sql in DefaultDataSeed.sqls) {
        expect(sql, contains('WHERE NOT EXISTS'));
      }
    });
  });

  group('14 备份链路接线（源码契约）', () {
    test('书籍/替换规则导出与偏好映射入口均被真实调用', () {
      final backup = File('lib/help/storage/backup_service.dart').readAsStringSync();
      expect(backup, contains('b.toUpstreamMap()'));
      expect(backup, contains('r.toLegadoJson()'));
      expect(backup, contains('AppPrefs.exportForUpstream(prefs)'));
      expect(backup, contains('AppPrefs.importFromUpstream(m, prefs)'));
      final prefs = File('lib/help/config/prefer_key_map.dart').readAsStringSync();
      expect(prefs, contains('exportToUpstream(Map<String, dynamic> flutter)'));
      expect(prefs, contains('importFromUpstream(Map<String, dynamic> upstream)'));
    });
  });
}
