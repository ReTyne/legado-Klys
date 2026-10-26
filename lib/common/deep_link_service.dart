import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/common/app_navigator.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/config/theme_share.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// legado:// 深链 / 系统分享文本 的统一接收与导入服务（对齐 legado-E 的 OnLineImportActivity）。
///
/// 数据流：
/// ```text
/// Intent(VIEW legado://… / SEND text/plain)
///   → MainActivity.handleDeepLinkIntent 归一化为链接字符串
///   → MethodChannel 'legado/deep_link'（启动时 getInitialLink 取 / 运行中 onLink 推）
///   → DeepLinkService.links 流
///   → handleLink() 按类型分派：书源 / RSS 源 / 主题
/// ```
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  static const MethodChannel channel = MethodChannel('legado/deep_link');

  final StreamController<String> _linkController =
      StreamController<String>.broadcast();

  /// 深链 / 分享链接流（broadcast，可多处监听）
  Stream<String> get links => _linkController.stream;

  /// 网络导入用的 HTTP 客户端（与书源管理页「网络导入」同款配置）
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.bytes,
  ));

  final DatabaseService _db = DatabaseService();

  bool _initialized = false;

  /// 注册 channel 回调并取回启动时待处理的链接（幂等，重复调用无副作用）。
  /// main.dart 接入：`DeepLinkService.instance.init()` 后监听 [links] 并调用 [handleLink]。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink' && call.arguments is String) {
        _linkController.add(call.arguments as String);
      }
      return null;
    });
    try {
      final initial = await channel.invokeMethod<String>('getInitialLink');
      if (initial != null && initial.isNotEmpty) {
        _linkController.add(initial);
      }
    } catch (_) {
      // 平台侧未实现（单测 / 桌面端）：忽略
    }
  }

  /// 处理一条链接（供订阅 [links] 后调用，也可直接调用）。
  /// 支持：
  ///  - `legado://import/{path}?src={url}`（对齐 legado-E OnLineImportActivity：
  ///    bookSource / rssSource / replaceRule / textTocRule / httpTTS / dictRule /
  ///    theme / readConfig / importonline/{type}）
  ///  - `legado://import?url=<编码后的JSON地址>[&type=...]`（本项目早期格式）
  ///  - `legado://import?type=bookSource&json=<编码后的JSON>`
  ///  - `share://text?content=<编码后的URL或JSON>`
  Future<void> handleLink(String link) async {
    try {
      final uri = Uri.tryParse(link.trim());
      if (uri == null) {
        _tip('无法解析的导入链接');
        return;
      }
      switch (uri.scheme) {
        case 'legado':
          await _handleLegadoUri(uri);
        case 'share':
          await _handleShareUri(uri);
        default:
          _tip('不支持的链接：$link');
      }
    } catch (e) {
      _tip('导入失败：$e');
    }
  }

  /// legado://import：兼容 E 的路径格式与本项目早期的查询参数格式
  Future<void> _handleLegadoUri(Uri uri) async {
    // ---- E 格式：legado://import/{path}?src={url} ----
    final src = uri.queryParameters['src'] ?? uri.queryParameters['url'];
    final segments = uri.pathSegments;
    // importonline/{type}（E 的 host 形式：legado://importonline/booksource?src=）
    if (segments.isNotEmpty && segments.first == 'importonline') {
      final type = segments.length > 1 ? segments[1] : '';
      if (src == null || src.trim().isEmpty) {
        _tip('链接缺少 src 参数');
        return;
      }
      await _importByType(_normalizeType(type) ?? 'bookSource', src.trim());
      return;
    }
    if (segments.isNotEmpty && segments.first == 'import' && segments.length > 1) {
      final path = segments[1];
      if (src == null || src.trim().isEmpty) {
        _tip('链接缺少 src 参数');
        return;
      }
      switch (path) {
        case 'bookSource':
          await _importByType('bookSource', src.trim());
        case 'rssSource':
          await _importByType('rss', src.trim());
        case 'replaceRule':
          await _importByType('replaceRule', src.trim());
        case 'textTocRule':
          await _importByType('txtRule', src.trim());
        case 'httpTTS':
          await _importByType('httpTts', src.trim());
        case 'dictRule':
          await _importByType('dictRule', src.trim());
        case 'theme':
          await _importByType('theme', src.trim());
        case 'readConfig':
          // 在线导入阅读配置包（E: OnLineImport readConfig）：URL 拉取 JSON 后写入
          // 权威键 read_config_json 并刷新阅读器内存态。
          await _importByType('readConfig', src.trim());
        case 'addToBookshelf':
          // 按书籍地址链接直接加入书架（E: addToBookshelf）：匹配书源 → 抓取详情 → 入库
          await _addToBookshelf(src.trim());
        default:
          // 未知路径：按内容推断类型（E 的 determineType）
          await _determineType(src.trim());
      }
      return;
    }

    // ---- 本项目早期格式：legado://import?url=&json=&type= ----
    final url = uri.queryParameters['url'];
    final json = uri.queryParameters['json'];
    final type = uri.queryParameters['type'];
    if (url != null && url.trim().isNotEmpty) {
      final body = await _fetchText(url.trim());
      await importRaw(body, type: type);
    } else if (json != null && json.trim().isNotEmpty) {
      await importRaw(json, type: type);
    } else if (src != null && src.trim().isNotEmpty) {
      await importRaw(src.trim(), type: type);
    } else {
      _tip('链接缺少 url / json / src 参数');
    }
  }

  /// 按显式类型导入（src 为 URL 时先拉取）
  Future<void> _importByType(String kind, String src) async {
    final body =
        src.startsWith('http://') || src.startsWith('https://') ? await _fetchText(src) : src;
    await importRaw(body, type: kind);
  }

  /// 未知类型时按内容推断（对齐 E BaseAssociationViewModel.importJson）：
  /// 拉取远端内容，JSON 则按特征键判断类型。
  Future<void> _determineType(String url) async {
    final body = await _fetchText(url);
    await importRaw(body);
  }

  /// share://text?content=...：系统分享的文本（URL 或 JSON）
  Future<void> _handleShareUri(Uri uri) async {
    final content = uri.queryParameters['content'] ?? '';
    if (content.trim().isEmpty) {
      _tip('分享内容为空');
      return;
    }
    await importRaw(content);
  }

  /// 导入原始内容：URL 先抓取，再按 JSON 解析并分派类型（公开供 UI 层调用）
  Future<void> importRaw(String raw, {String? type}) async {
    var text = raw.trim();
    if (text.isEmpty) {
      _tip('导入内容为空');
      return;
    }
    // 去掉 BOM 与换行包裹
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    text = text.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      text = await _fetchText(text);
    }
    dynamic data = _decodeJson(text);
    if (data == null) {
      _tip('无法解析导入内容（非 JSON）');
      return;
    }
    final kind = _normalizeType(type) ?? _detectType(data) ?? 'bookSource';
    switch (kind) {
      case 'bookSource':
        final n = await _importBookSources(data);
        _tip(n > 0 ? '成功导入 $n 个书源' : '未识别到有效书源');
      case 'rss':
        final n = await _importRssSources(data);
        _tip(n > 0 ? '成功导入 $n 个订阅源' : '未识别到有效订阅源');
      case 'theme':
        final theme = await ThemeShare.importThemeJson(jsonEncode(data));
        _tip(theme != null ? '已导入主题「${theme.name}」' : '主题解析失败');
      case 'readConfig':
        final ok = await _importReadConfig(data);
        _tip(ok ? '已导入阅读配置' : '阅读配置格式不正确');
      case 'replaceRule':
        final n = await _importReplaceRules(data);
        _tip(n > 0 ? '成功导入 $n 条替换规则' : '未识别到有效替换规则');
      case 'dictRule':
        final n = await _importDictRules(data);
        _tip(n > 0 ? '成功导入 $n 条字典规则' : '未识别到有效字典规则');
      case 'txtRule':
        final n = await _importTxtTocRules(data);
        _tip(n > 0 ? '成功导入 $n 条 TXT目录规则' : '未识别到有效TXT目录规则');
      case 'httpTts':
        final n = await _importHttpTts(data);
        _tip(n > 0 ? '成功导入 $n 个在线TTS' : '未识别到有效在线TTS');
      default:
        _tip('不支持的导入类型：$kind');
    }
  }

  /// JSON 解析：兼容数组 / 单对象 / JSONL（逐行一个对象）
  dynamic _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      final lines = text
          .split(RegExp(r'[\r\n]+'))
          .where((l) => l.trim().startsWith('{'))
          .toList();
      if (lines.isEmpty) return null;
      final arr = <dynamic>[];
      for (final l in lines) {
        try {
          arr.add(jsonDecode(l));
        } catch (_) {}
      }
      return arr.isEmpty ? null : arr;
    }
  }

  /// 导入书源（解包 {data:[…]} / {bookSources:[…]} 等订阅格式）
  Future<int> _importBookSources(dynamic data) async {
    dynamic unwrapped = data;
    if (unwrapped is Map && !unwrapped.containsKey('bookSourceUrl')) {
      for (final key in const [
        'data',
        'bookSources',
        'sources',
        'result',
        'list',
        'records',
      ]) {
        if (unwrapped[key] is List) {
          unwrapped = unwrapped[key];
          break;
        }
      }
    }
    var count = 0;
    final list = unwrapped is List ? unwrapped : [unwrapped];
    for (final item in list) {
      if (item is! Map) continue;
      try {
        final m = Map<String, dynamic>.from(item);
        if ((m['bookSourceUrl'] ?? '').toString().isEmpty) continue;
        await _db.insertSource(BookSource.fromJson(m));
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// 导入 RSS 订阅源（解包 {data:[…]} / {sources:[…]} 等订阅格式）
  Future<int> _importRssSources(dynamic data) async {
    dynamic unwrapped = data;
    if (unwrapped is Map && !unwrapped.containsKey('sourceUrl')) {
      for (final key in const ['data', 'sources', 'result', 'list']) {
        if (unwrapped[key] is List) {
          unwrapped = unwrapped[key];
          break;
        }
      }
    }
    var count = 0;
    final list = unwrapped is List ? unwrapped : [unwrapped];
    for (final item in list) {
      if (item is! Map) continue;
      try {
        final m = Map<String, dynamic>.from(item);
        if ((m['sourceUrl'] ?? m['url'] ?? '').toString().isEmpty) continue;
        await _db.insertRssSource(RssSource.fromJson(m));
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// 归一化显式 type 参数（含 E OnLineImport 的全部路径名）
  String? _normalizeType(String? type) {
    switch (type?.toLowerCase()) {
      case 'booksource':
      case 'book_source':
      case 'source':
        return 'bookSource';
      case 'rsssource':
      case 'rss_source':
      case 'rss':
        return 'rss';
      case 'theme':
        return 'theme';
      case 'replacerule':
      case 'replace_rule':
      case 'replace':
        return 'replaceRule';
      case 'dictrule':
      case 'dict_rule':
      case 'dict':
        return 'dictRule';
      case 'texttocrule':
      case 'txttocrule':
      case 'txt_rule':
      case 'txtrule':
        return 'txtRule';
      case 'httptts':
      case 'http_tts':
      case 'tts':
        return 'httpTts';
      case 'readconfig':
      case 'read_config':
        return 'readConfig';
      default:
        return null;
    }
  }

  /// 无显式 type 时按 JSON 结构推断（对齐 E importJson 的特征键顺序）
  String? _detectType(dynamic data) {
    final first = data is List && data.isNotEmpty ? data.first : data;
    if (first is Map) {
      if (first.containsKey('bookSourceUrl')) return 'bookSource';
      if (first.containsKey('sourceUrl') ||
          first.containsKey('ruleArticles') ||
          first.containsKey('sortUrl')) {
        return 'rss';
      }
      if (first.containsKey('pattern')) return 'replaceRule';
      if (first.containsKey('themeName') ||
          first.containsKey('colorPrimary') ||
          first.containsKey('primaryColor')) {
        return 'theme';
      }
      if (first.containsKey('showRule')) return 'dictRule';
      if (first.containsKey('name') && first.containsKey('rule')) return 'txtRule';
      if (first.containsKey('name') && first.containsKey('url')) return 'httpTts';
    }
    return null;
  }

  /// 导入替换规则（E: ImportReplaceRuleDialog）
  Future<int> _importReplaceRules(dynamic data) async {
    final list = data is List ? data : [data];
    var count = 0;
    for (final item in list) {
      if (item is! Map) continue;
      try {
        await _db.insertReplaceRule(
            ReplaceRule.fromMap(Map<String, dynamic>.from(item)));
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// 导入字典规则（E: ImportDictRuleDialog）
  Future<int> _importDictRules(dynamic data) async {
    final list = data is List ? data : [data];
    var count = 0;
    for (final item in list) {
      if (item is! Map) continue;
      try {
        await _db.insertDictRule(
            DictRule.fromMap(Map<String, dynamic>.from(item)));
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// 导入 TXT 目录规则（E: ImportTxtTocRuleDialog，JSON 键 `rule` → chapterRule）
  Future<int> _importTxtTocRules(dynamic data) async {
    final list = data is List ? data : [data];
    var count = 0;
    for (final item in list) {
      if (item is! Map) continue;
      try {
        final m = Map<String, dynamic>.from(item);
        // E 的键名 rule/replacement 映射到 Klys 的 chapterRule/volumeRule
        if (m.containsKey('rule') && !m.containsKey('chapterRule')) {
          m['chapterRule'] = m['rule'];
        }
        if (m.containsKey('replacement') && !m.containsKey('volumeRule')) {
          m['volumeRule'] = m['replacement'];
        }
        await _db.insertTxtTocRule(TxtTocRule.fromMap(m));
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// 导入在线 TTS（E: ImportHttpTtsDialog）
  Future<int> _importHttpTts(dynamic data) async {
    final list = data is List ? data : [data];
    var count = 0;
    for (final item in list) {
      if (item is! Map) continue;
      try {
        await _db.insertHttpTTS(
            HttpTTS.fromMap(Map<String, dynamic>.from(item)));
        count++;
      } catch (_) {}
    }
    return count;
  }

  /// 导入阅读配置（E: OnLineImport readConfig）：解析 JSON（单对象或数组）为
  /// [ReadConfig]，写入权威键 `read_config_json` 并刷新阅读器内存态。
  /// 返回是否成功。
  Future<bool> _importReadConfig(dynamic data) async {
    if (data == null) return false;
    final map = data is List && data.isNotEmpty ? data.first : data;
    if (map is! Map) return false;
    try {
      final cfg = ReadConfig.fromJson(Map<String, dynamic>.from(map));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('read_config_json', jsonEncode(cfg.toJson()));
      await ReadProvider.liveInstance?.reloadReadConfig();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 按书籍地址链接加入书架（E: addToBookshelf）：依据 `bookUrlPattern` 匹配可用
  /// 书源 → 抓取书籍详情 → 入库并提示结果。
  Future<void> _addToBookshelf(String url) async {
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      _tip('书籍链接无效');
      return;
    }
    final engine = BookSourceEngine();
    BookSource? matched;
    try {
      final sources = await _db.getAllSources(enabled: true);
      for (final s in sources) {
        try {
          if (engine.matchBookUrl(s, url)) {
            matched = s;
            break;
          }
        } catch (_) {}
      }
    } catch (_) {}
    if (matched == null) {
      _tip('没有书源匹配该链接');
      return;
    }
    try {
      final book = await engine.getBookInfo(matched, url).timeout(const Duration(seconds: 30));
      if (book == null || book.name.isEmpty) {
        _tip('获取书籍信息失败');
        return;
      }
      book.bookUrl = url;
      book.origin = matched.bookSourceUrl;
      book.originName = matched.bookSourceName;
      await BookProvider().addBook(book);
      _tip('已加入书架：《${book.name}》');
    } catch (e) {
      _tip('添加失败：$e');
    }
  }

  /// GET 拉取文本（兼容无 Content-Encoding 头的 gzip 响应）
  Future<String> _fetchText(String url) async {
    final resp = await _dio.get<List<int>>(url);
    final bytes = resp.data ?? const <int>[];
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return utf8.decode(gzip.decode(bytes));
    }
    return utf8.decode(bytes);
  }

  /// 全局 SnackBar 提示（无需 BuildContext，失败不影响导入流程）
  void _tip(String message) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {}
  }
}
