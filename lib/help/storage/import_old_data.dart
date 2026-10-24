import 'dart:convert';
import 'dart:io';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/replace_rule.dart';

/// 旧版（legado 3.x / 阅读旧格式）数据迁移（E: help/storage/ImportOldData.kt）。
///
/// 读取旧版导出的三个文件并转换为当前模型：
/// * `myBookShelf.json`   旧书架（`noteUrl`/`bookInfoBean.*` 字段）
/// * `myBookSource.json`  旧书源（`ruleSearchUrl` 等旧字段名 + 旧规则语法）
/// * `myBookReplaceRule.json` 旧替换规则
///
/// 规则语法转换（E 的 toNewRule/toNewUrl）：
/// * `#正则#替换` → `##正则##替换`；`|` → `||`；`&` → `&&`
/// * `searchKey` → `{{key}}`；`searchPage`/`<searchPage±1>` → `{{page}}`/`{{page±1}}`
/// * `@Header:{...}` → `,{"headers":...}`；`|charset=x` → `,{"charset":"x"}`
/// * `url@body` → `url,{"method":"POST","body":...}`
class ImportOldData {
  ImportOldData._();

  static final _headerPattern =
      RegExp(r'@Header:\{.+?\}', caseSensitive: false);
  static final _jsPattern = RegExp(r'\{\{.+?\}\}', caseSensitive: false);

  /// 迁移结果统计
  static Future<ImportOldResult> importDir(String dirPath) async {
    var books = 0;
    var sources = 0;
    var rules = 0;
    final errors = <String>[];

    Future<void> run(String fileName, Future<int> Function(String json) fn, String label) async {
      final f = File('$dirPath/$fileName');
      if (!f.existsSync()) return;
      try {
        final n = await fn(await f.readAsString());
        switch (label) {
          case '书架':
            books = n;
            break;
          case '书源':
            sources = n;
            break;
          case '替换规则':
            rules = n;
            break;
        }
      } catch (e) {
        errors.add('$label: $e');
      }
    }

    await run('myBookShelf.json', importOldBookshelf, '书架');
    await run('myBookSource.json', importOldSource, '书源');
    await run('myBookReplaceRule.json', importOldReplaceRule, '替换规则');
    return ImportOldResult(books: books, sources: sources, rules: rules, errors: errors);
  }

  /// 旧书架单条 JSON → [Book]（E: fromOldBooks 的逐条转换，供恢复回退复用）
  static Book? bookFromOldMap(Map<String, dynamic> item) {
    final bookUrl = _str(item['noteUrl']) ?? '';
    if (bookUrl.isEmpty) return null;
    final name = _str(item['bookInfoBean'] is Map ? (item['bookInfoBean'] as Map)['name'] : null) ?? '';
    return Book(
      name: name,
      author: _str(_sub(item, 'bookInfoBean', 'author')) ?? '',
      bookUrl: bookUrl,
      origin: _str(item['tag']) ?? '',
      originName: _str(_sub(item, 'bookInfoBean', 'origin')) ?? '',
      local: (_str(item['tag']) ?? '') == 'loc_book',
      type: (_str(_sub(item, 'bookInfoBean', 'bookSourceType')) == 'AUDIO') ? 1 : 0,
      coverUrl: _str(_sub(item, 'bookInfoBean', 'coverUrl')),
      customCoverUrl: _str(item['customCoverPath']),
      intro: _str(_sub(item, 'bookInfoBean', 'introduce')),
      lastChapter: _str(item['lastChapterName']),
      durChapterIndex: _int(item['durChapter']) ?? 0,
      durChapterPos: _int(item['durChapterPage']) ?? 0,
      durChapterTime: _int(item['finalDate']) ?? 0,
      lastCheckTime: _int(_sub(item, 'bookInfoBean', 'finalRefreshData')) ?? 0,
      canUpdate: _bool(item['allowUpdate']) == true,
      order: _int(item['serialNumber']) ?? 0,
      variable: _str(item['variable']),
      noteUrl: bookUrl,
    );
  }

  /// 判断书源 Map 是否为旧版格式（E: Restore.kt 回退条件）
  static bool isOldSourceMap(Map<String, dynamic> map) =>
      map.containsKey('ruleSearchUrl') && !map.containsKey('searchUrl');

