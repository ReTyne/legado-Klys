import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/explore_refresh.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/parts/engine_primitives.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/source_extensions.dart';
import 'package:legado_md3/help/source/ttf_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 书源引擎主链路与字体反爬能力的真实行为验证。
/// 直接调用可执行的 Dart 实现与公开方法，断言具体结果。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 测试环境固定使用迷你求值器，避免桌面端 WebView 初始化等待
    JsRuntimeManager.instance.factoryOverride = (_) => MiniLegadoJs();
  });

  BookSource makeSource(String url, {Map<String, dynamic>? extra}) =>
      BookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': url,
        'bookSourceName': '测试源',
        ...?extra,
      });

  // ==================== 302 后相对地址基准 ====================
  group('最终 URL 作为相对地址基准', () {
    test('设置 redirectUrl 后相对链接解析到重定向域名', () {
      final engine = BookSourceEngine();
      engine.setRedirectUrl('https://cdn.example.com/book/');
      expect(
        engine.resolveEditUrl('chap1.html', 'https://origin.example.com/'),
        'https://cdn.example.com/book/chap1.html',
      );
      expect(engine.redirectUrl, 'https://cdn.example.com/book/');
    });

    test('根相对与协议相对地址的解析', () {
      final engine = BookSourceEngine();
      engine.setRedirectUrl('https://cdn.example.com/dir/index.html');
      expect(engine.resolveEditUrl('/abs/page', 'https://origin.example.com/'),
          'https://cdn.example.com/abs/page');
      engine.setRedirectUrl(null);
      expect(
          engine.resolveEditUrl('next.html', 'https://origin.example.com/a/'),
          'https://origin.example.com/a/next.html');
      expect(resolveUrlBase('//other.example.com/x', 'https://a.example.com/'),
          'https://other.example.com/x');
    });

    test('resolveWithRedirect 在无重定向时回退 baseUrl', () {
      expect(resolveWithRedirect('p.html', 'https://a.example.com/d/', null),
          'https://a.example.com/d/p.html');
      expect(
          resolveWithRedirect(
              'p.html', 'https://a.example.com/d/', 'https://b.example.com/e/'),
          'https://b.example.com/e/p.html');
      expect(resolveUrlBase('data:text/plain,abc', 'https://a.example.com/'),
          'data:text/plain,abc');
    });
  });

  // ==================== 请求方法 / 选项 ====================
  group('请求方法与 URL 选项', () {
    test('HEAD 等请求方法规范化', () {
      expect(normalizeMethod('HEAD'), 'HEAD');
      expect(normalizeMethod('head'), 'HEAD');
      expect(normalizeMethod('get'), 'GET');
      expect(normalizeMethod('unknown'), 'GET');
      expect(kSupportedMethods.contains('HEAD'), isTrue);
      expect(isBodylessMethod('HEAD'), isTrue);
      expect(isBodylessMethod('POST'), isFalse);
    });

    test('webView 与 bodyjs 选项大小写兼容', () {
      expect(optFlag(<String, dynamic>{'webView': true}, 'webview'), isTrue);
      expect(optFlag(<String, dynamic>{'webview': 'true'}, 'webView'), isTrue);
      expect(optFlag(<String, dynamic>{'webView': false}, 'webview'), isFalse);
      expect(optCI(<String, dynamic>{'BODYJS': 'x=1'}, 'bodyJs'), 'x=1');
      expect(
          optFlag(<String, dynamic>{'WEBVIEWDELAYTIME': '300'}, 'x'), isFalse);
    });

    test('type 与 Content-Type 语义分离', () {
      expect(responseHexType(<String, dynamic>{'type': 'hex'}), 'hex');
      expect(
          requestContentType(
              <String, dynamic>{'type': 'form'}, <String, dynamic>{}),
          isNull);
      expect(
          requestContentType(
              <String, dynamic>{'contentType': 'application/json'},
              <String, dynamic>{}),
          'application/json');
      expect(
          requestContentType(<String, dynamic>{'contentType': 'text/plain'},
              <String, dynamic>{'Content-Type': 'image/png'}),
          'image/png');
    });
  });

  // ==================== 请求参数编码 ====================
  group('charset 编码', () {
    test('charset=escape 采用 JS escape 语义', () {
      expect(escapeParam('中文'), '%u4E2D%u6587');
      expect(escapeParam('a b&'), 'a%20b%26');
      expect(encodeParams('q=中文', 'escape'), 'q=%u4E2D%u6587');
      expect(encodeParams('a=1&b=中文', 'escape'), 'a=1&b=%u4E2D%u6587');
    });

    test('已编码参数不重复编码', () {
      expect(isPercentEncoded('%E4%B8%AD'), isTrue);
      expect(isPercentEncoded('%u4E2D'), isTrue);
      expect(isPercentEncoded('中文'), isFalse);
      expect(encodeParams('q=%E4%B8%AD', 'utf-8'), 'q=%E4%B8%AD');
      expect(encodeParams('q=%u4E2D', 'escape'), 'q=%u4E2D');
      expect(encodeParams('a=1&b=中文', 'utf-8'), 'a=1&b=%E4%B8%AD%E6%96%87');
    });

    test('escape 处理增补平面字符', () {
      expect(escapeParam('😀'), '%uD83D%uDE00');
    });
  });

  // ==================== 请求头清洗 ====================
  group('请求头清洗', () {
    test('<js> / @js: 动态请求头被抽出', () {
      expect(headerScriptOf('<js>1+1</js>'), '1+1');
      expect(headerScriptOf('@js: token()'), ' token()');
      final plan = planHeaders(<String, dynamic>{
        'X-Token': '<js>abc()</js>',
        'X-Plain': 'v',
      });
      expect(plan.jsHeaders.map((e) => e.key), contains('X-Token'));
      expect(plan.headers.containsKey('X-Token'), isFalse);
      expect(plan.headers['X-Plain'], 'v');
    });

    test('"null" UA 删除语义', () {
      final plan = planHeaders(<String, dynamic>{'User-Agent': 'null'});
      expect(plan.nullUaRemoved, isTrue);
      expect(plan.headers.containsKey('User-Agent'), isFalse);
      final kept = planHeaders(<String, dynamic>{'User-Agent': 'Mozilla'});
      expect(kept.nullUaRemoved, isFalse);
      expect(kept.headers['User-Agent'], 'Mozilla');
    });

    test('proxy 头剥离为代理配置', () {
      final plan = planHeaders(<String, dynamic>{
        'proxy': 'http://127.0.0.1:8080',
        'X-Key': '1',
      });
      expect(plan.proxy, 'http://127.0.0.1:8080');
      expect(plan.headers.containsKey('proxy'), isFalse);
      expect(plan.headers['X-Key'], '1');
      expect(plan.notes.any((n) => n.contains('proxy')), isTrue);
    });
  });

  // ==================== 变量跨步骤 / 桥接 ====================
  group('变量体系统一', () {
    test('同一书源跨步骤变量不被清空', () async {
      final engine = BookSourceEngine();
      final source = makeSource('https://v.example.com');
      await engine.exploreKinds(source); // 建立会话
      await engine.putVariable(source, 'token', 'abc123');
      await engine.exploreKinds(source); // 同书源再次进入
      expect(await engine.getVariable(source, 'token'), 'abc123');
      expect(engine.sessionVariables['token'], 'abc123');
    });

    test('登录信息与 java.put/get 变量桥接到变量表', () async {
      const url = 'https://bridge.example.com';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'loginInfo_$url': 'LOGIN_TOKEN',
        'jsKv_$url': '{"uid":"42"}',
      });
      final engine = BookSourceEngine();
      final source = makeSource(url);
      await engine.exploreKinds(source);
      expect(await engine.getVariable(source, 'loginInfo'), 'LOGIN_TOKEN');
      expect(await engine.getVariable(source, 'uid'), '42');
    });
  });

  // ==================== 探索分类 ====================
  group('探索分类全字段与缓存', () {
    test('旧文本分支补齐全字段', () {
      final kinds = parseExploreKindsFull('玄幻::http://a.example.com/x');
      expect(kinds, hasLength(1));
      final k = kinds.first;
      expect(k['title'], '玄幻');
      expect(k['url'], 'http://a.example.com/x');
      for (final key in <String>[
        'type',
        'action',
        'chars',
        'default',
        'viewName',
        'style'
      ]) {
        expect(k.containsKey(key), isTrue, reason: '缺少字段 $key');
      }
      expect(k['type'], 'url');
    });

    test('JSON 数组分支保留全字段', () {
      final kinds = parseExploreKindsFull(jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'title': '排行',
          'url': 'http://a.example.com/r',
          'type': 'button',
          'action': 'go()',
          'chars': <String>['日', '周'],
          'default': '日',
          'viewName': '切换',
          'style': <String, dynamic>{'layout_flexGrow': 1},
        }
      ]));
      final k = kinds.first;
      expect(k['type'], 'button');
      expect(k['action'], 'go()');
      expect(k['chars'], '日,周');
      expect(k['default'], '日');
      expect(k['viewName'], '切换');
      expect(jsonDecode(k['style']!)['layout_flexGrow'], 1);
    });

    test('缓存 key 含 exploreUrl 内容哈希，配置变更即失效', () {
      const url = 'https://e.example.com';
      final k1 = exploreKindsCacheKey(url, '分类A::u1');
      final k2 = exploreKindsCacheKey(url, '分类B::u2');
      expect(k1, isNot(k2));
      expect(k1, exploreKindsCacheKey(url, '分类A::u1'));
      expect(contentHash('abc'), contentHash('abc'));
      expect(contentHash('abc'), isNot(contentHash('abd')));
    });

    test('getExploreKinds 与 exploreKindsJson 输出全字段', () async {
      final engine = BookSourceEngine();
      final source = makeSource('https://j.example.com',
          extra: <String, dynamic>{'exploreUrl': '分类::http://j.example.com/c'});
      final kinds = engine.getExploreKinds(source);
      expect(kinds.first.containsKey('style'), isTrue);
      final json = await engine.exploreKindsJson(source);
      final decoded = jsonDecode(json) as List;
      expect(decoded, isNotEmpty);
      expect((decoded.first as Map)['type'], 'url');
    });

    test('clearExploreKindsCache 清除该书源所有历史哈希键', () async {
      const url = 'https://c.example.com';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'exploreKinds_$url': 'old',
        exploreKindsCacheKey(url, 'A'): 'a',
        exploreKindsCacheKey(url, 'B'): 'b',
      });
      final engine = BookSourceEngine();
      await engine.clearExploreKindsCache(makeSource(url));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('exploreKinds_$url')),
          isEmpty);
    });
  });

  // ==================== 横切登录检测 ====================
  group('loginCheckJs 重新登录信号', () {
    test('求值结果含标记时判定需重新登录', () {
      final out = evaluateLoginCheckPure('result', 'body', kReloginMarker);
      expect(out.needRelogin, isTrue);
      expect(out.evaluated, isTrue);
      expect(loginCheckNeedsRelogin('false'), isTrue);
      expect(loginCheckNeedsRelogin('0'), isTrue);
      expect(loginCheckNeedsRelogin('true'), isFalse);
    });

    test('公开 evaluateLoginCheck 触发重新登录信号', () async {
      final engine = BookSourceEngine();
      final source = makeSource('https://login.example.com',
          extra: <String, dynamic>{'loginCheckJs': 'result'});
      final before = reloginSignal.value;
      final out = await engine.evaluateLoginCheck(
          source, '页面内容 $kReloginMarker 需要重新登录');
      expect(out.needRelogin, isTrue);
      expect(reloginSignal.value, isNot(before));
      expect(reloginSourceOf(reloginSignal.value), 'https://login.example.com');
    });
  });

  // ==================== 去重 / 分页上限 ====================
  group('去重与分页上限', () {
    test('搜索结果按 bookUrl 去重可开关', () {
      final books = <Map<String, String>>[
        <String, String>{'bookUrl': 'u1', 'name': 'A'},
        <String, String>{'bookUrl': 'u1', 'name': 'A2'},
        <String, String>{'bookUrl': 'u2', 'name': 'B'},
      ];
      expect(dedupSearchBooks(books), hasLength(2));
      expect(dedupSearchBooks(books, enabled: false), hasLength(3));
    });

    test('目录按 URL 去重且分页上限默认 100', () {
      expect(kDefaultTocPageLimit, 100);
      expect(kDefaultContentPageLimit, 100);
      expect(clampPageLimit(null), 100);
      expect(clampPageLimit(500), 100);
      expect(clampPageLimit(7), 7);
      final items = <String>['u1', 'u2', 'u1', 'u3'];
      expect(dedupByUrl<String>(items, (e) => e), <String>['u1', 'u2', 'u3']);
    });

    test('正文分页重复内容检测', () {
      expect(isDuplicateContent('第一章正文', '第一章正文'), isTrue);
      expect(isDuplicateContent('第一章正文', '第二章正文'), isFalse);
      expect(isDuplicateContent('任意', '  '), isTrue);
    });
  });

  // ==================== imageStyle / payAction ====================
  group('正文呈现选项', () {
    test('imageStyle 支持 full/center/default/尺寸语义', () {
      expect(parseImageStyle('full').keepImage, isTrue);
      final center = parseImageStyle('center');
      expect(center.keepImage, isTrue);
      expect(center.imageCss, contains('margin'));
      expect(parseImageStyle('default').imageCss, contains('max-width'));
      final size = parseImageStyle('100x200');
      expect(size.imageCss, contains('width:100px'));
      expect(size.imageCss, contains('height:200px'));
      expect(parseImageStyle('none').keepImage, isFalse);
    });

    test('payAction 含 {{js}} 时取脚本并产出购买提示', () {
      expect(payActionNeedsJs('请购买 {{js=buy()}}'), isTrue);
      expect(payActionNeedsJs('请购买'), isFalse);
      expect(payActionScript('请购买 {{js=1+1}}'), '1+1');
      expect(payActionScript('<js>buy()</js>'), 'buy()');
      final hint = buildPurchaseHint('本章需购买 {{js=x}}', '请付费后阅读');
      expect(hint, contains('本章需购买'));
      expect(hint, contains('请付费后阅读'));
      expect(buildPurchaseHint('', ''), '本章需要购买后阅读');
    });
  });

  // ==================== JS 注入变量 ====================
  group('JS 注入变量', () {
    test('buildJsVarPrelude 绑定额外全局量', () {
      final prelude = buildJsVarPrelude(
          src: '<html>',
          title: '第一章',
          nextChapterUrl: 'u2',
          fromBookInfo: true,
          speakText: '朗读',
          speakSpeed: 2,
          content: '正文');
      expect(prelude, contains('globalThis.title'));
      expect(prelude, contains('globalThis.content'));
      expect(prelude, contains('globalThis.speakSpeed = 2'));
      expect(prelude, contains('globalThis.fromBookInfo = true'));
      expect(prelude, contains(r'\u003C'), reason: '尖括号应转义');
      expect(buildJsVarPrelude(), isEmpty);
    });

    test('preUpdateJs 注入 reGetBook/refreshTocUrl 等价能力', () {
      final prelude = buildPreUpdateJsPrelude();
      expect(prelude, contains('reGetBook'));
      expect(prelude, contains('refreshTocUrl'));
      expect(preUpdateRequestsReGetBook(kReGetBookMarker), isTrue);
      expect(preUpdateRequestsReGetBook('普通结果'), isFalse);
    });
  });

  // ==================== 书源扩展方法 ====================
  group('书源扩展方法', () {
    test('类型位标志 / 缓存键 / 关键词 / 分组', () {
      final audio = makeSource('https://a.example.com',
          extra: <String, dynamic>{'bookSourceType': 1});
      expect(audio.extGetBookType(), kBookTypeAudio);
      final image = makeSource('https://i.example.com',
          extra: <String, dynamic>{'bookSourceType': 2});
      expect(image.extGetBookType(), kBookTypeImage);
      final s = makeSource('https://g.example.com', extra: <String, dynamic>{
        'bookSourceGroup': '01_玄幻,精选',
        'checkKeyWord': '斗破',
        'exploreUrl': '分类::u',
      });
      expect(s.extGetSourceType(), 0);
      expect(s.extGetCheckKeyword(), '斗破');
      expect(s.extHasGroup('精选'), isTrue);
      expect(s.extHasGroup('不存在'), isFalse);
      expect(s.extGetDisplayNameGroup(), '玄幻');
      expect(s.extGetExploreKindsKey(),
          exploreKindsCacheKey(s.bookSourceUrl, '分类::u'));
    });
  });

  // ==================== TTF 字体轮廓 ====================
  group('TTF 字形轮廓与 cmap', () {
    final ttf = _assembleTtf(<String, List<int>>{
      'cmap': _cmap(<(int, int, List<int>)>[
        (3, 1, _format6(0x4E00, <int>[1, 2])),
        (1, 0, _format0()),
      ]),
      'maxp': _maxp(3),
      'loca': _loca(<int>[0, 0, 12, 20]),
      'glyf': _glyf(),
    });

    test('glyf 简单/复合字形轮廓指纹', () {
      final parser = TtfParser.fromBytes(ttf);
      expect(parser.glyfFingerprint(1), 'S:1;0,0;10,10');
      expect(parser.glyfFingerprint(2), 'C|gid=1,a=0,0');
      expect(parser.glyfFingerprint(0), isNull); // 空字形
      expect(parser.glyfFingerprint(99), isNull); // 越界
    });

    test('cmap format 6 连续映射', () {
      final parser = TtfParser.fromBytes(ttf);
      final cmap = parser.parseCmap();
      expect(cmap[0x4E00], 1);
      expect(cmap[0x4E01], 2);
    });

    test('cmap format 0 字节编码表', () {
      final format0Only = _assembleTtf(<String, List<int>>{
        'cmap': _cmap(<(int, int, List<int>)>[(1, 0, _format0())]),
      });
      final cmap = TtfParser.fromBytes(format0Only).parseCmap();
      expect(cmap[65], 1);
      expect(cmap[66], 2);
      expect(cmap[0], isNull);
    });

    test('多平台子表优先级：高优先级先写不被覆盖', () {
      final prioritized = _assembleTtf(<String, List<int>>{
        'cmap': _cmap(<(int, int, List<int>)>[
          (1, 0, _format6(0x41, <int>[9])),
          (3, 1, _format6(0x41, <int>[5])),
        ]),
      });
      expect(TtfParser.fromBytes(prioritized).parseCmap()[0x41], 5);
    });

    test('buildQueryData 无参行为不变，withOutline 使用轮廓指纹', () {
      final parser = TtfParser.fromBytes(ttf);
      final base = parser.buildQueryData();
      final outline = parser.buildQueryData(withOutline: true);
      expect(base['unicodeToGlyphId']['19968'], '1');
      expect(base['unicodeToGlyph']['19968'], 'glyf_1');
      expect(outline['unicodeToGlyph']['19968'], 'S:1;0,0;10,10');
      expect(outline['glyphToUnicode']['S:1;0,0;10,10'], '19968');
      expect(base['replacement'], isA<Map>());
    });

    test('非法字体数据安全降级', () {
      final parser = TtfParser.fromBytes(const <int>[0, 1, 2, 3]);
      expect(parser.parseCmap(), isEmpty);
      expect(parser.glyfFingerprint(1), isNull);
      expect(parser.buildQueryData(withOutline: true)['unicodeToGlyph'],
          isA<Map>());
    });
  });
}

