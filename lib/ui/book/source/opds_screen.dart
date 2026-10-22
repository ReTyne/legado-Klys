import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:legado_md3/help/storage/import_book_service.dart';

/// OPDS 条目链接
class _OpdsLink {
  final String href;
  final String? rel;
  final String? type;
  final String? title;
  _OpdsLink({required this.href, this.rel, this.type, this.title});
}

/// OPDS 条目：既可能是子目录，也可能是可下载的书籍
class _OpdsEntry {
  final String? id;
  final String title;
  final String? author;
  final String? summary;
  final String? updated;
  final String? cover;
  final String? downloadUrl;
  final String? navUrl; // 子目录（导航 feed）地址
  final List<String> categories;

  _OpdsEntry({
    this.id,
    required this.title,
    this.author,
    this.summary,
    this.updated,
    this.cover,
    this.downloadUrl,
    this.navUrl,
    this.categories = const [],
  });

  bool get isNavigation => navUrl != null && downloadUrl == null;
}

/// OPDS Feed 解析结果
class _OpdsFeed {
  final String? title;
  final List<_OpdsEntry> entries;
  final String? nextUrl;
  final String? prevUrl;
  final String? searchUrl;

  _OpdsFeed(
      {this.title,
      this.entries = const [],
      this.nextUrl,
      this.prevUrl,
      this.searchUrl});
}

/// OPDS 书源浏览页：真实解析 Atom feed（<feed><entry><title><link>），
/// 支持分页、OpenSearch 搜索、Basic 认证、下载并加入书架。
///
/// 说明：项目未提供 xml 包，这里使用 html 包解析（已验证可正确解析 Atom），
/// 并在 feed 级 link 取不到时用正则兜底。
class OpdsScreen extends StatefulWidget {
  final String? initialUrl;
  const OpdsScreen({super.key, this.initialUrl});

  @override
  State<OpdsScreen> createState() => _OpdsScreenState();
}