  /// 导入旧书架（E: importOldBookshelf）
  static Future<int> importOldBookshelf(String json) async {
    final items = _decodeList(json);
    final db = DatabaseService();
    final existing = (await db.getAllBooks()).map((b) => b.bookUrl).toSet();
    final books = <Book>[];
    for (final item in items) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final bookUrl = _str(map['noteUrl']) ?? '';
      if (bookUrl.isEmpty) continue;
      if (existing.contains(bookUrl)) continue; // 已存在跳过（E 同）
      final book = bookFromOldMap(map);
      if (book != null) books.add(book);
    }
    for (final b in books) {
      await db.insertBook(b);
    }
    return books.length;
  }

  /// 导入旧书源（E: importOldSource）
  static Future<int> importOldSource(String json) async {
    final items = _decodeList(json);
    final db = DatabaseService();
    final existing = (await db.getAllSources()).map((s) => s.bookSourceUrl).toSet();
    var count = 0;
    for (final item in items) {
      if (item is! Map) continue;
      final source = fromOldBookSource(item);
      if (source == null) continue;
      if (existing.contains(source.bookSourceUrl)) continue;
      await db.insertSource(source);
      count++;
    }
    return count;
  }

  /// 导入旧替换规则（E: importOldReplaceRule）
  static Future<int> importOldReplaceRule(String json) async {
    final items = _decodeList(json);
    final db = DatabaseService();
    var count = 0;
    for (final item in items) {
      if (item is! Map) continue;
      final rule = ReplaceRule.fromMap(Map<String, dynamic>.from(item));
      await db.insertReplaceRule(rule);
      count++;
    }
    return count;
  }

  // ============================ 旧书源转换 ============================

  /// 旧书源 JSON → [BookSource]；缺 bookSourceUrl 返回 null（E 抛 wrong_format）。
  static BookSource? fromOldBookSource(Map<dynamic, dynamic> jsonItem) {
    final bookSourceUrl = _str(jsonItem['bookSourceUrl']);
    if (bookSourceUrl == null || bookSourceUrl.isEmpty) return null;
    final isAudio = _str(jsonItem['bookSourceType']) == 'AUDIO';
    final exploreUrl = toNewUrls(_str(jsonItem['ruleFindUrl']));
    var content = toNewRule(_str(jsonItem['ruleBookContent'])) ?? '';
    if (content.startsWith(r'$') && !content.startsWith(r'$.')) {
      content = content.substring(1);
    }
    return BookSource(
      bookSourceUrl: bookSourceUrl,
      bookSourceName: _str(jsonItem['bookSourceName']) ?? '',
      bookSourceGroup: _str(jsonItem['bookSourceGroup']),
      loginUrl: _str(jsonItem['loginUrl']),
      loginUi: _str(jsonItem['loginUi']),
      loginCheckJs: _str(jsonItem['loginCheckJs']),
      coverDecodeJs: _str(jsonItem['coverDecodeJs']),
      bookSourceComment: _str(jsonItem['bookSourceComment']) ?? '',
      bookUrlPattern: _str(jsonItem['ruleBookUrlPattern']),
      customOrder: _int(jsonItem['serialNumber']) ?? 0,
      header: uaToHeader(_str(jsonItem['httpUserAgent'])),
      searchUrl: toNewUrl(_str(jsonItem['ruleSearchUrl'])),
      exploreUrl: exploreUrl,
      bookSourceType: isAudio ? 1 : 0,
      enabled: _bool(jsonItem['enable']) ?? true,
      enabledExplore: exploreUrl == null || exploreUrl.isEmpty ? false : true,
      ruleSearch: {
        'bookList': toNewRule(_str(jsonItem['ruleSearchList'])),
        'name': toNewRule(_str(jsonItem['ruleSearchName'])),
        'author': toNewRule(_str(jsonItem['ruleSearchAuthor'])),
        'intro': toNewRule(_str(jsonItem['ruleSearchIntroduce'])),
        'kind': toNewRule(_str(jsonItem['ruleSearchKind'])),
        'bookUrl': toNewRule(_str(jsonItem['ruleSearchNoteUrl'])),
        'coverUrl': toNewRule(_str(jsonItem['ruleSearchCoverUrl'])),
        'lastChapter': toNewRule(_str(jsonItem['ruleSearchLastChapter'])),
      },
      ruleExplore: {
        'bookList': toNewRule(_str(jsonItem['ruleFindList'])),
        'name': toNewRule(_str(jsonItem['ruleFindName'])),
        'author': toNewRule(_str(jsonItem['ruleFindAuthor'])),
        'intro': toNewRule(_str(jsonItem['ruleFindIntroduce'])),
        'kind': toNewRule(_str(jsonItem['ruleFindKind'])),
        'bookUrl': toNewRule(_str(jsonItem['ruleFindNoteUrl'])),
        'coverUrl': toNewRule(_str(jsonItem['ruleFindCoverUrl'])),
        'lastChapter': toNewRule(_str(jsonItem['ruleFindLastChapter'])),
      },
      ruleBookInfo: {
        'init': toNewRule(_str(jsonItem['ruleBookInfoInit'])),
        'name': toNewRule(_str(jsonItem['ruleBookName'])),
        'author': toNewRule(_str(jsonItem['ruleBookAuthor'])),
        'intro': toNewRule(_str(jsonItem['ruleIntroduce'])),
        'kind': toNewRule(_str(jsonItem['ruleBookKind'])),
        'coverUrl': toNewRule(_str(jsonItem['ruleCoverUrl'])),
        'lastChapter': toNewRule(_str(jsonItem['ruleBookLastChapter'])),
        'tocUrl': toNewRule(_str(jsonItem['ruleChapterUrl'])),
      },
      ruleToc: {
        'chapterList': toNewRule(_str(jsonItem['ruleChapterList'])),
        'chapterName': toNewRule(_str(jsonItem['ruleChapterName'])),
        'chapterUrl': toNewRule(_str(jsonItem['ruleContentUrl'])),
        'nextTocUrl': toNewRule(_str(jsonItem['ruleChapterUrlNext'])),
      },
      ruleContent: {
        'content': content,
        'replaceRegex': toNewRule(_str(jsonItem['ruleBookContentReplace'])),
        'nextContentUrl': toNewRule(_str(jsonItem['ruleContentUrlNext'])),
      },
    );
  }

  // ============================ 规则语法转换 ============================

  /// default 规则适配（E: toNewRule）：`#`→`##`、`|`→`||`、`&`→`&&`。
  static String? toNewRule(String? oldRule) {
    if (oldRule == null || oldRule.trim().isEmpty) return null;
    var newRule = oldRule;
    var reverse = false;
    var allinone = false;
    if (oldRule.startsWith('-')) {
      reverse = true;
      newRule = oldRule.substring(1);
    }
    if (newRule.startsWith('+')) {
      allinone = true;
      newRule = newRule.substring(1);
    }
    final lower = newRule.toLowerCase();
    final special = lower.startsWith('@css:') ||
        lower.startsWith('@xpath:') ||
        newRule.startsWith('//') ||
        newRule.startsWith('##') ||
        newRule.startsWith(':') ||
        lower.contains('@js:') ||
        lower.contains('<js>');
    if (!special) {
      if (newRule.contains('#') && !newRule.contains('##')) {
        newRule = oldRule.replaceAll('#', '##');
      }
      if (newRule.contains('|') && !newRule.contains('||')) {
        if (newRule.contains('##')) {
          final list = newRule.split('##');
          if (list[0].contains('|')) {
            final sb = StringBuffer(list[0].replaceAll('|', '||'));
            for (var i = 1; i < list.length; i++) {
              sb.write('##${list[i]}');
            }
            newRule = sb.toString();
          }
        } else {
          newRule = newRule.replaceAll('|', '||');
        }
      }
      if (newRule.contains('&') &&
          !newRule.contains('&&') &&
          !newRule.contains('http') &&
          !newRule.startsWith('/')) {
        newRule = newRule.replaceAll('&', '&&');
      }
    }
    if (allinone) newRule = '+$newRule';
    if (reverse) newRule = '-$newRule';
    return newRule;
  }

  /// 发现/搜索 URL 转换（E: toNewUrls）
  static String? toNewUrls(String? oldUrls) {
    if (oldUrls == null || oldUrls.trim().isEmpty) return null;
    final lower = oldUrls.toLowerCase();
    if (lower.startsWith('@js:') || lower.startsWith('<js>')) return oldUrls;
    if (!oldUrls.contains('\n') && !oldUrls.contains('&&')) {
      return toNewUrl(oldUrls);
    }
    final urls = oldUrls.split(RegExp(r'(&&|\r?\n)+'));
    return urls
        .map((u) => toNewUrl(u)?.replaceAll(RegExp(r'\n\s*'), ''))
        .where((u) => u != null && u.isNotEmpty)
        .join('\n');
  }

  /// 单条 URL 转换（E: toNewUrl）：Header/charset/method 选项、searchKey/searchPage 占位。
  static String? toNewUrl(String? oldUrl) {
    if (oldUrl == null || oldUrl.trim().isEmpty) return null;
    var url = oldUrl;
    if (url.toLowerCase().startsWith('<js>')) {
      return url
          .replaceAll('=searchKey', '={{key}}')
          .replaceAll('=searchPage', '={{page}}');
    }
    final map = <String, dynamic>{};
    final headerMatch = _headerPattern.firstMatch(url);
    if (headerMatch != null) {
      final headerJson = headerMatch.group(0)!.substring(8);
      url = url.replaceAll(headerMatch.group(0)!, '');
      // 去掉剥离 @Header 后残留的尾逗号
      url = url.replaceAll(RegExp(r',+\s*$'), '');
      try {
        final decoded = jsonDecode(headerJson);
        map['headers'] = decoded is Map ? decoded : headerJson;
      } catch (_) {
        map['headers'] = headerJson;
      }
    }
    var urlList = url.split('|');
    url = urlList[0];
    if (urlList.length > 1) {
      final charset = urlList[1].split('=');
      map['charset'] = charset.length > 1 ? charset[1] : charset[0];
    }
    // {{...}} JS 块先占位，避免 { } → < > 替换破坏
    final jsList = <String>[];
    var matcher = _jsPattern.firstMatch(url);
    while (matcher != null) {
      jsList.add(matcher.group(0)!);
      url = url.replaceAll(jsList.last, '\$${jsList.length - 1}');
      matcher = _jsPattern.firstMatch(url);
    }
    url = url.replaceAll('{', '<').replaceAll('}', '>');
    url = url.replaceAll('searchKey', '{{key}}');
    url = url
        .replaceAllMapped(RegExp(r'<searchPage([-+]1)>'), (m) => '{{page${m.group(1)}}}')
        .replaceAllMapped(RegExp(r'searchPage([-+]1)'), (m) => '{{page${m.group(1)}}}')
        .replaceAll('searchPage', '{{page}}');
    for (var index = 0; index < jsList.length; index++) {
      url = url.replaceAll(
          '\$$index',
          jsList[index]
              .replaceAll('searchKey', 'key')
              .replaceAll('searchPage', 'page'));
    }
    urlList = url.split('@');
    url = urlList[0];
    if (urlList.length > 1) {
      map['method'] = 'POST';
      // { } → < > 的批量替换影响了 body 内的 JSON 括号，此处还原
      map['body'] = urlList[1].replaceAll('<', '{').replaceAll('>', '}');
    }
    if (map.isNotEmpty) {
      url += ',${jsonEncode(map)}';
    }
    return url;
  }

  /// 旧 httpUserAgent → header JSON（E: uaToHeader）
  static String? uaToHeader(String? ua) {
    if (ua == null || ua.isEmpty) return null;
    return jsonEncode({'User-Agent': ua});
  }

  // ============================ 工具 ============================

  static List<dynamic> _decodeList(String json) {
    final data = jsonDecode(json);
    return data is List ? data : [];
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static bool? _bool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    return v?.toString() == 'true' ? true : null;
  }

  static dynamic _sub(Map<dynamic, dynamic> item, String key, String field) {
    final m = item[key];
    return m is Map ? m[field] : null;
  }
}

/// 旧数据迁移结果
class ImportOldResult {
  final int books;
  final int sources;
  final int rules;
  final List<String> errors;

  const ImportOldResult({
    required this.books,
    required this.sources,
    required this.rules,
    required this.errors,
  });

  bool get isEmpty => books == 0 && sources == 0 && rules == 0 && errors.isEmpty;

  String summary() {
    if (isEmpty) return '未找到可导入的旧数据';
    final parts = <String>[
      if (books > 0) '书架 $books 本',
      if (sources > 0) '书源 $sources 个',
      if (rules > 0) '替换规则 $rules 条',
    ];
    var msg = '成功导入${parts.join('、')}';
    if (errors.isNotEmpty) msg += '；失败 ${errors.length} 项（${errors.first}）';
    return msg;
  }
}
