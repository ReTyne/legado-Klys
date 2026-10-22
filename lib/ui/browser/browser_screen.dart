import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';

/// 内置浏览器 - 对齐原版 WebViewActivity：
/// 地址栏 + 前进后退刷新 + 多标签 + UA 切换 + 无图模式 +
/// 书源/书籍嗅探 + 保存网页为 txt + 快捷导航。
class BrowserScreen extends StatefulWidget {
  final String url;
  final String? title;
  const BrowserScreen({super.key, required this.url, this.title});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

/// 一个标签页
class _BrowserTab {
  String url;
  String title;
  _BrowserTab(this.url, this.title);
}

/// 嗅探结果
class _SniffResult {
  final List<Map<String, dynamic>> sources;
  final String? sourceUrl; // 页面内发现的可疑书源订阅链接
  final String? bookUrl; // 匹配到 bookUrlPattern 的书籍详情页
  final String? bookSourceUrl;
  _SniffResult({this.sources = const [], this.sourceUrl, this.bookUrl, this.bookSourceUrl});

  bool get isEmpty =>
      sources.isEmpty && sourceUrl == null && bookUrl == null;
}

const String _uaDesktop =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
const String _uaMobile =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

/// 快捷导航（书城 / 源仓库）
const List<Map<String, String>> _quickLinks = <Map<String, String>>[
  {'name': '123书城', 'url': 'https://www.123du.cc/'},
  {'name': '阅读源仓库 GitHub', 'url': 'https://github.com/gedoor/legado'},
  {'name': '阅读官网', 'url': 'https://gedoor.github.io/'},
  {
    'name': '搜索书源订阅',
    'url': 'https://github.com/search?q=legado+%E4%B9%A6%E6%BA%90&type=repositories'
  },
];

class _BrowserScreenState extends State<BrowserScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  InAppWebViewController? _controller;
  final TextEditingController _urlController = TextEditingController();
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _desktopUa = false;
  bool _noImage = false;
  bool _sniffing = false;
  _SniffResult? _sniffResult;

  final List<_BrowserTab> _tabs = <_BrowserTab>[];
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    _tabs.add(_BrowserTab(widget.url, widget.title ?? widget.url));
    _urlController.text = widget.url;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  _BrowserTab get _tab => _tabs[_activeTab];

  // ---------- 基础导航 ----------
  static String _normalize(String url) {
    final target = url.trim();
    if (target.startsWith('http://') || target.startsWith('https://')) {
      return target;
    }
    return 'https://$target';
  }

