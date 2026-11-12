/// 由 browser_screen.dart 按「一类一文件」拆出的 _BrowserScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../browser_screen.dart';


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

  /// data: URI 解码得到的 HTML；非空表示这是一个「自包含页面」，
  /// 需用 loadData 加载（WebUri 会把 base64 里的 + / = 二次编码导致空白页）。
  String _initialDataHtml = '';
  /// 自包含页面的基准地址。用 about:blank 会让页面处于 opaque origin，
  /// `history.replaceState('#config=...')` 与 `document.cookie` 都会静默
  /// 失败，书源设置页的三条结果回传通道因此只剩 DOM 一条。改用页面中
  /// 出现的真实服务器域名，页面即可正常写 hash 与 Cookie。
  late final String _dataBaseUrl;
  /// 地址栏友好显示文本（data: 页不暴露超长 base64）。
  late final String _displayUrl;
  /// 防止「完成 / 系统返回」重复触发 pop。
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    // 书源常用 java.startBrowser('data:text/html;base64,' + base64(html), title)
    // 展示「使用教程 / 更新书源 / 设置中心」等自包含页面。能正常渲染，
    // 这里在 Dart 侧把 data URI 解码成 HTML，避免 WebUri 破坏 base64。
    // 书源可直接给出页面 HTML，此时优先渲染它；否则解析 data: URI。
    final given = widget.initialHtml;
    _initialDataHtml = (given != null && given.isNotEmpty)
        ? given
        : (_decodeDataHtml(widget.url) ?? '');
    final isData = _initialDataHtml.isNotEmpty;
    _dataBaseUrl = isData ? _pageOrigin(_initialDataHtml) : '';
    _displayUrl = isData
        ? ((widget.title ?? '').trim().isEmpty ? '书源页面' : widget.title!.trim())
        : widget.url;
    _tabs.add(_BrowserTab(_displayUrl, widget.title ?? _displayUrl));
    _urlController.text = _displayUrl;
  }

  /// 从自包含页面里提取一个可用的 http(s) 源，作为 loadData 的 baseUrl。
  /// 书源设置页内嵌了服务器列表（`https://v5.langge.uk` 等）与注入的
  /// state.server，取第一个合法 https/http 地址即可给页面一个非 opaque
  /// 的源；找不到时退回 about:blank，不影响原有渲染。
  static String _pageOrigin(String html) {
    final m = RegExp(r'https?://[A-Za-z0-9.\-]+(?::\d+)?')
        .firstMatch(html);
    if (m == null) return 'about:blank';
    final base = m.group(0)!;
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) return 'about:blank';
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/';
  }

  /// 解析 `data:text/html[;charset=..][;base64],<payload>` 为 HTML 字符串。
  /// 非 data: 或非 HTML 类型返回 null（交给常规 loadUrl）。
  static String? _decodeDataHtml(String raw) {
    if (!raw.toLowerCase().startsWith('data:')) return null;
    final comma = raw.indexOf(',');
    if (comma < 0) return null;
    final header = raw.substring(5, comma).toLowerCase();
    // 仅处理 text/html（含缺省 mime 的 data:;base64,..），避免误伤普通 data:
    if (header.contains('/') && !header.startsWith('text/html')) return null;
    final payload = raw.substring(comma + 1);
    try {
      if (header.contains(';base64')) {
        // 兼容 URL-safe base64 与含换行的编码
        final normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
        final padded = normalized.padRight(
            (normalized.length + 3) ~/ 4 * 4, '=');
        return utf8.decode(base64Decode(padded), allowMalformed: true);
      }
      // 百分号编码：+ 号是空格，需先还原再 decode
      return Uri.decodeComponent(payload.replaceAll('+', ' '));
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  _BrowserTab get _tab => _tabs[_activeTab];

  /// 交互登录模式退出：取「渲染后的整页 DOM」后带值 pop（供书源 JS 使用）。
  ///
  /// 书源设置中心一类页面在运行时会把用户选择写进
  /// `<script id="source-settings-(final-)result">`、`location.hash` 的
  /// `#config=` 或 Cookie。因此回传的必须是当前渲染后的 DOM，而不是
  /// [_initialDataHtml] 那份原始 HTML —— 否则书源用正则读到的永远是
  /// 空结果，表现为「改了跟没改一样 / 未读取到设置结果」。
  ///
  /// 用超时 + 防重入兜底：WebView 未就绪时取 DOM 可能挂起，无论成功
  /// 与否都必须 pop，避免「完成 / 系统返回」点了没反应。
  Future<void> _exitCapture() async {
    if (_exiting) return;
    _exiting = true;
    var html = '';
    var finalUrl = _displayUrl;
    var cookies = '';

    // 1) 当前页面最终地址（含运行期 hash）。data: 页用 location.href，
    //    普通页优先 WebView 的 url。
    try {
      final href = await _controller
          ?.evaluateJavascript(source: 'location.href')
          .timeout(const Duration(seconds: 2));
      final decoded = _decodeJsString(href);
      if (decoded.isNotEmpty &&
          !decoded.startsWith('about:blank') &&
          !decoded.startsWith('data:')) {
        finalUrl = decoded;
      }
    } catch (_) {}
    if (finalUrl == _displayUrl) {
      try {
        final u = await _controller?.getUrl().timeout(const Duration(seconds: 2));
        final s = u?.toString() ?? '';
        if (s.isNotEmpty &&
            !s.startsWith('about:blank') &&
            !s.startsWith('data:')) {
          finalUrl = s;
        }
      } catch (_) {}
    }

    // 2) 渲染后的整页 DOM —— 结果 script 标签的内容在这里才会出现。
    try {
      final raw = await _controller
          ?.evaluateJavascript(source: 'document.documentElement.outerHTML')
          .timeout(const Duration(seconds: 3));
      final decoded = _decodeJsString(raw);
      if (decoded.isNotEmpty) html = decoded;
    } catch (_) {}
    if (html.isEmpty) {
      try {
        final raw = await _controller
            ?.getHtml()
            .timeout(const Duration(seconds: 2));
        if (raw != null && raw.isNotEmpty) html = raw;
      } catch (_) {}
    }
    // 3) 页面 Cookie（书源设置结果也可能走 Cookie 通道）。
    try {
      final raw = await _controller
          ?.evaluateJavascript(source: 'document.cookie')
          .timeout(const Duration(seconds: 2));
      cookies = _decodeJsString(raw);
    } catch (_) {}
    if (cookies.isEmpty) {
      try {
        final list = await CookieManager.instance()
            .getCookies(url: WebUri(finalUrl))
            .timeout(const Duration(seconds: 2));
        cookies = list
            .where((c) => c.name.isNotEmpty && c.value != null)
            .map((c) => '${c.name}=${c.value}')
            .join('; ');
      } catch (_) {}
    }

    // 4) WebView 未就绪时兜底：至少回传原始 HTML，并补上最终 URL 的 hash，
    //    让书源的 URL 通道仍有机会拿到结果。
    if (html.isEmpty) html = _initialDataHtml;
    if (!mounted) return;
    Navigator.pop(
        context,
        BrowserCaptureResult(
            html: html, finalUrl: finalUrl, cookies: cookies));
  }

  /// 还原 evaluateJavascript 返回的 JSON 字符串（带引号 + 转义）。
  String _decodeJsString(dynamic raw) {
    if (raw == null) return '';
    var s = raw.toString().trim();
    if (s.isEmpty || s == 'null' || s == 'undefined') return '';
    if (s.startsWith('"') && s.endsWith('"') && s.length > 1) {
      try {
        final v = jsonDecode(s);
        return v?.toString() ?? '';
      } catch (_) {
        return s.substring(1, s.length - 1);
      }
    }
    return s;
  }

  // ---------- 基础导航 ----------
  static String _normalize(String url) {
    final target = url.trim();
    // http(s) 与 data:/javascript: 等带 scheme 的地址原样加载
    // （书源 java.startBrowserAwait(base64, ...) 会传 data:text/html 地址）
    if (target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('data:') ||
        target.startsWith('javascript:')) {
      return target;
    }
    return 'https://$target';
  }

  void _load(String url) {
    if (url.trim().isEmpty) return;
    // data: 自包含页面：解码后 loadData，绕开 WebUri 对 base64 的二次编码。
    final dataHtml = _decodeDataHtml(url);
    if (dataHtml != null) {
      setState(() {
        _urlController.text = (widget.title ?? '').trim().isEmpty
            ? '书源页面'
            : widget.title!.trim();
        _sniffResult = null;
      });
      _controller?.loadData(
          data: dataHtml, mimeType: 'text/html', encoding: 'utf-8');
      return;
    }
    final target = _normalize(url);
    setState(() {
      _tab.url = target;
      _urlController.text = target;
      _sniffResult = null;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  Future<void> _reload() async {
    // loadData 加载的自包含页面 reload() 常得到空内容，改为重新喂 HTML
    if (_initialDataHtml.isNotEmpty) {
      await _controller?.loadData(
          data: _initialDataHtml, mimeType: 'text/html', encoding: 'utf-8');
      return;
    }
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
                  tooltip: '关闭标签',
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

  // ---------- 多格式下载（按 MIME 保存 EPUB/PDF/图片/视频等） ----------
  static const Map<String, String> _mimeExt = <String, String>{
    'application/epub+zip': 'epub',
    'application/pdf': 'pdf',
    'text/plain': 'txt',
    'text/html': 'html',
    'application/json': 'json',
    'application/xml': 'xml',
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'video/mp4': 'mp4',
    'video/x-matroska': 'mkv',
    'video/webm': 'webm',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'application/zip': 'zip',
    'application/x-rar-compressed': 'rar',
    'application/octet-stream': 'bin',
  };
  static const Set<String> _knownExt = <String>{
    'epub', 'pdf', 'txt', 'html', 'htm', 'json', 'xml', 'jpg', 'jpeg', 'png',
    'gif', 'webp', 'mp4', 'mkv', 'webm', 'mp3', 'm4a', 'zip', 'cbz', 'rar',
    '7z', 'mobi', 'azw3',
  };

  /// 依据 URL 文件名与响应 Content-Type 推断保存扩展名。
  String _extensionFor(String mime, String name) {
    final dot = name.lastIndexOf('.');
    if (dot >= 0) {
      final e = name.substring(dot + 1).toLowerCase();
      if (_knownExt.contains(e)) return e;
    }
    final m = mime.toLowerCase().split(';').first.trim();
    final mapped = _mimeExt[m];
    if (mapped != null) return mapped;
    if (m.startsWith('image/')) return m.substring(6);
    if (m.startsWith('video/')) return m.substring(6);
    if (m.startsWith('audio/')) return m.substring(6);
    return 'bin';
  }

  /// 下载任意资源并按真实 MIME 落盘；随后可选择打开 / 分享（走 NativeBridge）。
  Future<void> _downloadAndSave(
    String url, {
    String? suggestedName,
    String? mimeHint,
  }) async {
    final target = _normalize(url);
    _toast('正在下载资源…');
    HttpClient? client;
    try {
      client = HttpClient();
      final uri = Uri.parse(target);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, _uaMobile);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final reported = resp.headers.contentType?.mimeType ?? '';
      final mime = (mimeHint != null && mimeHint.isNotEmpty)
          ? mimeHint
          : (reported.isNotEmpty ? reported : 'application/octet-stream');
      final bytes = await resp.fold<List<int>>(<int>[], (acc, chunk) {
        acc.addAll(chunk);
        return acc;
      });
      client.close();
      client = null;

      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      var baseName = (suggestedName != null && suggestedName.isNotEmpty)
          ? suggestedName
          : (segments.isNotEmpty ? segments.last : 'download');
      baseName = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final ext = _extensionFor(mime, baseName);
      if (!baseName.toLowerCase().endsWith('.$ext')) {
        baseName = '$baseName.$ext';
      }
      final dir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(dir.path, 'download'));
      if (!await targetDir.exists()) await targetDir.create(recursive: true);
      final file = File(p.join(targetDir.path,
          '${p.basenameWithoutExtension(baseName)}_${DateTime.now().millisecondsSinceEpoch}.$ext'));
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('资源已保存'),
          content: Text('$baseName\n${bytes.length} 字节 · $mime\n${file.path}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'save'),
                child: const Text('仅保存')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'open'),
                child: const Text('打开')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'share'),
                child: const Text('分享')),
          ],
        ),
      );
      if (action == 'open') {
        final ok =
            await NativeBridge.instance.openFile(file.path, mime: mime);
        _toast(ok ? '已请求外部应用打开' : '当前平台不支持外部打开，已保存到本地');
      } else if (action == 'share') {
        final ok = await NativeBridge.instance.shareFile(file.path,
            mime: mime, title: baseName);
        _toast(ok ? '已打开系统分享面板' : '当前平台不支持系统分享，已保存到本地');
      }
    } catch (e) {
      client?.close();
      _toast('下载失败：$e');
    }
  }

  /// 菜单入口：输入资源 URL（默认当前页），按格式保存。
  Future<void> _promptDownload() async {
    final ctl = TextEditingController(text: _tab.url);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载文件（多格式）'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(
            hintText: 'EPUB / PDF / 图片 / 视频等资源地址',
            labelText: '资源 URL',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('下载')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) {
      await _downloadAndSave(v.trim());
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

  /// 书源自包含 data: 页面（教程/更新日志/设置中心）的精简标题栏：
  /// 只读标题 + 完成/返回 + 刷新。对这些页面而言地址栏、前进后退、
  /// 嗅探、多标签都没有意义，反而暴露超长 base64、显得杂乱（图2）。
  PreferredSizeWidget _buildDataPageAppBar(BuildContext context, bool capture) {
    final title = (widget.title ?? '').trim().isEmpty
        ? '书源页面'
        : widget.title!.trim();
    return AppBar(
      automaticallyImplyLeading: !capture,
      leading: capture
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: _exitCapture,
            )
          : null,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        // 页面内跳转（气泡预览、教程链接等）后可退回主页面，避免
        // 「点进去就出不来」；没有历史时按钮禁用。
        IconButton(
          tooltip: '返回上一页',
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: _canGoBack ? _goBack : null,
        ),
        if (capture)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            child: FilledButton.icon(
              onPressed: _exitCapture,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
            ),
          ),
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh_outlined),
          onPressed: _reload,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final capture = widget.captureHtmlOnExit;
    final isDataPage = _initialDataHtml.isNotEmpty;
    final scaffold = Scaffold(
      // 书源自包含 data: 页面（教程/更新/设置中心）：精简标题栏，
      // 不再显示「前进/后退/嗅探/超长 base64 地址栏」这些无意义且丑的控件。
      appBar: isDataPage
          ? _buildDataPageAppBar(context, capture)
          : AppBar(
        automaticallyImplyLeading: !capture,
        leading: capture
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '完成并返回',
                onPressed: _exitCapture,
              )
            : null,
        title: Text(
          _tab.title.isEmpty ? '浏览器' : _tab.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (capture)
            FilledButton.icon(
              onPressed: _exitCapture,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
            ),
          IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh), onPressed: _reload),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '嗅探当前页',
            onPressed: _sniff,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
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
                case 'download_file':
                  await _promptDownload();
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
              const PopupMenuItem<String>(
                  value: 'download_file', child: Text('下载文件（多格式）')),
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
              tooltip: '后退',
              iconSize: 20,
              icon: const Icon(Icons.arrow_back),
              onPressed: _canGoBack ? () => _goBack() : null,
            ),
            IconButton(
              tooltip: '前进',
              iconSize: 20,
              icon: const Icon(Icons.arrow_forward),
              onPressed: _canGoForward ? () => _goForward() : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(fontSize: 13),
                  textInputAction: TextInputAction.go,
                  onSubmitted: _load,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
                    border: OutlineInputBorder(
                        borderRadius: AppRadius.mAll),
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
              tooltip: '标签页',
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
            // 自包含 data: 页面用 initialData 直接喂解码后的 HTML；
            // 否则走常规 URLRequest。两者互斥，避免 WebUri 破坏 base64。
            initialUrlRequest: _initialDataHtml.isEmpty
                ? URLRequest(url: WebUri(_normalize(widget.url)))
                : null,
            initialData: _initialDataHtml.isEmpty
                ? null
                : InAppWebViewInitialData(
                    data: _initialDataHtml,
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                    // 使用页面真实源，保证 location.hash / document.cookie
                    // 可用（书源设置页的结果回传依赖这两条通道）。
                    baseUrl: WebUri(_dataBaseUrl),
                  ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              useShouldOverrideUrlLoading: true,
              useOnDownloadStart: true,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              userAgent: _uaMobile,
              blockNetworkImage: _noImage,
              loadsImagesAutomatically: !_noImage,
            ),
            onWebViewCreated: (c) => _controller = c,
            // 页面内跳转：http(s)/data:/about:blank 放行；其它自定义 scheme
            // （legado://、书源内部协议等）提示用外部应用打开。此前开启了
            // useShouldOverrideUrlLoading 却未注册回调，页面里的链接点击
            // 会进入空白页且无法返回。
            shouldOverrideUrlLoading: (c, action) async {
              final uri = action.request.url;
              if (uri == null) return NavigationActionPolicy.CANCEL;
              final scheme = uri.scheme.toLowerCase();
              if (scheme == 'http' ||
                  scheme == 'https' ||
                  scheme == 'data' ||
                  scheme == 'about' ||
                  scheme == 'javascript' ||
                  scheme == 'file') {
                return NavigationActionPolicy.ALLOW;
              }
              final external = uri.toString();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('跳转到其它应用：$external'),
                  duration: const Duration(seconds: 4),
                  action: SnackBarAction(
                    label: '打开',
                    onPressed: () async {
                      final u = Uri.tryParse(external);
                      if (u != null && await canLaunchUrl(u)) {
                        await launchUrl(u,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ));
              }
              return NavigationActionPolicy.CANCEL;
            },
            // 点击 EPUB/PDF/图片/视频等下载链接时，按真实 MIME 拦截并落盘，
            // 随后可打开/分享（走 NativeBridge）。
            onDownloadStartRequest: (c, req) {
              _downloadAndSave(
                req.url.toString(),
                suggestedName: req.suggestedFilename,
                mimeHint: req.mimeType,
              );
            },
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
                // data: 自包含页面保持友好标题，不把超长 base64 写回地址栏
                if (_initialDataHtml.isEmpty && current != null) {
                  _tab.url = current.toString();
                }
              });
              // 自动嗅探（书源 JSON / 书籍详情页）
              await _sniff();
            },
          ),
        ),
        if (_sniffResult != null && !_sniffResult!.isEmpty) _buildSniffBar(),
      ]),
    );
    if (!capture) return scaffold;
    // 交互登录模式：拦截系统返回，统一走 _exitCapture 回传 HTML
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitCapture();
      },
      child: scaffold,
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
        child: Row(
          children: [
            const Icon(Icons.travel_explore, size: 18),
            const SizedBox(width: AppSpacing.s),
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
              tooltip: '关闭',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _sniffResult = null),
            ),
          ],
        ),
      ),
    );
  }
}