// ==================== 最小 TTF 字节构造 ====================

List<int> _assembleTtf(Map<String, List<int>> tables) {
  final tags = tables.keys.toList()..sort();
  final headerSize = 12 + tags.length * 16;
  var offset = headerSize;
  final locations = <String, (int, int)>{};
  for (final tag in tags) {
    final pad = (4 - (offset % 4)) % 4;
    offset += pad;
    locations[tag] = (offset, tables[tag]!.length);
    offset += tables[tag]!.length;
  }
  final d = ByteData(offset);
  d.setUint32(0, 0x00010000);
  d.setUint16(4, tags.length);
  d.setUint16(6, 0);
  d.setUint16(8, 0);
  d.setUint16(10, 0);
  var rec = 12;
  for (final tag in tags) {
    for (var i = 0; i < 4; i++) {
      d.setUint8(rec + i, tag.codeUnitAt(i));
    }
    d.setUint32(rec + 8, locations[tag]!.$1);
    d.setUint32(rec + 12, locations[tag]!.$2);
    rec += 16;
    final (off, len) = locations[tag]!;
    final data = tables[tag]!;
    for (var i = 0; i < len; i++) {
      d.setUint8(off + i, data[i]);
    }
  }
  return d.buffer.asUint8List();
}

List<int> _cmap(List<(int, int, List<int>)> subs) {
  final headerLen = 4 + subs.length * 8;
  var total = headerLen;
  for (final s in subs) {
    total += s.$3.length;
  }
  final d = ByteData(total);
  d.setUint16(0, 0);
  d.setUint16(2, subs.length);
  var subOff = headerLen;
  for (var i = 0; i < subs.length; i++) {
    final rec = 4 + i * 8;
    d.setUint16(rec, subs[i].$1);
    d.setUint16(rec + 2, subs[i].$2);
    d.setUint32(rec + 4, subOff);
    final data = subs[i].$3;
    for (var j = 0; j < data.length; j++) {
      d.setUint8(subOff + j, data[j]);
    }
    subOff += data.length;
  }
  return d.buffer.asUint8List();
}