class _OpdsScreenState extends State<OpdsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _pwdController = TextEditingController();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
    validateStatus: (s) => s != null && s < 500,
  ));

  final List<String> _stack = <String>[]; // 浏览历史（用于返回上一层）
  String? _currentUrl;
  _OpdsFeed? _feed;
  List<_OpdsEntry> _entries = [];
  bool _loading = false;
  String? _error;
  double? _downloadProgress;
  String? _downloadingTitle;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
      _load(widget.initialUrl!);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    _userController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  // ---------- 网络 ----------
  Map<String, String> get _headers {
    final h = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) LegadoMD3/OPDS',
      'Accept':
          'application/atom+xml,application/xml,text/xml,application/opensearchdescription+xml,*/*',
    };
    final user = _userController.text.trim();
    if (user.isNotEmpty) {
      h[HttpHeaders.authorizationHeader] =
          'Basic ${base64Encode(utf8.encode('$user:${_pwdController.text}'))}';
    }
    return h;
  }

  Future<String> _get(String url) async {
    final resp = await _dio.get<String>(url,
        options: Options(
          headers: _headers,
          responseType: ResponseType.plain,
        ));
    final code = resp.statusCode ?? 0;
    if (code >= 400) throw Exception('HTTP $code');
    final body = resp.data;
    if (body == null || body.isEmpty) throw Exception('返回内容为空');
    return body;
  }

  // ---------- 解析 ----------
  String _resolve(String base, String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    try {
      return Uri.parse(base).resolve(href).toString();
    } catch (_) {
      return href;
    }
  }

  String? _childText(dom.Element parent, String name) {
    for (final c in parent.children) {
      if (c.localName == name) {
        final t = c.text.trim();
        if (t.isNotEmpty) return t;
      }
    }
    final all = parent.getElementsByTagName(name);
    for (final e in all) {
      final t = e.text.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  List<_OpdsLink> _linksOf(dom.Element el) {
    final out = <_OpdsLink>[];
    for (final c in el.children) {
      if (c.localName == 'link') {
        out.add(_OpdsLink(
          href: c.attributes['href'] ?? '',
          rel: c.attributes['rel'],
          type: c.attributes['type'],
          title: c.attributes['title'],
        ));
      }
    }
    if (out.isEmpty) {
      for (final l in el.getElementsByTagName('link')) {
        out.add(_OpdsLink(
          href: l.attributes['href'] ?? '',
          rel: l.attributes['rel'],
          type: l.attributes['type'],
          title: l.attributes['title'],
        ));
      }
    }
    return out.where((l) => l.href.isNotEmpty).toList();
  }

  /// feed 级 link（self/search/next/prev）不能与 entry 内的 link 混淆，
  /// 因此只取 <feed> 的直接子节点；取不到再对首个 <entry> 之前的片段做正则兜底。
  List<_OpdsLink> _feedLevelLinks(String xml, dom.Document doc) {
    final feeds = doc.getElementsByTagName('feed');
    if (feeds.isNotEmpty) {
      final direct = feeds.first.children
          .where((c) => c.localName == 'link')
          .map((c) => _OpdsLink(
                href: c.attributes['href'] ?? '',
                rel: c.attributes['rel'],
                type: c.attributes['type'],
                title: c.attributes['title'],
              ))
          .where((l) => l.href.isNotEmpty)
          .toList();
      if (direct.isNotEmpty) return direct;
    }
    // 正则兜底：只扫描第一个 <entry> 之前的片段
    final idx = xml.indexOf(RegExp(r'<entry[\s>]', caseSensitive: false));
    final head = idx > 0 ? xml.substring(0, idx) : xml;
    final out = <_OpdsLink>[];
    for (final m in
        RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(head)) {
      final tag = m.group(0)!;
      out.add(_OpdsLink(
        href: _attr(tag, 'href') ?? '',
        rel: _attr(tag, 'rel'),
        type: _attr(tag, 'type'),
        title: _attr(tag, 'title'),
      ));
    }
    return out.where((l) => l.href.isNotEmpty).toList();
  }

  String? _attr(String tag, String name) {
    final m = RegExp('$name\\s*=\\s*"([^"]*)"', caseSensitive: false)
        .firstMatch(tag);
    if (m != null) return m.group(1);
    final m2 = RegExp("$name\\s*=\\s*'([^']*)'", caseSensitive: false)
        .firstMatch(tag);
    return m2?.group(1);
  }

  bool _isAtomCatalog(String? type) =>
      (type ?? '').toLowerCase().contains('atom+xml');

  bool _isAcquisitionFile(String? type) {
    final t = (type ?? '').toLowerCase();
    return t.contains('epub') ||
        t.contains('pdf') ||
        t.contains('mobipocket') ||
        t.contains('x-mobi') ||
        t.contains('text/plain') ||
        t.contains('application/octet-stream');
  }

  _OpdsEntry _parseEntry(dom.Element e, String baseUrl) {
    final links = _linksOf(e);
    String? cover;
    String? download;
    String? nav;
    for (final l in links) {
      final rel = l.rel ?? '';
      final type = l.type ?? '';
      if (cover == null &&
          (rel == 'http://opds-spec.org/image' ||
              rel == 'http://opds-spec.org/image/thumbnail' ||
              type.startsWith('image/'))) {
        cover = _resolve(baseUrl, l.href);
        continue;
      }
      if (download == null &&
          (rel.startsWith('http://opds-spec.org/acquisition') ||
              _isAcquisitionFile(type))) {
        download = _resolve(baseUrl, l.href);
        continue;
      }
      if (nav == null &&
          (rel == 'subsection' ||
              rel == 'http://opds-spec.org/sort/new' ||
              (rel == 'alternate' && _isAtomCatalog(type)))) {
        nav = _resolve(baseUrl, l.href);
      }
    }
    final author = e.children
        .where((c) => c.localName == 'author')
        .map((a) => _childText(a, 'name') ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final categories = e.children
        .where((c) => c.localName == 'category')
        .map((c) => c.attributes['label'] ?? c.attributes['term'] ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return _OpdsEntry(
      id: _childText(e, 'id'),
      title: _childText(e, 'title') ?? '(无标题)',
      author: author.isEmpty ? null : author,
      summary: _childText(e, 'summary') ?? _childText(e, 'content'),
      updated: _childText(e, 'updated') ?? _childText(e, 'published'),
      cover: cover,
      downloadUrl: download,
      navUrl: nav,
      categories: categories,
    );
  }

  _OpdsFeed _parseFeed(String xml, String baseUrl) {
    final doc = html_parser.parse(xml);
    final feedEls = doc.getElementsByTagName('feed');
    final title = feedEls.isEmpty
        ? _regexTitle(xml)
        : _childText(feedEls.first, 'title');
    final feedLinks = _feedLevelLinks(xml, doc);
    String? next;
    String? prev;
    String? search;
    for (final l in feedLinks) {
      final rel = (l.rel ?? '').toLowerCase();
      if (rel == 'next') next = _resolve(baseUrl, l.href);
      if (rel == 'prev' || rel == 'previous') {
        prev = _resolve(baseUrl, l.href);
      }
      if (rel.contains('search')) search = _resolve(baseUrl, l.href);
    }
    final entries = doc
        .getElementsByTagName('entry')
        .map((e) => _parseEntry(e, baseUrl))
        .toList();
    return _OpdsFeed(
      title: title,
      entries: entries,
      nextUrl: next,
      prevUrl: prev,
      searchUrl: search,
    );
  }

  String? _regexTitle(String xml) {
    final m =
        RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
            .firstMatch(xml);
    if (m == null) return null;
    return _unescape(m.group(1)!.trim());
  }

  String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');

  // ---------- 加载 / 分页 / 搜索 ----------
  Future<void> _load(String raw, {bool push = true}) async {
    final url = _normalizeUrl(raw);
    if (url.isEmpty) {
      setState(() => _error = '请输入 OPDS 目录地址');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final xml = await _get(url);
      final feed = _parseFeed(xml, url);
      if (!mounted) return;
      setState(() {
        if (push && _currentUrl != null && _currentUrl != url) {
          _stack.add(_currentUrl!);
        }
        _currentUrl = url;
        _urlController.text = url;
        _feed = feed;
        _entries = feed.entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _normalizeUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }

  Future<void> _goBack() async {
    if (_stack.isEmpty) return;
    final url = _stack.removeLast();
    await _load(url, push: false);
  }

  Future<void> _doSearch() async {
    final kw = _searchController.text.trim();
    if (kw.isEmpty) return;
    final base = _currentUrl ?? _normalizeUrl(_urlController.text);
    if (base.isEmpty) return;
    var tpl = _feed?.searchUrl;
    // OpenSearch 描述文档需要再取一次真正的模板
    if (tpl != null && (tpl.endsWith('.xml') || tpl.contains('opensearch'))) {
      tpl = await _resolveOpenSearch(tpl);
    }
    tpl ??= _feed?.searchUrl;
    final url = tpl == null
        ? '$base${base.contains('?') ? '&' : '?'}q=${Uri.encodeComponent(kw)}'
        : tpl
            .replaceAll('{searchTerms}', Uri.encodeComponent(kw))
            .replaceAll('{searchTerms/?}', Uri.encodeComponent(kw));
    await _load(url);
  }

  /// 解析 OpenSearch 描述 XML，取出 Atom 搜索模板
  Future<String?> _resolveOpenSearch(String url) async {
    try {
      final xml = await _get(url);
      for (final m in RegExp(r'<Url\b[^>]*>', caseSensitive: false)
          .allMatches(xml)) {
        final tag = m.group(0)!;
        final type = _attr(tag, 'type') ?? '';
        if (!type.contains('atom') && !type.contains('xml')) continue;
        final tpl = _attr(tag, 'template');
        if (tpl != null && tpl.contains('searchTerms')) return tpl;
      }
    } catch (_) {}
    return null;
  }

  // ---------- 加入书架 ----------
  Future<void> _addToShelf(_OpdsEntry entry) async {
    final url = entry.downloadUrl;
    if (url == null) {
      _toast('该条目没有可直接下载的书籍文件');
      return;
    }
    final ext = _extOf(url);
    if (!ImportBookService.supported.contains(ext)) {
      _toast('暂不支持的文件类型：$ext');
      return;
    }
    setState(() {
      _downloadingTitle = entry.title;
      _downloadProgress = 0;
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final target = Directory(p.join(dir.path, 'import'));
      if (!await target.exists()) await target.create(recursive: true);
      final safe = entry.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File(p.join(
          target.path, '${safe}_${DateTime.now().millisecondsSinceEpoch}.$ext'));
      await _dio.download(
        url,
        file.path,
        options: Options(headers: _headers),
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _downloadProgress = received / total);
        },
      );
      final result = await ImportBookService().importPath(file.path);
      if (!mounted) return;
      setState(() {
        _downloadProgress = null;
        _downloadingTitle = null;
      });
      _toast('已加入书架：《${result.book.name}》（${result.chapterCount} 章）');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadProgress = null;
        _downloadingTitle = null;
      });
      _toast('下载失败：$e');
    }
  }

  String _extOf(String url) {
    try {
      final path = Uri.parse(url).path;
      if (!path.contains('.')) return '';
      return path.split('.').last.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showAuthDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OPDS 认证（Basic）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            TextField(
              controller: _pwdController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _toast('认证信息已保存，重新加载后生效');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _onTapEntry(_OpdsEntry entry) {
    if (entry.isNavigation && entry.navUrl != null) {
      _load(entry.navUrl!);
      return;
    }
    if (entry.downloadUrl != null) {
      showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(entry.title),
                subtitle: Text(entry.author ?? '未知作者'),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('下载并加入书架'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addToShelf(entry);
                },
              ),
              if (entry.navUrl != null)
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('打开详情（获取更多下载格式）'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _load(entry.navUrl!);
                  },
                ),
            ],
          ),
        ),
      );
      return;
    }
    if (entry.navUrl != null) {
      _load(entry.navUrl!);
      return;
    }
    _toast('该条目没有可访问的地址');
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final hasNext = _feed?.nextUrl != null;
    final hasPrev = _feed?.prevUrl != null || _stack.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(_feed?.title ?? 'OPDS 书源',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Basic 认证',
            onPressed: _showAuthDialog,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: '返回上一层',
            onPressed: _stack.isEmpty ? null : _goBack,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'OPDS 目录地址',
                      hintText: 'https://example.com/opds',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (v) => _load(v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _load(_urlController.text.trim()),
                  child: const Text('加载'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: '搜索',
                      hintText: '使用目录提供的 OpenSearch 接口',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _doSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.search), onPressed: _doSearch),
              ],
            ),
          ),
          if (_downloadingTitle != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(value: _downloadProgress),
                  ),
                  const SizedBox(width: 8),
                  const Text('下载中', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
          if (hasPrev || hasNext)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一页'),
                    onPressed: hasPrev
                        ? () {
                            final prev = _feed?.prevUrl;
                            if (prev != null) {
                              _load(prev, push: false);
                            } else {
                              _goBack();
                            }
                          }
                        : null,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一页'),
                    onPressed: hasNext ? () => _load(_feed!.nextUrl!) : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('加载失败：$_error',
            style: const TextStyle(color: Colors.red)),
      ));
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('暂无内容，请输入 OPDS 目录地址'));
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = _entries[i];
        return ListTile(
          leading: SizedBox(
            width: 40,
            height: 56,
            child: e.cover != null
                ? Image.network(
                    e.cover!,
                    fit: BoxFit.cover,
                    headers: _authImageHeaders(),
                    errorBuilder: (_, __, ___) => const Icon(Icons.book),
                  )
                : const Icon(Icons.book),
          ),
          title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e.author ?? '未知作者'}${e.updated != null ? ' · ${e.updated!.substring(0, e.updated!.length > 10 ? 10 : e.updated!.length)}' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (e.summary != null && e.summary!.isNotEmpty)
                Text(e.summary!, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
          isThreeLine: e.summary != null && e.summary!.isNotEmpty,
          trailing: e.isNavigation
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  icon: const Icon(Icons.download_for_offline_outlined),
                  tooltip: '下载并加入书架',
                  onPressed: () => _addToShelf(e),
                ),
          onTap: () => _onTapEntry(e),
        );
      },
    );
  }

  Map<String, String> _authImageHeaders() {
    final user = _userController.text.trim();
    if (user.isEmpty) return const <String, String>{};
    return _headers;
  }
}
