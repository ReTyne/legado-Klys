import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/common/app_navigator.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/config/theme_share.dart';

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
  ///  - `legado://import?url=<编码后的JSON地址>[&type=bookSource|rssSource|theme]`
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

  /// legado://import：url 参数拉取远端内容，json 参数直接取内容
  Future<void> _handleLegadoUri(Uri uri) async {
    final url = uri.queryParameters['url'];
    final json = uri.queryParameters['json'];
    final type = uri.queryParameters['type'];
    if (url != null && url.trim().isNotEmpty) {
      final body = await _fetchText(url.trim());
      await _importRaw(body, type: type);
    } else if (json != null && json.trim().isNotEmpty) {
      await _importRaw(json, type: type);
    } else {
      _tip('链接缺少 url / json 参数');
    }
  }

  /// share://text?content=...：系统分享的文本（URL 或 JSON）
  Future<void> _handleShareUri(Uri uri) async {
    final content = uri.queryParameters['content'] ?? '';
    if (content.trim().isEmpty) {
      _tip('分享内容为空');
      return;
    }
    await _importRaw(content);
  }

  /// 导入原始内容：URL 先抓取，再按 JSON 解析并分派类型
  Future<void> _importRaw(String raw, {String? type}) async {
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

  /// 归一化显式 type 参数（bookSource / rssSource / theme）
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
      default:
        return null;
    }
  }

  /// 无显式 type 时按 JSON 结构推断（取数组首元素 / 单对象判断）
  String? _detectType(dynamic data) {
    final first = data is List && data.isNotEmpty ? data.first : data;
    if (first is Map) {
      if (first.containsKey('bookSourceUrl')) return 'bookSource';
      if (first.containsKey('sourceUrl') ||
          first.containsKey('ruleArticles') ||
          first.containsKey('sortUrl')) {
        return 'rss';
      }
      if (first.containsKey('themeName') ||
          first.containsKey('colorPrimary') ||
          first.containsKey('primaryColor')) {
        return 'theme';
      }
    }
    return null;
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
