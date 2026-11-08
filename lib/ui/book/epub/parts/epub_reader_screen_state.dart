/// 由 epub_reader_screen.dart 按「一类一文件」拆出的 _EpubReaderScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../epub_reader_screen.dart';


class _EpubReaderScreenState extends State<EpubReaderScreen> {
  final DatabaseService _db = DatabaseService();

  epub.EpubBook? _epub;
  List<_SpineItem> _spine = const [];
  Map<int, _FragmentIds> _fragments = const {};

  int _chapter = 0;
  bool _loading = true;
  String? _error;
  InAppWebViewController? _controller;

  double _fontSize = 18;
  double _scrollY = 0;
  double _pendingScrollY = 0;
  String? _pendingFragment;
  Timer? _saveTimer;

  String get _progressKey =>
      'epub_progress_${widget.book.name}_${widget.book.author}';

  static final WebUri _base = WebUri('https://epub.local/');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_savePosition(force: true));
    super.dispose();
  }

  Future<void> _load() async {
    final path = EpubReaderScreen.localPathOf(widget.book);
    if (path == null) {
      setState(() {
        _loading = false;
        _error = '未找到本地 EPUB 文件（Book.fileName / bookUrl / noteUrl 均不是可读路径）';
      });
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final book = await epub.EpubReader.readBook(bytes);
      _epub = book;
      _spine = _buildSpine(book);
      if (_spine.isEmpty) {
        throw StateError('EPUB 中未找到可阅读的 XHTML 章节');
      }
      await _loadFragments();
      await _restoreProgress();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'EPUB 打开失败：$e';
      });
    }
  }

  List<_SpineItem> _buildSpine(epub.EpubBook book) {
    final htmlMap =
        book.Content?.Html ?? const <String, epub.EpubTextContentFile>{};
    String htmlFor(String name) {
      if (name.isEmpty) return '';
      final clean = name.split('#').first;
      for (final e in htmlMap.entries) {
        if (e.key == clean || p.basename(e.key) == p.basename(clean)) {
          return e.value.Content ?? '';
        }
      }
      return '';
    }

    final out = <_SpineItem>[];
    void walk(List<epub.EpubChapter>? chapters) {
      for (final c in chapters ?? <epub.EpubChapter>[]) {
        final ref = c.ContentFileName ?? '';
        final fileKey = ref.split('#').first;
        var html = htmlFor(fileKey);
        if (html.trim().isEmpty) html = c.HtmlContent ?? '';
        if (html.trim().isNotEmpty) {
          final anchor = (c.Anchor ?? '').isNotEmpty
              ? c.Anchor
              : (ref.contains('#') ? ref.split('#').last : null);
          out.add(_SpineItem(
            title: (c.Title ?? '').trim().isNotEmpty
                ? c.Title!.trim()
                : '第 ${out.length + 1} 节',
            html: html,
            anchor: anchor,
            fileKey: fileKey,
          ));
        }
        walk(c.SubChapters);
      }
    }

    walk(book.Chapters);
    if (out.isEmpty) {
      final keys = htmlMap.keys.toList()..sort();
      for (final k in keys) {
        final html = htmlFor(k);
        if (html.trim().isNotEmpty) {
          out.add(_SpineItem(
              title: p.basenameWithoutExtension(k), html: html, fileKey: k));
        }
      }
    }
    return out;
  }

  /// 读取 v14 补列的 `startFragmentId / endFragmentId`（BookChapter 模型未暴露，直接查表）。
  Future<void> _loadFragments() async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'book_chapters',
        columns: ['chapter_index', 'startFragmentId', 'endFragmentId'],
        where: 'bookName = ? AND bookAuthor = ?',
        whereArgs: [widget.book.name, widget.book.author],
      );
      _fragments = <int, _FragmentIds>{
        for (final r in rows)
          (r['chapter_index'] as int? ?? 0): _FragmentIds(
            start: r['startFragmentId']?.toString(),
            end: r['endFragmentId']?.toString(),
          ),
      };
    } catch (_) {
      _fragments = const {};
    }
  }

  Future<void> _restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    if (raw != null && raw.contains('|')) {
      final parts = raw.split('|');
      _chapter = (int.tryParse(parts[0]) ?? 0).clamp(0, _spine.length - 1);
      _pendingScrollY = double.tryParse(parts[1]) ?? 0;
    } else {
      _chapter = widget.initialChapter.clamp(0, _spine.length - 1);
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => _savePosition());
  }

  Future<void> _savePosition({bool force = false}) async {
    if (_loading || _spine.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _progressKey, '$_chapter|${_scrollY.toStringAsFixed(0)}');
      await BookProgressSync.instance.record(widget.book,
          chapterIndex: _chapter, pagePos: _scrollY.toInt());
    } catch (_) {}
  }

  String _extractBody(String raw) {
    final bodyMatch =
        RegExp(r'<body[^>]*>([\s\S]*?)</body>', caseSensitive: false)
            .firstMatch(raw);
    final body = bodyMatch != null ? bodyMatch.group(1) ?? raw : raw;
    final headStyles = RegExp(
            r'<style[^>]*>([\s\S]*?)</style>',
            caseSensitive: false)
        .allMatches(raw)
        .map((m) => m.group(1) ?? '')
        .join('\n');
    return '$headStyles\n$body';
  }

  String _collectCss() {
    final sb = StringBuffer()
      ..writeln(
          'html,body{margin:0;padding:16px;line-height:1.75;word-wrap:break-word;}')
      ..writeln('img{max-width:100%;height:auto;}')
      ..writeln('body{font-size:${_fontSize.toStringAsFixed(0)}px;}');
    _epub?.Content?.Css?.forEach((_, v) {
      final c = v.Content;
      if (c != null && c.isNotEmpty) sb.writeln(c);
    });
    return sb.toString();
  }

  String _inlineImages(String html) {
    final images = _epub?.Content?.Images;
    if (images == null || images.isEmpty) return html;
    final byBase = <String, Uint8List>{};
    images.forEach((key, v) {
      final bytes = v.Content;
      if (bytes != null && bytes.isNotEmpty) {
        byBase[p.basename(key).toLowerCase()] =
            Uint8List.fromList(List<int>.from(bytes));
      }
    });
    return html.replaceAllMapped(
      RegExp(r'''(<img\b[^>]*?\bsrc\s*=\s*)(["'])([^"']+)\2''',
          caseSensitive: false),
      (m) {
        final src = m.group(3) ?? '';
        if (src.startsWith('data:') || src.startsWith('http')) {
          return m.group(0)!;
        }
        final base =
            p.basename(Uri.decodeFull(src.split('?').first)).toLowerCase();
        final data = byBase[base];
        if (data == null) return m.group(0)!;
        final ext = p.extension(base).toLowerCase();
        final mime = ext == '.png'
            ? 'image/png'
            : (ext == '.gif' ? 'image/gif' : 'image/jpeg');
        return '${m.group(1)}${m.group(2)}data:$mime;base64,${base64Encode(data)}${m.group(2)}';
      },
    );
  }

  static String _safeId(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  String _buildFullHtml(int index) {
    final item = _spine[index];
    final ids = _fragments[index];
    final startId = (ids?.start ?? '').isNotEmpty ? ids!.start : null;
    final endId = ids?.end;
    final target = _pendingFragment ?? startId ?? item.anchor;
    _pendingFragment = null;

    final title = item.title
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final body = _inlineImages(_extractBody(item.html));
    final endAnchor = (endId != null && endId.isNotEmpty)
        ? '<div id="${_safeId(endId)}" data-epub-end="1"></div>'
        : '';
    final targetJs = jsonEncode(target ?? '');
    final restoreJs = _pendingScrollY.toStringAsFixed(0);
    final script = '''
(function(){
  function report(){
    try { window.flutter_inappwebview && window.flutter_inappwebview.callHandler('EpubScroll', window.scrollY||window.pageYOffset||0); } catch(e){}
  }
  window.addEventListener('scroll', report, {passive:true});
  function ready(){
    var t = $targetJs;
    if (t) { var el = document.getElementById(t); if (el) el.scrollIntoView(); }
    else { var r = $restoreJs; if (r > 0) window.scrollTo(0, r); }
    report();
  }
  if (document.readyState === 'loading') window.addEventListener('DOMContentLoaded', ready);
  else ready();
})();
''';
    return '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
        '<style>${_collectCss()}</style></head><body>'
        '<h2 class="epub-chapter-title">$title</h2>$body$endAnchor'
        '<script>$script</script></body></html>';
  }

  Future<void> _goChapter(int index) async {
    if (index < 0 || index >= _spine.length) return;
    await _savePosition(force: true);
    _scrollY = 0;
    _pendingScrollY = 0;
    setState(() => _chapter = index);
    final html = _buildFullHtml(index);
    final c = _controller;
    if (c != null) {
      await c.loadData(
          data: html,
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: _base);
    }
    await _savePosition(force: true);
  }

  Future<void> _eval(String source) async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.evaluateJavascript(source: source);
    } catch (_) {}
  }

  void _handleHref(String href) {
    if (href.isEmpty) return;
    if (href.startsWith('#')) {
      final id = href.substring(1);
      final ids = _fragments[_chapter];
      // 章末 fragment：推进到下一章
      if (ids?.end == id) {
        unawaited(_goChapter(_chapter + 1));
        return;
      }
      unawaited(_eval(
          'var el=document.getElementById(${jsonEncode(id)});if(el)el.scrollIntoView();'));
      return;
    }
    for (var i = 0; i < _spine.length; i++) {
      final key = _spine[i].fileKey ?? '';
      if (key.isEmpty) continue;
      final hrefFile = href.split('#').first;
      if (href.contains(key) || p.basename(hrefFile) == p.basename(key)) {
        if (href.contains('#')) _pendingFragment = href.split('#').last;
        unawaited(_goChapter(i));
        return;
      }
    }
  }

  void _setFontSize(double v) {
    setState(() => _fontSize = v.clamp(12.0, 32.0));
    unawaited(_eval(
        "document.body.style.fontSize='${_fontSize.toStringAsFixed(0)}px';"));
  }

  void _showToc() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('目录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _spine.length,
              itemBuilder: (ctx, i) => ListTile(
                dense: true,
                selected: i == _chapter,
                title: Text(_spine[i].title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(c);
                  unawaited(_goChapter(i));
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _showDisplaySheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setLocal) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('阅读设置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: [
                const Text('正文字号'),
                Expanded(
                  child: Slider(
                    value: _fontSize,
                    min: 12,
                    max: 32,
                    divisions: 20,
                    label: _fontSize.toStringAsFixed(0),
                    onChanged: (v) {
                      setLocal(() {});
                      _setFontSize(v);
                    },
                  ),
                ),
                Text(_fontSize.toStringAsFixed(0)),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _switchToTextReader() async {
    await _savePosition(force: true);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ReadingScreen(
          book: widget.book,
          initialChapter: _chapter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_outlined),
            tooltip: '目录',
            onPressed: _loading ? null : _showToc,
          ),
          IconButton(
            icon: const Icon(Icons.text_format_outlined),
            tooltip: '阅读设置',
            onPressed: _loading ? null : _showDisplaySheet,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'text') unawaited(_switchToTextReader());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'text', child: Text('切换到通用文本阅读器')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorState(
                  message: _error!,
                  onRetry: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
                )
              : Column(
                  children: [
                    Expanded(
                      child: InAppWebView(
                        key: const ValueKey('epub_webview'),
                        initialData: InAppWebViewInitialData(
                          data: _buildFullHtml(_chapter),
                          mimeType: 'text/html',
                          encoding: 'utf-8',
                          baseUrl: _base,
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          domStorageEnabled: true,
                          supportZoom: true,
                          builtInZoomControls: true,
                          useShouldOverrideUrlLoading: true,
                          verticalScrollBarEnabled: true,
                          horizontalScrollBarEnabled: false,
                          mixedContentMode:
                              MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                        ),
                        onWebViewCreated: (c) {
                          _controller = c;
                          c.addJavaScriptHandler(
                            handlerName: 'EpubScroll',
                            callback: (args) {
                              if (args.isNotEmpty && args.first is num) {
                                _scrollY = (args.first as num).toDouble();
                                _scheduleSave();
                              }
                              return null;
                            },
                          );
                        },
                        shouldOverrideUrlLoading: (c, action) async {
                          final url = action.request.url?.toString() ?? '';
                          if (url.isNotEmpty) _handleHref(url);
                          return NavigationActionPolicy.CANCEL;
                        },
                        onLoadStop: (c, url) async {
                          // 兜底：loadData 后脚本可能未执行，主动恢复一次滚动位置
                          try {
                            await c.evaluateJavascript(
                                source:
                                    'window.flutter_inappwebview && window.flutter_inappwebview.callHandler("EpubScroll", window.scrollY||0);');
                          } catch (_) {}
                        },
                      ),
                    ),
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        color: cs.surfaceContainerHighest,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous_outlined),
                              tooltip: '上一章',
                              onPressed: _chapter > 0
                                  ? () => unawaited(_goChapter(_chapter - 1))
                                  : null,
                            ),
                            Expanded(
                              child: Text(
                                '${_chapter + 1} / ${_spine.length} · ${_spine[_chapter].title}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 12),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_outlined),
                              tooltip: '下一章',
                              onPressed: _chapter < _spine.length - 1
                                  ? () => unawaited(_goChapter(_chapter + 1))
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
