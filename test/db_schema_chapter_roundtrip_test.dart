import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';

import 'helpers/lib_source_helper.dart';

/// 回归 P0：全新安装（只走 onCreate）时 book_chapters 曾缺 isVip / update_time 列，
/// 导致 BookChapter.toMap 写入抛 "no such column"，章节目录无法保存；
/// 老用户因走 v9 迁移补列而无碍，故只有新装用户中招、极易漏测。
/// 本测试用生产同一份建表 SQL 建真库，跑一遍完整 写→读 往返。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> freshDb() => databaseFactory.openDatabase(':memory:');

  test('全新安装 book_chapters 建表列覆盖 BookChapter.toMap 全部键', () async {
    final db = await freshDb();
    addTearDown(() => db.close());
    await db.execute(DatabaseService.bookChaptersTableSql);
    final cols = await db.rawQuery('PRAGMA table_info(book_chapters)');
    final names = cols.map((r) => r['name'] as String).toSet();

    final map = BookChapter(index: 0, title: 't', url: 'u').toMap('书', '作者');
    for (final key in map.keys) {
      expect(names.contains(key), isTrue, reason: 'book_chapters 缺列: $key');
    }
    expect(
      names.containsAll(
          const ['isVip', 'update_time', 'tag', 'resourceUrl', 'baseUrl']),
      isTrue,
    );
  });

  test('章节完整往返：isVip/updateTime/tag/resourceUrl/baseUrl 保真', () async {
    final db = await freshDb();
    addTearDown(() => db.close());
    await db.execute(DatabaseService.bookChaptersTableSql);

    final ch = BookChapter(
      index: 3,
      title: '第三章 风起',
      url: 'https://example.com/c/3',
      isVip: true,
      isPay: true,
      updateTime: '2026-11-05',
      tag: 'VIP · 3千字',
      resourceUrl: 'https://example.com/audio/3.mp3',
      baseUrl: 'https://example.com/toc',
      content: '正文内容',
      startPos: 10,
      endPos: 200,
      variable: 'k=v',
    );
    // 关键：全新安装库上插入不得抛异常（修复前此处会 no such column: isVip）
    await db.insert('book_chapters', ch.toMap('书名', '作者'));
    final rows = await db.query('book_chapters');
    expect(rows, hasLength(1));

    final back = BookChapter.fromMap(rows.first);
    expect(back.index, 3);
    expect(back.title, '第三章 风起');
    expect(back.isVip, isTrue);
    expect(back.isPay, isTrue);
    expect(back.updateTime, '2026-11-05');
    expect(back.tag, 'VIP · 3千字');
    expect(back.resourceUrl, 'https://example.com/audio/3.mp3');
    expect(back.baseUrl, 'https://example.com/toc');
    expect(back.content, '正文内容');
    expect(back.startPos, 10);
    expect(back.endPos, 200);
    expect(back.variable, 'k=v');
  });

  test('books 建表列覆盖 Book.toMap 全部键，且冗余死列已清理', () async {
    final db = await freshDb();
    addTearDown(() => db.close());
    await db.execute(DatabaseService.booksTableSql);
    final cols = await db.rawQuery('PRAGMA table_info(books)');
    final names = cols.map((r) => r['name'] as String).toSet();

    final book = Book(
      name: '十日终焉',
      author: '杀虫队队员',
      tag: '悬疑',
      group: '默认',
      order: 2,
    );
    for (final key in book.toMap().keys) {
      expect(names.contains(key), isTrue, reason: 'books 缺列: $key');
    }
    // 模型不读写的旧 schema 冗余列不再新建
    for (final dead in const [
      'latestChapterTitle',
      'lastChapterTime',
      'updateTime',
      'order',
      'groupId',
    ]) {
      expect(names.contains(dead), isFalse, reason: '冗余死列未清理: $dead');
    }
    await db.insert('books', book.toMap());
    expect(await db.query('books'), hasLength(1));
  });

  test('章节 JS 上下文输出 resourceUrl/tag/baseUrl（消除 __wrapChapter 死读）', () {
    final ch = BookChapter(
      index: 0,
      title: '第一章',
      url: 'u',
      resourceUrl: 'https://example.com/a.mp3',
      tag: 'VIP',
      baseUrl: 'https://example.com/toc',
    );
    final ctx = ch.jsContext('https://example.com/book');
    expect(ctx['resourceUrl'], 'https://example.com/a.mp3');
    expect(ctx['tag'], 'VIP');
    expect(ctx['baseUrl'], 'https://example.com/toc');
    expect(ch.toJson()['resourceUrl'], 'https://example.com/a.mp3');

    // JS 桥契约：__wrapChapter.getResourceUrl 读取的正是该键
    const bridgePath = 'lib/help/source/js/legado_bridge_js.dart';
    final bridge = File(bridgePath).readAsStringSync() +
        extraLibrarySources(bridgePath);
    expect(bridge, contains('this.resourceUrl'));
  });
}
