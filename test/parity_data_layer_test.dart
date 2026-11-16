import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legado_md3/constant/app_const.dart';
import 'package:legado_md3/constant/book_type.dart';
import 'package:legado_md3/constant/source_type.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/book_source_part.dart';
import 'package:legado_md3/data/model/explore_kind.dart';
import 'package:legado_md3/data/model/flex_child_style.dart';
import 'package:legado_md3/data/model/row_ui.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rule/book_info_rule.dart';
import 'package:legado_md3/data/model/rule/book_list_rule.dart';
import 'package:legado_md3/data/model/rule/content_rule.dart';
import 'package:legado_md3/data/model/rule/explore_rule.dart';
import 'package:legado_md3/data/model/rule/review_rule.dart';
import 'package:legado_md3/data/model/rule/search_rule.dart';
import 'package:legado_md3/data/model/rule/toc_rule.dart';
import 'package:legado_md3/help/source/check_source_service.dart';
import 'package:legado_md3/help/source/source_help.dart';

/// 书源数据层能力回归：默认值、判等、强类型规则、控件解析、投影查询、
/// DAO 查询与单列更新、分组整理、源统一入口与级联删除。
void main() {
  BookSource makeSource(
    String url, {
    String name = '源',
    String? group,
    int type = 0,
    bool enabled = true,
    bool enabledExplore = true,
    int customOrder = 0,
    String? loginUrl,
    String? exploreUrl,
    String? bookUrlPattern,
    String? comment,
  }) =>
      BookSource(
        bookSourceUrl: url,
        bookSourceName: name,
        bookSourceGroup: group,
        bookSourceType: type,
        enabled: enabled,
        enabledExplore: enabledExplore,
        customOrder: customOrder,
        loginUrl: loginUrl,
        exploreUrl: exploreUrl,
        bookUrlPattern: bookUrlPattern,
        bookSourceComment: comment,
      );

  group('默认值一致性', () {
    test('构造默认值：enabledExplore / enabledCookieJar 为 true，lastUpdateTime 为 0',
        () {
      final s = BookSource(bookSourceUrl: 'u', bookSourceName: 'n');
      expect(s.enabledExplore, isTrue);
      expect(s.enabledCookieJar, isTrue);
      expect(s.lastUpdateTime, 0);
      expect(s.customOrder, 0);
      expect(s.enabled, isTrue);
      expect(s.toMap()['enabledExplore'], 1);
      expect(s.toMap()['enabledCookieJar'], 1);
    });

    test('fromJson / fromMap 缺省字段默认值一致，显式 false 仍保留', () {
      final j =
          BookSource.fromJson({'bookSourceUrl': 'u', 'bookSourceName': 'n'});
      expect(j.enabledExplore, isTrue);
      expect(j.enabledCookieJar, isTrue);
      expect(j.lastUpdateTime, 0);
      final m =
          BookSource.fromMap({'bookSourceUrl': 'u', 'bookSourceName': 'n'});
      expect(m.enabledExplore, isTrue);
      expect(m.enabledCookieJar, isTrue);
      expect(m.lastUpdateTime, 0);

      final explicit = BookSource.fromJson({
        'bookSourceUrl': 'u',
        'enabledExplore': false,
        'enabledCookieJar': false,
      });
      expect(explicit.enabledExplore, isFalse);
      expect(explicit.enabledCookieJar, isFalse);
    });
  });

  group('判等与成员方法', () {
    test('operator == / hashCode 按 bookSourceUrl 判等', () {
      final a = BookSource(bookSourceUrl: 'u', bookSourceName: 'A');
      final b = BookSource(bookSourceUrl: 'u', bookSourceName: 'B');
      final c = BookSource(bookSourceUrl: 'v', bookSourceName: 'A');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(<BookSource>{a, b, c}.length, 2);
    });

    test('equal 全字段比对，含嵌套规则深比较', () {
      final a = BookSource(
        bookSourceUrl: 'u',
        bookSourceName: 'A',
        ruleSearch: {'name': '@text', 'author': 'a'},
      );
      expect(a.equal(BookSource.fromJson(a.toJson())), isTrue);
      final changed = BookSource.fromJson(a.toJson())..bookSourceComment = '改了';
      expect(a.equal(changed), isFalse);
      final ruleChanged = BookSource.fromJson(a.toJson())
        ..ruleSearch = {'name': '@text', 'author': '不同'};
      expect(a.equal(ruleChanged), isFalse);
    });

    test('hasGroup / 展示名 / 变量注释 / 类型位标志 / 校验关键字', () {
      final s = BookSource(
        bookSourceUrl: 'u',
        bookSourceName: '测试源',
        bookSourceGroup: '玄幻, 都市；仙侠、科幻',
        variableComment: '// 用户名\n// 密码\nvarA',
        bookSourceType: BookSourceType.audio,
        ruleSearch: {'checkKeyWord': '我的'},
      );
      expect(s.hasGroup('玄幻'), isTrue);
      expect(s.hasGroup('仙侠'), isTrue);
      expect(s.hasGroup('不存在'), isFalse);
      expect(s.getDisplayNameGroup(), '测试源 (玄幻, 都市；仙侠、科幻)');
      expect(s.getDisplayVariableComment(), '用户名\n密码\nvarA');
      expect(s.getBookType(), BookType.audio);

      expect(makeSource('a', type: BookSourceType.image).getBookType(),
          BookType.image);
      expect(makeSource('a', type: BookSourceType.file).getBookType(),
          BookType.webFile);
      expect(makeSource('a', type: BookSourceType.video).getBookType(),
          BookType.video);
      expect(makeSource('a').getBookType(), BookType.text);

      expect(s.checkKeywordOf(), '我的');
      expect(
          BookSource(
            bookSourceUrl: 'u',
            bookSourceName: 'n',
            checkKeyWord: '斗破',
          ).checkKeywordOf(),
          '斗破');
      expect(
          BookSource(
            bookSourceUrl: 'u',
            bookSourceName: 'n',
            checkKeyWord: 'a.*b',
          ).checkKeywordOf('兜底'),
          '兜底');
    });
  });

  group('强类型规则类', () {
    test('fromJson 支持 Map 与 JSON 字符串，toJson 双向一致，get 类型化取值', () {
      final map = {
        'bookList': '@list',
        'name': '@name',
        'checkKeyWord': '我的',
        'author': '@author',
      };
      final fromMap = SearchRule.fromJson(map);
      final fromStr = SearchRule.fromJson(jsonEncode(map));
      expect(fromMap.bookList, '@list');
      expect(fromMap.name, '@name');
      expect(fromMap.checkKeyWord, '我的');
      expect(fromMap.get('author'), '@author');
      expect(fromMap.get('缺失'), '');
      expect(fromStr.bookList, '@list');
      expect(fromStr.checkKeyWord, '我的');

      final round = SearchRule.fromJson(fromMap.toJson());
      expect(round.bookList, '@list');
      expect(round.name, '@name');
      expect(round.checkKeyWord, '我的');
      expect(round.get('missing'), '');

      final ext = SearchRule.fromJson({...map, 'customKey': 'v'});
      expect(ext.get('customKey'), 'v');
      expect(ext.toJson()['customKey'], 'v');
    });

    test('各规则类字段默认值、get 与 toJson 完整', () {
      final bi = BookInfoRule.fromJson(
          {'name': 'n', 'tocUrl': 't', 'downloadUrls': 'd'});
      expect(bi.init, '');
      expect(bi.name, 'n');
      expect(bi.get('tocUrl'), 't');
      expect(bi.canReName, '');
      expect(bi.toJson()['downloadUrls'], 'd');

      final toc = TocRule.fromJson(
          {'chapterList': 'cl', 'nextTocUrl': 'n', 'isVip': 'vip'});
      expect(toc.chapterName, '');
      expect(toc.get('isVip'), 'vip');
      expect(toc.toJson()['chapterList'], 'cl');

      final content =
          ContentRule.fromJson('{"content":"c","webJs":"w","payAction":"p"}');
      expect(content.content, 'c');
      expect(content.get('payAction'), 'p');
      expect(content.callBackJs, '');

      final review =
          ReviewRule.fromJson({'reviewUrl': 'r', 'contentRule': 'cr'});
      expect(review.avatarRule, '');
      expect(review.get('contentRule'), 'cr');

      final bl = BookListRule.fromJson({'bookUrl': 'bu'});
      expect(bl.bookUrl, 'bu');
      expect(bl.wordCount, '');
      final er = ExploreRule.fromJson({'bookList': 'el'});
      expect(er.bookList, 'el');
    });

    test('BookSource.ruleXxxTyped 强类型视图，现有 Map getter 保持不变', () {
      final s = BookSource(
        bookSourceUrl: 'u',
        bookSourceName: 'n',
        ruleSearch: {'bookList': 'bl', 'name': 'n', 'checkKeyWord': 'k'},
        ruleExplore: {'bookList': 'ebl'},
        ruleBookInfo: {'tocUrl': 't'},
        ruleToc: {'chapterList': 'cl'},
        ruleContent: {'content': 'c'},
        ruleReview: {'reviewUrl': 'r'},
      );
      expect(s.ruleSearch, isA<Map<String, dynamic>>());
      expect(s.ruleSearch!['name'], 'n');
      expect(s.searchName, 'n');
      expect(s.ruleSearchTyped, isA<SearchRule>());
      expect(s.ruleSearchTyped!.bookList, 'bl');
      expect(s.ruleSearchTyped!.checkKeyWord, 'k');
      expect(s.ruleExploreTyped!.bookList, 'ebl');
      expect(s.ruleBookInfoTyped!.tocUrl, 't');
      expect(s.ruleTocTyped!.chapterList, 'cl');
      expect(s.ruleContentTyped!.content, 'c');
      expect(s.ruleReviewTyped!.reviewUrl, 'r');

      final empty = BookSource(bookSourceUrl: 'u', bookSourceName: 'n');
      expect(empty.ruleSearchTyped, isNull);
    });
  });

  group('控件与分类解析', () {
    test('RowUi 兼容 toggle / switch 与 chars / options', () {
      final toggle =
          RowUi.fromJson({'name': '记住', 'type': 'switch', 'default': 'true'});
      expect(toggle.type, RowUi.typeToggle);
      expect(toggle.isToggle, isTrue);
      expect(toggle.defaultValue, 'true');

      final sel1 = RowUi.fromJson({
        'name': '排序',
        'type': 'select',
        'chars': ['默认', '最新', '最热'],
      });
      expect(sel1.chars, ['默认', '最新', '最热']);
      expect(sel1.isSelect, isTrue);
      final sel2 = RowUi.fromJson({
        'name': '排序',
        'type': 'select',
        'options': ['A', 'B'],
      });
      expect(sel2.chars, ['A', 'B']);
      expect(sel2.toJson()['chars'], ['A', 'B']);
      expect(RowUi.fromJson({'options': '甲,乙，丙'}).chars, ['甲', '乙', '丙']);
      expect(RowUi.fromJson({'name': '用户名'}).type, RowUi.typeText);
    });

    test('FlexChildStyle 六字段 / alignSelf 映射 / defaultStyle', () {
      final st = FlexChildStyle.fromJson({
        'layout_flexGrow': 1,
        'layout_flexShrink': 0,
        'layout_alignSelf': 'flex-start',
        'layout_flexBasisPercent': 0.45,
        'layout_wrapBefore': true,
        'layout_justifySelf': 'center',
      });
      expect(st.layoutFlexGrow, 1.0);
      expect(st.layoutFlexShrink, 0.0);
      expect(st.layoutFlexBasisPercent, 0.45);
      expect(st.layoutWrapBefore, isTrue);
      expect(st.alignSelf(), 'flex_start');
      expect(st.toJson()['layout_flexGrow'], 1.0);
      expect(st.toJson()['layout_alignSelf'], 'flex-start');
      expect(FlexChildStyle.defaultStyle.alignSelf(), 'auto');
      expect(FlexChildStyle.fromJson({'layout_alignSelf': 'END'}).alignSelf(),
          'flex_end');
      expect(
          FlexChildStyle.fromJson({'layout_alignSelf': 'stretch'}).alignSelf(),
          'stretch');
    });

    test('ExploreKind 兼容 switch 控件类型与 options 选项来源', () {
      final k = ExploreKind.fromJson({
        'title': '开关',
        'type': 'switch',
        'options': ['开', '关']
      });
      expect(k.type, ExploreKind.typeToggle);
      expect(k.chars, ['开', '关']);
      expect(k.isControl, isTrue);
      final url = ExploreKind.fromJson({
        'title': '分类',
        'type': 'url',
        'chars': ['A']
      });
      expect(url.isUrl, isTrue);
      expect(url.chars, ['A']);
    });
  });

  group('常量与工具', () {
    test('AppConst 常量、设备标识、分组拆分与内容哈希缓存键', () {
      expect(AppConst.UA_NAME, 'User-Agent');
      expect(AppConst.MAX_THREAD, greaterThan(0));
      expect(AppConst.charsets, contains('UTF-8'));
      expect(AppConst.charsets, contains('GBK'));
      final id = AppConst.androidId();
      expect(id.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id), isTrue);
      expect(
        AppConst.splitGroups('玄幻,都市；仙侠、科幻 abc；历史'),
        ['玄幻', '都市', '仙侠', '科幻', 'abc', '历史'],
      );
      final groups = ['小说', 'abc', 'ABC', '玄幻']..sort(AppConst.compareGroups);
      expect(groups.first, anyOf('abc', 'ABC'));

      final keyA = AppConst.exploreKindsCacheKey('u', 'ruleA');
      final keyB = AppConst.exploreKindsCacheKey('u', 'ruleB');
      expect(keyA, isNot(keyB));
      expect(keyA, contains('u'));
    });

    test('SourceType 常量 book=0 / rss=1', () {
      expect(SourceType.book, 0);
      expect(SourceType.rss, 1);
      expect(SourceHelp.sourceTypeBook, SourceType.book);
      expect(SourceHelp.sourceTypeRss, SourceType.rss);
    });
  });

  group('数据库能力', () {
    late Database db;
    late DatabaseService service;
    late SourceHelp help;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await databaseFactory.openDatabase(':memory:');
      await DatabaseService.createTablesForTest(db);
      DatabaseService.overrideDatabaseForTest(db);
      service = DatabaseService();
      help = SourceHelp(db: service);
      addTearDown(() => db.close());
    });

    test('getAllParts 投影查询与计算列、toBookSource 还原', () async {
      await service.insertSource(makeSource(
        'https://a.com/x',
        name: '甲',
        group: '玄幻',
        customOrder: 3,
        loginUrl: 'https://a.com/login',
        exploreUrl: 'https://a.com/explore',
      ));
      await service.insertSource(makeSource('https://b.com/y', name: '乙'));
      final parts = await service.getAllParts();
      expect(parts.length, 2);
      expect(parts.first, isA<BookSourcePart>());
      final a = parts.firstWhere((p) => p.bookSourceUrl == 'https://a.com/x');
      expect(a.bookSourceName, '甲');
      expect(a.bookSourceGroup, '玄幻');
      expect(a.hasLoginUrl, isTrue);
      expect(a.hasExploreUrl, isTrue);
      final b = parts.firstWhere((p) => p.bookSourceUrl == 'https://b.com/y');
      expect(b.hasLoginUrl, isFalse);
      expect(b.hasExploreUrl, isFalse);
      final restored = a.toBookSource();
      expect(restored.bookSourceUrl, 'https://a.com/x');
      expect(restored.loginUrl, 'https://a.com/login');
      expect(restored.exploreUrl, 'https://a.com/explore');
    });

    test('searchSources 对 name / group / url / comment 四字段模糊匹配', () async {
      await service.insertSource(makeSource('https://a.com/x',
          name: '起点中文', group: '玄幻', comment: '精品'));
      await service
          .insertSource(makeSource('https://b.com/y', name: '纵横', group: '都市'));
      expect((await service.searchSources('起点')).length, 1);
      expect((await service.searchSources('玄幻')).length, 1);
      expect((await service.searchSources('a.com')).length, 1);
      expect((await service.searchSources('精品')).length, 1);
      expect(await service.searchSources('无匹配'), isEmpty);
    });

    test('分组 / 类型 / 无分组 / URL 模式 查询', () async {
      await service.insertSource(makeSource('u1', group: '玄幻,都市'));
      await service.insertSource(makeSource('u2', group: '玄幻', type: 1));
      await service.insertSource(makeSource('u3', group: '玄幻', enabled: false));
      await service.insertSource(
          makeSource('u4', bookUrlPattern: r'https://x.com/book/\d+'));
      await service
          .insertSource(makeSource('u5', group: '其它', bookUrlPattern: 'NONE'));
      await service.insertSource(makeSource('u6', group: '其它'));

      expect(
        (await service.getByGroup('玄幻')).map((s) => s.bookSourceUrl).toSet(),
        {'u1', 'u2', 'u3'},
      );
      expect(
        (await service.getEnabledByGroup('玄幻'))
            .map((s) => s.bookSourceUrl)
            .toSet(),
        {'u1', 'u2'},
      );
      expect((await service.getEnabledByType(1)).map((s) => s.bookSourceUrl),
          ['u2']);
      expect((await service.noGroup()).map((s) => s.bookSourceUrl), ['u4']);

      final patterns = await service.getByBookUrlPattern();
      expect(patterns.map((s) => s.bookSourceUrl), ['u4']);
      expect(
        (await service.getByBookUrlPattern('https://x.com/book/123'))
            .map((s) => s.bookSourceUrl),
        ['u4'],
      );
      expect(await service.getByBookUrlPattern('https://other.com/1'), isEmpty);
    });

    test('allCount / has / minOrder / maxOrder / hasDuplicateOrder', () async {
      await service.insertSource(makeSource('u1', customOrder: 5));
      await service.insertSource(makeSource('u2', customOrder: 5));
      await service.insertSource(makeSource('u3', customOrder: 9));
      expect(await service.allCount(), 3);
      expect(await service.has('u1'), isTrue);
      expect(await service.has('nope'), isFalse);
      expect(await service.minOrder(), 5);
      expect(await service.maxOrder(), 9);
      expect(await service.hasDuplicateOrder(), isTrue);
      await service.upOrder('u2', 7);
      expect(await service.hasDuplicateOrder(), isFalse);
      expect(await service.minOrder(), 5);
      expect(await service.maxOrder(), 9);
    });

    test('enable / enableExplore 单列更新与 enableSources 批量事务', () async {
      for (final u in const ['u1', 'u2', 'u3']) {
        await service.insertSource(makeSource(u));
      }
      await service.enable('u1', false);
      await service.enableExplore('u2', false);
      expect((await service.getSource('u1'))!.enabled, isFalse);
      expect((await service.getSource('u1'))!.enabledExplore, isTrue);
      expect((await service.getSource('u2'))!.enabledExplore, isFalse);

      await service.enableSources(['u1', 'u2', 'u3'], false);
      expect((await service.getAllSources()).every((s) => !s.enabled), isTrue);
      await service.enableExploreSources(['u1', 'u2', 'u3'], false);
      expect((await service.getAllSources()).every((s) => !s.enabledExplore),
          isTrue);

      await service.upGroup('u1', '新分组');
      expect((await service.getSource('u1'))!.bookSourceGroup, '新分组');
    });

    test('dealGroups 中文排序、分隔符覆盖与规范化写回；allGroups', () async {
      await service.insertSource(makeSource('u1', group: '玄幻,都市；仙侠、科幻 abc'));
      await service.insertSource(makeSource('u2', group: '玄幻，历史'));
      expect(
        (await service.allGroups()).toSet(),
        {'玄幻', '都市', '仙侠', '科幻', 'abc', '历史'},
      );
      final sorted = await service.dealGroups();
      expect(sorted.first, 'abc');
      expect(sorted.length, 6);

      final u1 = (await service.getSource('u1'))!;
      expect(u1.bookSourceGroup, isNot(contains('；')));
      expect(u1.bookSourceGroup, isNot(contains('、')));
      final parts = AppConst.splitGroups(u1.bookSourceGroup);
      expect(parts.toSet(), {'玄幻', '都市', '仙侠', '科幻', 'abc'});
      expect(parts, parts.toList()..sort(AppConst.compareGroups));
    });

    test('SourceHelp getSource / getSourceType / enableSource', () async {
      await service.insertSource(makeSource('https://book.com/x', name: '书源'));
      await db.insert('rss_sources',
          {'url': 'https://rss.com/feed', 'name': '订阅', 'enabled': 1});

      expect(await help.getSource('https://book.com/x'), isA<BookSource>());
      expect(await help.getSource('https://rss.com/feed'), isA<RssSource>());
      expect(await help.getSource('nope'), isNull);
      expect(await help.getSourceType('https://book.com/x'), SourceType.book);
      expect(await help.getSourceType('https://rss.com/feed'), SourceType.rss);
      expect(await help.getSourceType('nope'), -1);

      await help.enableSource('https://book.com/x', false);
      expect((await service.getSource('https://book.com/x'))!.enabled, isFalse);
      await help.enableSource('https://rss.com/feed', false);
      final rows = await db.query('rss_sources',
          where: 'url = ?', whereArgs: ['https://rss.com/feed']);
      expect(rows.first['enabled'], 0);
    });

    test('SourceHelp deleteSource 级联清理变量、检查状态与相关文章', () async {
      const key = 'https://book.com/x';
      await service.insertSource(makeSource(key));
      await db.insert('book_source_check_states', {'origin': key, 'state': 1});
      await db.insert('rss_articles', {'sourceUrl': key, 'title': 'a'});
      await db.insert('rss_stars', {'sourceUrl': key, 'title': 's'});
      await db
          .insert('kv_caches', {'key': 'sourceVariable_$key', 'value': 'v'});
      await db.insert('rss_articles', {'sourceUrl': 'other', 'title': 'keep'});

      await help.deleteSource(key);
      expect(await service.has(key), isFalse);
      expect(
        await db.query('book_source_check_states',
            where: 'origin = ?', whereArgs: [key]),
        isEmpty,
      );
      expect(
        await db
            .query('rss_articles', where: 'sourceUrl = ?', whereArgs: [key]),
        isEmpty,
      );
      expect(
        await db.query('rss_stars', where: 'sourceUrl = ?', whereArgs: [key]),
        isEmpty,
      );
      expect(
        await db.query('kv_caches',
            where: 'key = ?', whereArgs: ['sourceVariable_$key']),
        isEmpty,
      );
      expect(
        await db.query('rss_articles',
            where: 'sourceUrl = ?', whereArgs: ['other']),
        isNotEmpty,
      );
    });

    test('SourceHelp insertBookSource 整理来源基数排序号', () async {
      await help.insertBookSource(makeSource('https://a.com/1'));
      await help.insertBookSource(makeSource('https://a.com/2'));
      await help.insertBookSource(makeSource('https://b.com/1'));
      final all = await service.getAllSources();
      final a = all
          .where((s) => s.bookSourceUrl.startsWith('https://a.com/'))
          .toList()
        ..sort((x, y) => x.customOrder.compareTo(y.customOrder));
      final b = all
          .where((s) => s.bookSourceUrl.startsWith('https://b.com/'))
          .toList();
      expect(a.length, 2);
      expect(a[1].customOrder - a[0].customOrder, 1);
      expect(b.single.customOrder,
          greaterThanOrEqualTo(SourceHelp.sortNumberBase));
    });

    test('checkKeywordOf 静态兼容包装与实例方法一致', () {
      final s = BookSource(
        bookSourceUrl: 'u',
        bookSourceName: 'n',
        ruleSearch: {'checkKeyWord': '我的'},
      );
      expect(s.checkKeywordOf(), '我的');
      expect(CheckSourceConfig.checkKeywordOf(s), '我的');
      final bad = BookSource(
        bookSourceUrl: 'u',
        bookSourceName: 'n',
        checkKeyWord: 'a.*b',
      );
      expect(CheckSourceConfig.checkKeywordOf(bad), CheckSourceConfig.keyword);
    });
  });
}
