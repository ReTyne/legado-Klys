import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legado_md3/constant/book_type.dart';
import 'package:legado_md3/constant/book_group_virtual.dart';
import 'package:legado_md3/help/config/prefer_key_map.dart';
import 'package:legado_md3/data/model/book.dart';

String src(String p) => File(p).readAsStringSync();

/// 批次 5 · 数据层根基回归：
/// 16 BookType 位标志 + 旧备份重映射、17 onOpen 7 虚拟分组幂等 + 修复 SQL、
/// 18 偏好键名映射层 + DAO 位运算分组过滤。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ==================== 16 位标志体系 ====================
  group('BookType 位标志逐字对齐 legado-E BookType.kt', () {
    test('9 个位标志与 allBookType 掩码数值完全一致', () {
      expect(BookType.video, 4); // 0b100
      expect(BookType.text, 8); // 0b1000
      expect(BookType.updateError, 16); // 0b10000
      expect(BookType.audio, 32); // 0b100000
      expect(BookType.image, 64); // 0b1000000
      expect(BookType.webFile, 128); // 0b10000000
      expect(BookType.local, 256); // 0b100000000
      expect(BookType.archive, 512); // 0b1000000000
      expect(BookType.notShelf, 1024); // 0b10000000000
      expect(BookType.allBookType, 4 | 8 | 64 | 32 | 128);
      expect(BookType.allBookTypeLocal, BookType.allBookType | 256);
      expect(BookType.localTag, 'loc_book');
      expect(BookType.webDavTag, 'webDav::');
    });

    test('hasFlag / notFlag 即上游 type & mask 判定，可叠加', () {
      const int localText = BookType.text | BookType.local; // 264
      expect(BookType.hasFlag(localText, BookType.text), isTrue);
      expect(BookType.hasFlag(localText, BookType.local), isTrue);
      expect(BookType.hasFlag(localText, BookType.audio), isFalse);
      expect(BookType.notFlag(localText, BookType.audio), isTrue);
      expect(BookType.isBitmapType(264), isTrue);
      expect(BookType.isBitmapType(4), isFalse); // 顺序枚举上限
    });

    test('remapLegacyType 复刻 Migration_54_55，且幂等 + origin 置 local 位', () {
      // BookSourceType 0/1/2/3 -> text/audio/image/webFile
      expect(BookType.remapLegacyType(BookSourceType.defaultType), BookType.text);
      expect(BookType.remapLegacyType(BookSourceType.audio), BookType.audio);
      expect(BookType.remapLegacyType(BookSourceType.image), BookType.image);
      expect(BookType.remapLegacyType(BookSourceType.file), BookType.webFile);
      // 4 video 旧值与位标志数值相同；>=8 已是位标志，保持
      expect(BookType.remapLegacyType(BookSourceType.video), BookType.video);
      expect(BookType.remapLegacyType(BookType.text), BookType.text);
      // origin 前缀补 local 位
      expect(
        BookType.remapLegacyType(0, origin: 'loc_book/xx'),
        BookType.text | BookType.local,
      );
      expect(
        BookType.remapLegacyType(1, origin: 'webDav::a.mp3'),
        BookType.audio | BookType.local,
      );
      expect(BookType.remapLegacyType(0, origin: 'https://x'), BookType.text);
      // 幂等：对结果再跑一次不改变
      const int once = BookType.text | BookType.local;
      expect(BookType.remapLegacyType(once, origin: 'loc_book/x'), once);
    });

    test('toFlutterEnum / fromFlutterEnum 顺序枚举↔位标志可往返', () {
      for (final int e in <int>[0, 1, 2, 3, 4]) {
        final int flags = BookType.fromFlutterEnum(e);
        // video(4) 是位标志但 < text(8)：与 Flutter typeVideo(4) 数值/语义相同，
        // isBitmapType 按设计返回 false（fromMap 无需转换），故此处跳过。
        if (e != BookType.flutterVideo) {
          expect(BookType.isBitmapType(flags), isTrue, reason: 'enum=$e');
        }
        // flutterLocal(1) 与 flutterAudio(2) 等都落回自身枚举
        expect(BookType.toFlutterEnum(flags), e, reason: 'enum=$e flags=$flags');
      }
      expect(BookType.fromFlutterEnum(0), BookType.text);
      expect(BookType.fromFlutterEnum(1), BookType.text | BookType.local);
      expect(
        BookType.fromFlutterEnum(2, isLocal: true),
        BookType.audio | BookType.local,
      );
    });
  });

  // ==================== 16/18 DAO 位运算分组过滤 ====================
  group('BookGroupQuery 位运算分组过滤（对齐 BookDao.flowByGroup）', () {
    test('buildFlowByGroupWhere 逐字复刻上游 SQL 表达式', () {
      expect(
        BookGroupQuery.buildFlowByGroupWhere(VirtualBookGroup.idRoot),
        contains('type & 8 > 0'),
      );
      expect(
        BookGroupQuery.buildFlowByGroupWhere(VirtualBookGroup.idRoot),
        contains('and type & 256 = 0'),
      );
      expect(
        BookGroupQuery.buildFlowByGroupWhere(VirtualBookGroup.idRoot),
        contains('(SELECT sum(groupId) FROM book_groups where groupId > 0) & `group`'),
      );
      expect(
        BookGroupQuery.buildFlowByGroupWhere(VirtualBookGroup.idRoot),
        contains('groupId = -4) != 1'),
      );
      expect(
        BookGroupQuery.buildFlowByGroupWhere(VirtualBookGroup.idNetNone),
        contains('type & 32 = 0 and type & 256 = 0 and type & 4 = 0'),
      );
      expect(
        BookGroupQuery.buildFlowByGroupWhere(VirtualBookGroup.idError),
        'type & 16 > 0',
      );
      expect(
        BookGroupQuery.buildFlowByGroupWhere(4),
        '(`group` & 4) > 0',
      );
      // 列名可切到本项目 group_name
      expect(
        BookGroupQuery.buildFlowByGroupWhere(4, groupColumn: 'group_name'),
        contains('group_name & 4'),
      );
      expect(
        BookGroupQuery.buildFlowByGroupSql(VirtualBookGroup.idAll),
        contains('order by durChapterTime desc'),
      );
    });

    test('matchesGroup 与各虚拟分支位规则一致（含 flowRoot 的 != 1 语义）', () {
      const int text = BookType.text;
      bool match(int groupId, int typeFlags, {int bits = 0, int sum = 0, int show = 1}) =>
          BookGroupQuery.matchesGroup(
            typeFlags: typeFlags,
            groupBits: bits,
            groupId: groupId,
            userGroupsSum: sum,
            netNoneShow: show,
          );
      expect(match(VirtualBookGroup.idAll, text), isTrue);
      expect(match(VirtualBookGroup.idAudio, BookType.audio), isTrue);
      expect(match(VirtualBookGroup.idAudio, text), isFalse);
      expect(match(VirtualBookGroup.idLocal, text | BookType.local), isTrue);
      expect(match(VirtualBookGroup.idVideo, BookType.video), isTrue);
      expect(match(VirtualBookGroup.idError, text | BookType.updateError), isTrue);
      expect(match(VirtualBookGroup.idNetNone, text, bits: 0, sum: 1), isTrue);
      expect(match(VirtualBookGroup.idNetNone, text, bits: 1, sum: 1), isFalse);
      // 用户分组位与
      expect(match(4, text, bits: 4 | 2), isTrue);
      expect(match(8, text, bits: 4), isFalse);
      // flowRoot：上游 `(show of IdNetNone) != 1`，逐字照抄
      expect(match(VirtualBookGroup.idRoot, text, show: 1), isFalse);
      expect(match(VirtualBookGroup.idRoot, text, show: 0), isTrue);
    });

    test('上游 flowByGroup SQL 可在位标志列上真实执行', () async {
      final Database db = await databaseFactory.openDatabase(':memory:');
      addTearDown(() => db.close());
      await db.execute(
          'CREATE TABLE books (name TEXT, type INTEGER, `group` INTEGER, durChapterTime INTEGER)');
      await db.execute('CREATE TABLE book_groups (groupId INTEGER, show INTEGER)');
      await db.insert('books',
          <String, Object?>{'name': '文本', 'type': 8, 'group': 0, 'durChapterTime': 1});
      await db.insert('books',
          <String, Object?>{'name': '音频', 'type': 32, 'group': 0, 'durChapterTime': 2});
      await db.insert('books',
          <String, Object?>{'name': '本地文本', 'type': 8 | 256, 'group': 0, 'durChapterTime': 3});
      await db.insert('books',
          <String, Object?>{'name': '更新失败', 'type': 8 | 16, 'group': 0, 'durChapterTime': 4});

      final audio = await db.rawQuery(
          BookGroupQuery.buildFlowByGroupSql(VirtualBookGroup.idAudio));
      expect(audio.map((r) => r['name']).toList(), <String>['音频']);
      final local = await db.rawQuery(
          BookGroupQuery.buildFlowByGroupSql(VirtualBookGroup.idLocal));
      expect(local.map((r) => r['name']).toList(), <String>['本地文本']);
      final error = await db.rawQuery(
          BookGroupQuery.buildFlowByGroupSql(VirtualBookGroup.idError));
      expect(error.map((r) => r['name']).toList(), <String>['更新失败']);
    });
  });

  // ==================== 17 onOpen 虚拟分组 + 修复 SQL ====================
  group('onOpen 7 虚拟分组幂等插入 + 脏数据修复 SQL（ffi 真库）', () {
    Future<Database> groupsDb() async {
      final Database db = await databaseFactory.openDatabase(':memory:');
      await db.execute('CREATE TABLE book_groups ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, "order" INTEGER, '
          'show INTEGER DEFAULT 1, cover TEXT, groupId INTEGER, '
          'coverStyle INTEGER, enableRefresh INTEGER DEFAULT 1)');
      return db;
    }

    test('执行两遍 buildInsertSqls 仍为 7 行，且 order/show/enableRefresh 对齐', () async {
      final Database db = await groupsDb();
      addTearDown(() => db.close());
      final List<String> sqls = VirtualBookGroup.buildInsertSqls();
      expect(sqls.length, 7);
      for (final String s in sqls) {
        expect(s, contains('where not exists'));
      }
      for (final String s in sqls) {
        await db.execute(s);
      }
      for (final String s in sqls) {
        await db.execute(s); // 第二遍：幂等
      }
      final rows = await db.query('book_groups');
      expect(rows.length, 7);
      final byId = <int, Map<String, Object?>>{
        for (final r in rows) r['groupId'] as int: r,
      };
      expect(byId.keys.toSet(),
          <int>{-1, -2, -3, -4, -5, -6, -11});
      expect(byId[-1]!['name'], '全部');
      expect(byId[-1]!['order'], -10);
      expect(byId[-2]!['enableRefresh'], 0); // IdLocal 关刷新
      expect(byId[-2]!['order'], -9);
      expect(byId[-5]!['show'], 0); // IdLocalNone 隐藏
      expect(byId[-11]!['order'], -1); // 更新失败
      expect(byId[-6]!['name'], '视频');
      // builtIns 常量与上游 Id 值一致
      expect(VirtualBookGroup.idAll, -1);
      expect(VirtualBookGroup.idError, -11);
      expect(VirtualBookGroup.idRoot, -100);
    });

    test('buildRepairSqls 修复 loginUi=null 字符串与 concurrentRate 空值，幂等', () async {
      final Database db = await databaseFactory.openDatabase(':memory:');
      addTearDown(() => db.close());
      await db.execute('CREATE TABLE book_sources (loginUi TEXT)');
      await db.execute('CREATE TABLE rss_sources (loginUi TEXT)');
      await db.execute('CREATE TABLE http_tts (concurrentRate INTEGER)');
      await db.insert('book_sources', <String, Object?>{'loginUi': 'null'});
      await db.insert('book_sources', <String, Object?>{'loginUi': 'ok'});
      await db.insert('rss_sources', <String, Object?>{'loginUi': 'null'});
      await db.insert('http_tts', <String, Object?>{'concurrentRate': null});

      for (final String s in VirtualBookGroup.buildRepairSqls()) {
        await db.execute(s);
      }
      for (final String s in VirtualBookGroup.buildRepairSqls()) {
        await db.execute(s); // 幂等
      }
      final bs = await db.query('book_sources');
      expect(bs.where((r) => r['loginUi'] == null).length, 1);
      expect(bs.where((r) => r['loginUi'] == 'ok').length, 1);
      final rs = await db.query('rss_sources');
      expect(rs.single['loginUi'], isNull);
      final tt = await db.query('http_tts');
      expect(tt.single['concurrentRate'], 0);
      // 上游 4 条修复 SQL 原文契约留存
      expect(VirtualBookGroup.upstreamRepairSqls.length, 4);
      expect(VirtualBookGroup.upstreamRepairSqls.first,
          "update book_sources set loginUi = null where loginUi = 'null'");
    });
  });

  // ==================== 18 偏好键名映射层 ====================
  group('偏好键名映射往返（Android ↔ Flutter 备份互通）', () {
    test('toUpstream / fromUpstream 单键互逆，自造键映射到上游字符串值', () {
      expect(PreferKeyMap.toUpstream('cover_useDefault'), 'useDefaultCover');
      expect(PreferKeyMap.toUpstream('exportToWebDav'), 'webDavCacheBackup');
      expect(PreferKeyMap.toUpstream('theme_mode'), 'themeMode');
      expect(PreferKeyMap.toUpstream('threadCount'), 'threadCount'); // 同名直通
      expect(PreferKeyMap.fromUpstream('webDavCacheBackup'), 'exportToWebDav');
      expect(PreferKeyMap.fromUpstream('coverShowAuthor'), 'cover_showAuthor');
      expect(PreferKeyMap.fromUpstream('unknownKey'), 'unknownKey');
      for (final String k in PreferKeyMap.flutterToUpstream.keys) {
        expect(PreferKeyMap.fromUpstream(PreferKeyMap.toUpstream(k)), k);
      }
    });

    test('exportToUpstream / importFromUpstream 批量往返无损', () {
      final Map<String, dynamic> flutterPrefs = <String, dynamic>{
        'cover_useDefault': true,
        'cover_showName': false,
        'cover_showAuthor': true,
        'exportToWebDav': false,
        'theme_mode': 2,
        'threadCount': 32,
        'userAgent': 'UA',
      };
      final Map<String, dynamic> upstream = PreferKeyMap.exportToUpstream(flutterPrefs);
      expect(upstream.containsKey('useDefaultCover'), isTrue);
      expect(upstream.containsKey('webDavCacheBackup'), isTrue);
      expect(upstream.containsKey('cover_useDefault'), isFalse);
      expect(upstream['threadCount'], 32); // 同名键原样
      expect(PreferKeyMap.importFromUpstream(upstream), flutterPrefs);
    });

    test('UpstreamPrefKey 字符串值与 PreferKey.kt 一致（键名≠常量名陷阱）', () {
      expect(UpstreamPrefKey.clickActionTL, 'clickActionTopLeft');
      expect(UpstreamPrefKey.ttsEngine, 'appTtsEngine');
      expect(UpstreamPrefKey.prevKeys, 'prevKeyCodes');
      expect(UpstreamPrefKey.nextKeys, 'nextKeyCodes');
      expect(UpstreamPrefKey.textSelectAble, 'selectText');
      expect(UpstreamPrefKey.keepLight, 'keep_light');
      expect(UpstreamPrefKey.doublePageHorizontal, 'doubleHorizontalPage');
      expect(UpstreamPrefKey.readUrlOpenInBrowser, 'readUrlInBrowser');
      expect(kUpstreamClickActionKeys.length, 9);
    });

    test('themeMode 与 clickActions 值级转换器（不等价处按约定退化）', () {
      expect(PreferKeyMap.importThemeMode('2'), 2);
      expect(PreferKeyMap.importThemeMode('3'), 0); // EInk 合并语义不等价，退回系统
      expect(PreferKeyMap.importThemeMode(1), 1);
      expect(PreferKeyMap.importThemeMode('bad'), 0);
      expect(PreferKeyMap.exportThemeMode(1), '1');
      expect(PreferKeyMap.exportThemeMode(0, eink: true), '3');

      final Map<String, dynamic> upstream9 = <String, dynamic>{
        UpstreamPrefKey.clickActionTL: 2,
        UpstreamPrefKey.clickActionTC: 2,
        UpstreamPrefKey.clickActionTR: 1,
        UpstreamPrefKey.clickActionML: 2,
        UpstreamPrefKey.clickActionMC: 0,
        UpstreamPrefKey.clickActionMR: 1,
        UpstreamPrefKey.clickActionBL: 2,
        UpstreamPrefKey.clickActionBC: 1,
        UpstreamPrefKey.clickActionBR: 1,
      };
      final String csv = PreferKeyMap.importClickActions(upstream9);
      expect(csv.split(',').length, 9);
      expect(csv, '2,2,1,2,0,1,2,1,1');
      final Map<String, dynamic> back = PreferKeyMap.exportClickActions(csv);
      expect(back.length, 9);
      // 结构往返：9 键顺序与值一致（码值不翻译，显式标注的不等价）
      for (int i = 0; i < kUpstreamClickActionKeys.length; i++) {
        expect(back[kUpstreamClickActionKeys[i]], upstream9[kUpstreamClickActionKeys[i]]);
      }
    });
  });

  // ==================== 备份导入/导出边界行为 ====================
  group('Book 备份边界：位标志导入重映射 + toUpstreamMap 导出', () {
    test('fromMap 把上游位标志 type 转成顺序枚举并保留 local 位', () {
      final Book b = Book.fromMap(<String, dynamic>{
        'name': 'n',
        'author': 'a',
        'type': BookType.text | BookType.local, // 264
        'origin': 'loc_book/x',
      });
      expect(b.type, BookType.flutterLocal);
      expect(b.local, isTrue);
      // 普通 Flutter 自身备份（0..4 顺序枚举）原样保留，不被误转
      final Book b2 = Book.fromMap(<String, dynamic>{
        'name': 'n',
        'author': 'a',
        'type': 2,
      });
      expect(b2.type, 2);
      // 字符串数字也兼容
      final Book b3 = Book.fromMap(<String, dynamic>{
        'name': 'n',
        'author': 'a',
        'type': '32',
      });
      expect(b3.type, BookType.flutterAudio);
    });

    test('toUpstreamMap 输出位标志 type（跨端导出）', () {
      final Book b = Book(
        name: 'n',
        author: 'a',
        type: 2,
        local: true,
        origin: 'https://x',
      );
      final Map<String, dynamic> m = b.toUpstreamMap();
      expect(m['type'], BookType.audio | BookType.local);
      expect(BookType.hasFlag(m['type'] as int, BookType.local), isTrue);
    });
  });

  // ==================== 调用链闭环源码契约（防死代码） ====================
  group('调用链闭环：映射/SQL 被真实消费', () {
    test('Book.fromMap（备份导入）与 DAO / onOpen 真实消费新增层', () {
      expect(src('lib/data/model/book.dart'), contains('BookType.isBitmapType'));
      expect(src('lib/data/model/book.dart'), contains('BookType.toFlutterEnum'));
      expect(src('lib/data/model/book.dart'), contains('toUpstreamMap'));
      expect(src('lib/data/dao/book_dao.dart'), contains('getBooksByTypeBitmask'));
      expect(src('lib/data/dao/book_dao.dart'), contains('BookGroupQuery.matchesGroup'));
      expect(src('lib/data/local/app_database.dart'), contains('onOpen: _onOpen'));
      expect(src('lib/data/local/app_database.dart'),
          contains('VirtualBookGroup.buildInsertSqls()'));
      expect(src('lib/data/local/app_database.dart'),
          contains('VirtualBookGroup.buildRepairSqls()'));
      // BackupService 恢复书籍确实走 Book.fromMap（导入消费点）
      expect(src('lib/help/storage/backup_service.dart'), contains('Book.fromMap(map)'));
    });

    test('AppPrefs 真实消费偏好键名映射层', () {
      expect(src('lib/help/config/app_config.dart'), contains("import 'prefer_key_map.dart'"));
      expect(src('lib/help/config/app_constants.dart'),
          contains('PreferKeyMap.toUpstream(flutterKey)'));
      expect(src('lib/help/config/app_constants.dart'),
          contains('PreferKeyMap.importFromUpstream(upstream)'));
      expect(src('lib/help/config/app_constants.dart'),
          contains('PreferKeyMap.exportToUpstream(raw)'));
    });
  });
}