  void _load(String url) {
    if (url.trim().isEmpty) return;
    final target = _normalize(url);
    setState(() {
      _tab.url = target;
      _urlController.text = target;
      _sniffResult = null;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  Future<void> _reload() async {
    await _controller?.reload();
  }

  Future<void> _goBack() async {
    if (!await _controller!.canGoBack()) return;
    await _controller!.goBack();
  }

  Future<void> _goForward() async {
    if (!await _controller!.canGoForward()) return;
    await _controller!.goForward();
  }

  // ---------- 设置（UA / 无图） ----------
  Future<void> _setDesktopUa(bool v) async {
    setState(() => _desktopUa = v);
    await _controller?.setSettings(
      settings: InAppWebViewSettings(userAgent: v ? _uaDesktop : _uaMobile),
    );
    await _reload();
  }

  Future<void> _setNoImage(bool v) async {
    setState(() => _noImage = v);
    await _controller?.setSettings(
      settings: InAppWebViewSettings(
        blockNetworkImage: v,
        loadsImagesAutomatically: !v,
      ),
    );
    await _reload();
  }

  // ---------- 多标签 ----------
  void _newTab([String? url]) {
    final target = url ?? 'https://www.baidu.com';
    setState(() {
      _tabs.add(_BrowserTab(target, target));
      _activeTab = _tabs.length - 1;
    });
    _load(target);
  }

  void _switchTab(int index) {
    if (index == _activeTab) {
      Navigator.pop(context);
      return;
    }
    setState(() => _activeTab = index);
    Navigator.pop(context);
    _load(_tabs[index].url);
  }

  void _closeTab(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;
      if (_tabs.isEmpty) {
        _tabs.add(_BrowserTab(widget.url, widget.title ?? widget.url));
        _activeTab = 0;
      }
    });
    Navigator.pop(context);
    if (index == _activeTab) _load(_tabs[_activeTab].url);
  }

  void _showTabs() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建标签'),
              onTap: () {
                Navigator.pop(ctx);
                _newTab();
              },
            ),
            const Divider(height: 1),
            ...List.generate(_tabs.length, (i) {
              final t = _tabs[i];
              return ListTile(
                selected: i == _activeTab,
                leading: Icon(i == _activeTab
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _closeTab(i),
                ),
                onTap: () => _switchTab(i),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------- 嗅探 ----------
  Future<String?> _currentHtml() async {
    if (_controller == null) return null;
    try {
      final html = await _controller!.getHtml();
      if (html != null && html.isNotEmpty) return html;
    } catch (_) {}
    try {
      final raw = await _controller!
          .evaluateJavascript(source: 'document.documentElement.outerHTML');
      if (raw is String && raw.isNotEmpty) {
        // Android 返回的是 JSON 字符串（带首尾引号与转义）
        var s = raw.trim();
        if (s.startsWith('"') && s.endsWith('"')) {
          s = jsonDecode(s).toString();
        }
        return s;
      }
    } catch (_) {}
    return null;
  }

  /// WebView 会把纯文本/JSON 包一层 <html><body><pre>，需还原原文
  String _plainText(String html) {
    var s = html;
    s = s.replaceAllMapped(
        RegExp(r'<pre[^>]*>([\s\S]*?)</pre>', caseSensitive: false),
        (m) => m.group(1) ?? '');
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = s
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
    return s.trim();
  }

  List<Map<String, dynamic>> _extractSources(dynamic decoded) {
    dynamic unwrapped = decoded;
    if (unwrapped is Map && !unwrapped.containsKey('bookSourceUrl')) {
      for (final key in [
        'data',
        'bookSources',
        'sources',
        'result',
        'list',
        'records'
      ]) {
        if (unwrapped[key] is List) {
          unwrapped = unwrapped[key];
          break;
        }
      }
    }
    final list = unwrapped is List ? unwrapped : <dynamic>[unwrapped];
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      if ((m['bookSourceUrl'] ?? '').toString().isEmpty) continue;
      out.add(m);
    }
    return out;
  }

  Future<void> _sniff() async {
    if (_sniffing) return;
    setState(() => _sniffing = true);
    try {
      final html = await _currentHtml();
      final text = html == null ? '' : _plainText(html);
      final url = _tab.url;

      final sources = <Map<String, dynamic>>[];
      if (text.startsWith('[') || text.startsWith('{')) {
        try {
          sources.addAll(_extractSources(jsonDecode(text)));
        } catch (_) {}
      }
      String? sourceUrl;
      if (sources.isEmpty) {
        final m = RegExp(r'''https?://[^\s"'<>\\]+\.json''').firstMatch(text);
        if (m != null) sourceUrl = m.group(0);
      }

      // 书籍：当前地址是否命中某个书源的 bookUrlPattern
      String? bookUrl;
      String? bookSourceUrl;
      final all = await _db.getAllSources(enabled: true);
      for (final s in all) {
        if (_engine.matchBookUrl(s, url)) {
          bookUrl = url;
          bookSourceUrl = s.bookSourceUrl;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _sniffing = false;
        _sniffResult = _SniffResult(
          sources: sources,
          sourceUrl: sourceUrl,
          bookUrl: bookUrl,
          bookSourceUrl: bookSourceUrl,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sniffing = false);
    }
  }

  Future<void> _importSniffedSources() async {
    final result = _sniffResult;
    if (result == null) return;
    var list = result.sources;
    if (list.isEmpty && result.sourceUrl != null) {
      list = await _fetchSources(result.sourceUrl!);
    }
    if (list.isEmpty) {
      _toast('未嗅探到可用书源');
      return;
    }
    int count = 0;
    for (final m in list) {
      try {
        final source = BookSource.fromJson(m);
        final exist = await _db.getSource(source.bookSourceUrl);
        if (exist != null) {
          await _db.updateSource(source);
        } else {
          await _db.insertSource(source);
        }
        count++;
      } catch (_) {}
    }
    _toast(count > 0 ? '已导入 $count 个书源' : '书源解析失败');
  }

  Future<List<Map<String, dynamic>>> _fetchSources(String url) async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _uaMobile);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      return _extractSources(jsonDecode(body.trim()));
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 嗅探书籍：用匹配到的书源取详情并加入书架
  Future<void> _sniffBook() async {
    final result = _sniffResult;
    if (result?.bookUrl == null || result?.bookSourceUrl == null) return;
    final source = await _db.getSource(result!.bookSourceUrl!);
    if (source == null) {
      _toast('未找到对应书源');
      return;
    }
    _toast('正在获取书籍信息…');
    try {
      final book = await _engine
          .getBookInfo(source, result.bookUrl!)
          .timeout(const Duration(seconds: 30));
      if (book == null) {
        _toast('未解析出书籍信息');
        return;
      }
      book.bookUrl = result.bookUrl;
      book.origin = source.bookSourceUrl;
      book.originName = source.bookSourceName;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('嗅探到书籍'),
          content: Text('《${book.name}》\n作者：${book.author}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('加入书架')),
          ],
        ),
      );
      if (ok != true) return;
      final exist = await _db.getBook(book.name, book.author);
      if (exist != null) {
        await _db.updateBook(book);
      } else {
        await _db.insertBook(book);
      }
      _toast('已加入书架：${book.name}');
    } catch (e) {
      _toast('嗅探失败：$e');
    }
  }

  // ---------- 保存网页为 txt ----------
  Future<void> _savePageAsTxt() async {
    final html = await _currentHtml();
    if (html == null || html.isEmpty) {
      _toast('无法读取网页内容');
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final target = Directory(p.join(dir.path, 'import'));
      if (!await target.exists()) await target.create(recursive: true);
      final name = _tab.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safe = name.isEmpty ? 'webpage' : name;
      final file = File(p.join(
          target.path, '${safe}_${DateTime.now().millisecondsSinceEpoch}.txt'));
      await file.writeAsString(_plainText(html), encoding: utf8);
      if (!mounted) return;
      final importIt = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('已保存为 TXT'),
          content: Text(file.path),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('仅保存')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('导入到书架')),
          ],
        ),
      );
      if (importIt != true) {
        _toast('已保存到导入目录');
        return;
      }
      final res = await ImportBookService().importPath(file.path);
      _toast('已导入《${res.book.name}》（${res.chapterCount} 章）');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tab.title.isEmpty ? '浏览器' : _tab.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _reload),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '嗅探当前页',
            onPressed: _sniff,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'ua_desktop':
                  await _setDesktopUa(!_desktopUa);
                  break;
                case 'no_image':
                  await _setNoImage(!_noImage);
                  break;
                case 'save_txt':
                  await _savePageAsTxt();
                  break;
                case 'copy':
                  Clipboard.setData(ClipboardData(text: _tab.url));
                  _toast('链接已复制');
                  break;
                case 'external':
                  launchUrl(Uri.parse(_tab.url),
                      mode: LaunchMode.externalApplication);
                  break;
                case 'share':
                  Share.share(_tab.url);
                  break;
                default:
                  if (v.startsWith('http')) _load(v);
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              CheckedPopupMenuItem<String>(
                value: 'ua_desktop',
                checked: _desktopUa,
                child: const Text('桌面版 UA'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'no_image',
                checked: _noImage,
                child: const Text('无图模式'),
              ),
              const PopupMenuItem<String>(
                  value: 'save_txt', child: Text('保存网页为 TXT')),
              const PopupMenuDivider(),
              ..._quickLinks.map((e) => PopupMenuItem<String>(
                    value: e['url'],
                    child: Text(e['name'] ?? ''),
                  )),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'copy', child: Text('复制链接')),
              const PopupMenuItem<String>(
                  value: 'external', child: Text('系统浏览器打开')),
              const PopupMenuItem<String>(value: 'share', child: Text('分享')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Row(children: [
            IconButton(
              iconSize: 20,
              icon: const Icon(Icons.arrow_back),
              onPressed: _canGoBack ? () => _goBack() : null,
            ),
            IconButton(
              iconSize: 20,
              icon: const Icon(Icons.arrow_forward),
              onPressed: _canGoForward ? () => _goForward() : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(fontSize: 13),
                  textInputAction: TextInputAction.go,
                  onSubmitted: _load,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Center(
                child: Text(
                  '${_tabs.length}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            IconButton(
              iconSize: 20,
              icon: const Icon(Icons.tab),
              onPressed: _showTabs,
            ),
          ]),
        ),
      ),
      body: Column(children: [
        if (_progress < 100)
          LinearProgressIndicator(value: _progress / 100, minHeight: 2),
        if (_sniffing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_normalize(widget.url))),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              useShouldOverrideUrlLoading: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              userAgent: _uaMobile,
              blockNetworkImage: _noImage,
              loadsImagesAutomatically: !_noImage,
            ),
            onWebViewCreated: (c) => _controller = c,
            onProgressChanged: (c, v) {
              if (mounted) setState(() => _progress = v);
            },
            onTitleChanged: (c, title) {
              if (!mounted || title == null || title.isEmpty) return;
              setState(() => _tab.title = title);
            },
            onLoadStart: (c, url) {
              if (!mounted || url == null) return;
              final u = url.toString();
              if (u.startsWith('http')) {
                setState(() {
                  _tab.url = u;
                  _urlController.text = u;
                  _sniffResult = null;
                });
              }
            },
            onLoadStop: (c, url) async {
              final back = await c.canGoBack();
              final fwd = await c.canGoForward();
              final current = await c.getUrl();
              if (!mounted) return;
              setState(() {
                _canGoBack = back;
                _canGoForward = fwd;
                if (current != null) _tab.url = current.toString();
              });
              // 自动嗅探（书源 JSON / 书籍详情页）
              await _sniff();
            },
          ),
        ),
        if (_sniffResult != null && !_sniffResult!.isEmpty) _buildSniffBar(),
      ]),
    );
  }

  Widget _buildSniffBar() {
    final r = _sniffResult!;
    final parts = <String>[];
    if (r.sources.isNotEmpty) parts.add('${r.sources.length} 个书源');
    if (r.sourceUrl != null) parts.add('书源订阅链接');
    if (r.bookUrl != null) parts.add('书籍详情页');
    return Material(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.travel_explore, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '嗅探到：${parts.join(' · ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (r.sources.isNotEmpty || r.sourceUrl != null)
              TextButton(
                onPressed: _importSniffedSources,
                child: const Text('导入书源'),
              ),
            if (r.bookUrl != null)
              TextButton(onPressed: _sniffBook, child: const Text('嗅探书籍')),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _sniffResult = null),
            ),
          ],
        ),
      ),
    );
  }
}