List<int> _format6(int firstCode, List<int> gids) {
  final d = ByteData(10 + gids.length * 2);
  d.setUint16(0, 6);
  d.setUint16(2, 10 + gids.length * 2);
  d.setUint16(4, 0);
  d.setUint16(6, firstCode);
  d.setUint16(8, gids.length);
  for (var i = 0; i < gids.length; i++) {
    d.setUint16(10 + i * 2, gids[i]);
  }
  return d.buffer.asUint8List();
}

List<int> _format0() {
  final d = ByteData(6 + 256);
  d.setUint16(0, 0);
  d.setUint16(2, 262);
  d.setUint16(4, 0);
  d.setUint8(6 + 65, 1);
  d.setUint8(6 + 66, 2);
  return d.buffer.asUint8List();
}

List<int> _maxp(int numGlyphs) {
  final d = ByteData(6);
  d.setUint32(0, 0x00010000);
  d.setUint16(4, numGlyphs);
  return d.buffer.asUint8List();
}

/// short 格式 loca：每项为「字节偏移 / 2」。
List<int> _loca(List<int> halves) {
  final d = ByteData(halves.length * 2);
  for (var i = 0; i < halves.length; i++) {
    d.setUint16(i * 2, halves[i]);
  }
  return d.buffer.asUint8List();
}

/// glyph1：简单字形（1 轮廓 2 点）；glyph2：复合字形（引用 glyph1）。
List<int> _glyf() {
  final d = ByteData(40);
  var o = 0;
  d.setInt16(o, 1);
  o += 2; // numberOfContours
  for (var i = 0; i < 4; i++) {
    d.setInt16(o, 0);
    o += 2; // bbox
  }
  d.setUint16(o, 1);
  o += 2; // endPts[0]
  d.setUint16(o, 0);
  o += 2; // instructionLength
  d.setUint8(o, 0x01);
  o += 1; // flag point0
  d.setUint8(o, 0x01);
  o += 1; // flag point1
  d.setInt16(o, 0);
  o += 2; // x0
  d.setInt16(o, 10);
  o += 2; // x1
  d.setInt16(o, 0);
  o += 2; // y0
  d.setInt16(o, 10);
  o += 2; // y1
  // 复合字形
  d.setInt16(o, -1);
  o += 2; // numberOfContours = -1
  for (var i = 0; i < 4; i++) {
    d.setInt16(o, 0);
    o += 2; // bbox
  }
  d.setUint16(o, 0x0002);
  o += 2; // flags
  d.setUint16(o, 1);
  o += 2; // glyphIndex
  d.setInt8(o, 0);
  o += 1; // arg1
  d.setInt8(o, 0);
  o += 1; // arg2
  return d.buffer.asUint8List();
}
