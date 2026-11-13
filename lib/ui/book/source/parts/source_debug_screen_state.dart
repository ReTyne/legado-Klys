/// 由 source_debug_screen.dart 按「一类一文件」拆出的 _SourceDebugScreenState。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../source_debug_screen.dart';


class _SourceDebugScreenState extends State<SourceDebugScreen>
    with SingleTickerProviderStateMixin {
  final _keywordController = TextEditingController();
  final BookSourceEngine _engine = BookSourceEngine();
  final List<_LogLine> _logs = [];
  bool _running = false;
  double _progress = 0;

  // 各阶段原始源码
  String? _searchSrc;
  String? _bookSrc;
  String? _tocSrc;
  String? _contentSrc;

  // 页签：一键调试 / 分步调试 / 发现分类 / 请求响应 / 变量 / 原始源码
  late final TabController _tabController;
  // 分步调试各步骤状态
  final List<_DebugStep> _steps = [];
  bool _stepRunning = false;
  // 分步调试中间产物（供依赖步骤复用）
  SearchBook? _pickedBook;
  Book? _bookInfo;
  List<BookChapter> _tocChapters = [];

  // 发现分类
  List<Map<String, String>> _exploreKinds = [];
  bool _kindsLoading = false;
  String? _kindsError;
  int _selectedKind = 0;
  List<SearchBook> _exploreResults = [];
  bool _exploreRunning = false;
  String _exploreStatus = '';

  // 源变量 / 书籍变量编辑
  late final TextEditingController _sourceVarController;
  String? _originalVariable;
  static const Map<String, String> _bookVarLabels = {
    'bookUrl': '书籍地址 bookUrl',
    'name': '书名 name',
    'author': '作者 author',
    'tocUrl': '目录地址 tocUrl',
    'chapterTitle': '章节标题 title',
    'chapterUrl': '章节地址 url',
    'durChapterIndex': '章节索引 index',
  };
  final Map<String, TextEditingController> _bookVarCtl = {
    'bookUrl': TextEditingController(),
    'name': TextEditingController(),
    'author': TextEditingController(),
    'tocUrl': TextEditingController(),
    'chapterTitle': TextEditingController(),
    'chapterUrl': TextEditingController(),
    'durChapterIndex': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _originalVariable = widget.source.variable;
    _sourceVarController =
        TextEditingController(text: widget.source.variable ?? '');
    // 默认关键词：优先书源 ruleSearch.checkKeyWord（调试页推荐词），
    // 回退顶层 checkKeyWord，最后回退「我的」。
    _keywordController.text = _defaultKeyword(widget.source);
    _tabController = TabController(length: 6, vsync: this);
    _initSteps();
    _loadExploreKinds();
  }

  /// 调试页默认关键词（忽略明显不是关键词的值）
  static String _defaultKeyword(BookSource source) {
    for (final candidate in [
      source.effectiveCheckKeyWord,
    ]) {
      final v = candidate?.trim() ?? '';
      if (v.isEmpty) continue;
      final lower = v.toLowerCase();
      if (lower.contains('http') ||
          v.contains('::') ||
          v.contains('++') ||
          v.contains('--')) {
        continue;
      }
      return v;
    }
    return '我的';
  }

  /// 初始化分步调试的 5 个步骤
  void _initSteps() {
    _steps.addAll([
      _DebugStep('search', '搜索', Icons.search),
      _DebugStep('explore', '发现', Icons.explore_outlined),
      _DebugStep('info', '详情', Icons.menu_book_outlined),
      _DebugStep('toc', '目录', Icons.list_alt),
      _DebugStep('content', '正文', Icons.article_outlined),
    ]);
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _sourceVarController.dispose();
    for (final c in _bookVarCtl.values) {
      c.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  void _log(String message, {_LogLevel level = _LogLevel.info}) {
    setState(() {
      _logs.add(_LogLine(message, level));
    });
  }

  void _dumpEngineLog() {
    for (final l in _engine.debugLog.toList()) {
      _log('    $l', level: _LogLevel.detail);
    }
    _engine.clearDebugLog();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }

  void _copyText(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    _toast('已复制$what');
  }

  /// 解析调试输入，路由到对应阶段：
  ///  - `++url`      目录调试
  ///  - `--url`      正文调试
  ///  - `名称::url`   发现调试
  ///  - 绝对 URL     详情调试
  ///  - 其他         搜索调试
  ({String target, String url}) _parseDebugTarget(String input) {
    final t = input.trim();
    if (t.startsWith('++')) return (target: 'toc', url: t.substring(2).trim());
    if (t.startsWith('--')) return (target: 'content', url: t.substring(2).trim());
    final dc = t.indexOf('::');
    if (dc > 0) return (target: 'explore', url: t.substring(dc + 2).trim());
    if (RegExp(r'^https?://').hasMatch(t)) return (target: 'info', url: t);
    return (target: 'search', url: '');
  }

  Future<void> _runAll() async {
    final input = _keywordController.text.trim();
    if (input.isEmpty) {
      _log('请输入 搜索词 / 详情URL / ++目录URL / --正文URL / 发现::URL', level: _LogLevel.error);
      return;
    }
    // 每次调试只保留本次产生的请求（含 java.ajax 的原生拦截通道）
    SourceNetworkLog.instance.clear();
    setState(() {
      _running = true;
      _logs.clear();
      _searchSrc = null;
      _bookSrc = null;
      _tocSrc = null;
      _contentSrc = null;
      _progress = 0;
    });
    final source = widget.source;
    final parsed = _parseDebugTarget(input);
    _log('===== 开始调试：${source.bookSourceName} =====', level: _LogLevel.stage);
    _log('书源地址: ${source.bookSourceUrl}');
    _log('调试目标: ${parsed.target}${parsed.url.isNotEmpty ? '  ${parsed.url}' : ''}');

    try {
      switch (parsed.target) {
        case 'search':
          await _debugSearch(source, input);
          break;
        case 'explore':
          await _debugExplore(source, parsed.url);
          break;
        case 'info':
          await _debugInfo(source, parsed.url);
          break;
        case 'toc':
          await _debugToc(source, parsed.url);
          break;
        case 'content':
          await _debugContent(source, parsed.url);
          break;
      }
      _progress = 1;
      _log('===== 调试完成 =====', level: _LogLevel.stage);
      _finish(true);
    } catch (e) {
      _dumpEngineLog();
      _log('调试异常: $e', level: _LogLevel.error);
      _finish(false);
    }
  }

  /// 搜索 → 详情 → 目录 → 正文（全链路）
  Future<void> _debugSearch(BookSource source, String keyword) async {
    _progress = 0.1;
    _log('【搜索】「$keyword」…', level: _LogLevel.stage);
    final results = await _engine.search(source, keyword);
    _dumpEngineLog();
    _searchSrc = _engine.lastRawResponse;
    if (results.isEmpty) {
      _log('搜索结果为空（请检查 searchUrl / 登录 / 规则）', level: _LogLevel.error);
      return;
    }
    _log('搜索到 ${results.length} 本，前 3 本：', level: _LogLevel.ok);
    for (var i = 0; i < results.length && i < 3; i++) {
      final b = results[i];
      _log('  ${i + 1}. ${b.name} / ${b.author}  bookUrl=${b.bookUrl}');
    }
    final first = results.first;
    final detailUrl = first.bookUrl;
    if (detailUrl == null || detailUrl.isEmpty) {
      _log('首本书缺少 bookUrl', level: _LogLevel.error);
      return;
    }
    await _debugInfoInternal(source, detailUrl,
        presetName: first.name, presetAuthor: first.author);
  }

  /// 发现 → 详情 → 目录 → 正文
  Future<void> _debugExplore(BookSource source, String exploreUrl) async {
    _progress = 0.1;
    _log('【发现】$exploreUrl', level: _LogLevel.stage);
    final results = await _engine.exploreByUrl(source, exploreUrl);
    _dumpEngineLog();
    _searchSrc = _engine.lastRawResponse;
    if (results.isEmpty) {
      _log('发现结果为空（请检查 exploreUrl / ruleExplore）', level: _LogLevel.error);
      return;
    }
    _log('发现 ${results.length} 本，前 3 本：', level: _LogLevel.ok);
    for (var i = 0; i < results.length && i < 3; i++) {
      final b = results[i];
      _log('  ${i + 1}. ${b.name} / ${b.author}  bookUrl=${b.bookUrl}');
    }
    final first = results.first;
    final detailUrl = first.bookUrl;
    if (detailUrl == null || detailUrl.isEmpty) {
      _log('首本书缺少 bookUrl', level: _LogLevel.error);
      return;
    }
    await _debugInfoInternal(source, detailUrl,
        presetName: first.name, presetAuthor: first.author);
  }

  /// 详情（绝对 URL）→ 目录 → 正文
  Future<void> _debugInfo(BookSource source, String bookUrl) async {
    await _debugInfoInternal(source, bookUrl);
  }

  Future<void> _debugInfoInternal(BookSource source, String detailUrl,
      {String? presetName, String? presetAuthor}) async {
    _progress = 0.35;
    _log('【详情】$detailUrl', level: _LogLevel.stage);
    final info = await _engine.getBookInfo(source, detailUrl,
        presetName: presetName, presetAuthor: presetAuthor);
    _dumpEngineLog();
    _bookSrc = _engine.lastRawResponse;
    if (info == null) {
      _log('详情解析失败（ruleBookInfo）', level: _LogLevel.error);
      return;
    }
    _log('书名: ${info.name}  作者: ${info.author}', level: _LogLevel.ok);
    _log('分类: ${info.kind}  最新: ${info.lastChapter}');
    _log('目录地址: ${info.noteUrl}');
    await _debugTocInternal(source, info, detailUrl);
  }

  /// 目录（++url）→ 正文
  Future<void> _debugToc(BookSource source, String tocUrl) async {
    _progress = 0.6;
    _log('【目录】$tocUrl', level: _LogLevel.stage);
    final chapters = await _engine.getToc(source, tocUrl, bookInfo: {
      'bookUrl': tocUrl,
      'name': source.bookSourceName,
      'author': '',
      'tocUrl': tocUrl,
      'durChapterIndex': 0,
    });
    _dumpEngineLog();
    _tocSrc = _engine.lastRawResponse;
    if (chapters.isEmpty) {
      _log('目录为空（ruleToc.chapterList）', level: _LogLevel.error);
      return;
    }
    _log('目录共 ${chapters.length} 章，前 3 章：', level: _LogLevel.ok);
    for (var i = 0; i < chapters.length && i < 3; i++) {
      _log('  ${i + 1}. ${chapters[i].title} -> ${chapters[i].url}');
    }
    final firstChapter = chapters.firstWhere(
        (c) => c.url.isNotEmpty && !c.isVolume,
        orElse: () => chapters.first);
    await _debugContentInternal(source, firstChapter.url, {
      'bookUrl': tocUrl,
      'name': source.bookSourceName,
      'tocUrl': tocUrl,
      'durChapterIndex': firstChapter.index,
    }, {
      'index': firstChapter.index,
      'title': firstChapter.title,
      'url': firstChapter.url,
      'bookUrl': tocUrl,
    });
  }

  /// 目录（详情之后）→ 正文
  Future<void> _debugTocInternal(BookSource source, Book info, String detailUrl) async {
    final tocUrl = info.noteUrl ?? detailUrl;
    _progress = 0.6;
    _log('【目录】$tocUrl', level: _LogLevel.stage);
    final chapters = await _engine.getToc(source, tocUrl, bookInfo: {
      'bookUrl': info.bookUrl ?? detailUrl,
      'name': info.name,
      'author': info.author,
      'tocUrl': tocUrl,
      'durChapterIndex': 0,
    });
    _dumpEngineLog();
    _tocSrc = _engine.lastRawResponse;
    if (chapters.isEmpty) {
      _log('目录为空（ruleToc.chapterList）', level: _LogLevel.error);
      return;
    }
    _log('目录共 ${chapters.length} 章，前 3 章：', level: _LogLevel.ok);
    for (var i = 0; i < chapters.length && i < 3; i++) {
      _log('  ${i + 1}. ${chapters[i].title} -> ${chapters[i].url}');
    }
    final firstChapter = chapters.firstWhere(
        (c) => c.url.isNotEmpty && !c.isVolume,
        orElse: () => chapters.first);
    await _debugContentInternal(source, firstChapter.url, {
      'bookUrl': info.bookUrl,
      'name': info.name,
      'author': info.author,
      'tocUrl': info.noteUrl,
      'durChapterIndex': firstChapter.index,
    }, {
      'index': firstChapter.index,
      'title': firstChapter.title,
      'url': firstChapter.url,
      'bookUrl': info.bookUrl,
    });
  }

  /// 正文（--url）
  Future<void> _debugContent(BookSource source, String contentUrl) async {
    await _debugContentInternal(source, contentUrl, {
      'bookUrl': contentUrl,
      'name': source.bookSourceName,
      'tocUrl': '',
      'durChapterIndex': 0,
    }, {
      'index': 0,
      'title': '',
      'url': contentUrl,
      'bookUrl': contentUrl,
    });
  }

  Future<void> _debugContentInternal(BookSource source, String contentUrl,
      Map<String, dynamic> bookInfo, Map<String, dynamic> chapter) async {
    _progress = 0.8;
    _log('【正文】$contentUrl', level: _LogLevel.stage);
    final content = await _engine.getContent(source, contentUrl,
        bookInfo: bookInfo, chapter: chapter);
    _dumpEngineLog();
    _contentSrc = _engine.lastRawResponse;
    if (content == null || content.trim().isEmpty) {
      _log('正文为空（ruleContent.content）', level: _LogLevel.error);
      return;
    }
    final preview = content.length > 300 ? content.substring(0, 300) : content;
    _log('正文长度 ${content.length} 字符，预览：', level: _LogLevel.ok);
    _log(preview, level: _LogLevel.detail);
  }

  void _finish(bool ok) {
    if (mounted) setState(() => _running = false);
  }

  // ==================== 分步调试 ====================

  /// 从引擎调试日志中提取请求 URL（日志形如 "GET https://..."）
  List<String> _extractUrls(List<String> logs) {
    final urls = <String>[];
    for (final l in logs) {
      final m = RegExp(r'https?://\S+').firstMatch(l);
      if (m != null) {
        final u = m.group(0)!;
        if (!urls.contains(u)) urls.add(u);
      }
    }
    return urls;
  }

  /// 单独执行一个调试步骤，统计耗时并记录 URL / 摘要 / 引擎日志。
  /// 「详情 / 目录 / 正文」的地址可在「变量」页临时覆盖，覆盖值优先。
  Future<void> _runStep(_DebugStep step) async {
    if (_stepRunning || _running || _exploreRunning) return;
    final source = widget.source;
    final keyword = _keywordController.text.trim();
    if (step.key == 'search' && keyword.isEmpty) {
      setState(() {
        step.status = _StepStatus.fail;
        step.error = '请输入搜索关键词';
      });
      return;
    }
    setState(() {
      step.status = _StepStatus.running;
      step.error = null;
      step.url = '';
      step.summary = '';
      step.durationMs = 0;
      step.engineLogs = [];
      _stepRunning = true;
    });
    // 清空引擎日志，保证提取到的 URL 只属于本步
    _engine.clearDebugLog();
    final sw = Stopwatch()..start();
    try {
      switch (step.key) {
        case 'search':
          final results = await _engine.search(source, keyword);
          _pickedBook = results.isNotEmpty ? results.first : null;
          if (results.isEmpty) {
            throw Exception('搜索结果为空（请检查 searchUrl / 登录 / 规则）');
          }
          _fillBookVars(results.first, onlyEmpty: true);
          step.summary = '共 ${results.length} 本，前 5 本：\n${results
              .take(5)
              .map((b) => '  ${b.name} / ${b.author}')
              .join('\n')}';
          break;
        case 'explore':
          final kindUrl = _selectedKindUrl();
          if ((source.exploreUrl ?? '').trim().isEmpty && kindUrl.isEmpty) {
            throw Exception('书源未配置 exploreUrl / 发现分类');
          }
          final results = kindUrl.isNotEmpty
              ? await _engine.exploreByUrl(source, kindUrl)
              : await _engine.explore(source);
          _pickedBook = results.isNotEmpty ? results.first : null;
          if (results.isEmpty) {
            throw Exception('发现结果为空（请检查 exploreUrl / ruleExplore）');
          }
          _fillBookVars(results.first, onlyEmpty: true);
          step.summary = '共 ${results.length} 本，前 5 本：\n${results
              .take(5)
              .map((b) => '  ${b.name} / ${b.author}')
              .join('\n')}';
          break;
        case 'info':
          final book = _pickedBook;
          final bookUrl = _bookVar('bookUrl', book?.bookUrl ?? '');
          if (bookUrl.isEmpty) {
            throw Exception('请先执行「搜索」或「发现」，或在「变量」页填写书籍地址');
          }
          final pName = _bookVar('name', book?.name ?? '');
          final pAuthor = _bookVar('author', book?.author ?? '');
          final info = await _engine.getBookInfo(source, bookUrl,
              presetName: pName.isEmpty ? null : pName,
              presetAuthor: pAuthor.isEmpty ? null : pAuthor);
          if (info == null) throw Exception('详情解析失败（ruleBookInfo）');
          _bookInfo = info;
          step.url = bookUrl;
          step.summary = '书名: ${info.name}  作者: ${info.author}\n分类: ${info.kind}\n目录地址: ${info.noteUrl}';
          break;
        case 'toc':
          final info = _bookInfo;
          final tocUrl = _bookVar('tocUrl', info?.noteUrl ?? info?.bookUrl ?? '');
          if (tocUrl.isEmpty) {
            throw Exception('请先执行「详情」，或在「变量」页填写目录地址');
          }
          final chapters = await _engine.getToc(source, tocUrl, bookInfo: {
            'bookUrl': _bookVar('bookUrl', info?.bookUrl ?? ''),
            'name': _bookVar('name', info?.name ?? ''),
            'author': _bookVar('author', info?.author ?? ''),
            'tocUrl': tocUrl,
            'durChapterIndex': 0,
          });
          if (chapters.isEmpty) throw Exception('目录为空（ruleToc.chapterList）');
          _tocChapters = chapters;
          final first = chapters.firstWhere(
              (c) => c.url.isNotEmpty && !c.isVolume,
              orElse: () => chapters.first);
          _fillChapterVars(first, onlyEmpty: true);
          step.url = tocUrl;
          step.summary = '共 ${chapters.length} 章，前 3 章：\n${chapters
              .take(3)
              .map((c) => '  ${c.index + 1}. ${c.title} -> ${c.url}')
              .join('\n')}';
          break;
        case 'content':
          BookChapter? ch;
          if (_tocChapters.isNotEmpty) {
            ch = _tocChapters.firstWhere(
                (c) => c.url.isNotEmpty && !c.isVolume,
                orElse: () => _tocChapters.first);
          }
          final chapterUrl = _bookVar('chapterUrl', ch?.url ?? '');
          final chapterTitle = _bookVar('chapterTitle', ch?.title ?? '');
          if (chapterUrl.isEmpty) {
            throw Exception('请先执行「目录」，或在「变量」页填写章节地址');
          }
          final info = _bookInfo;
          final idxStr = _bookVar('durChapterIndex', '${ch?.index ?? 0}');
          final idx = int.tryParse(idxStr) ?? ch?.index ?? 0;
          final content = await _engine.getContent(source, chapterUrl, bookInfo: {
            'bookUrl': _bookVar('bookUrl', info?.bookUrl ?? ''),
            'name': _bookVar('name', info?.name ?? ''),
            'author': _bookVar('author', info?.author ?? ''),
            'tocUrl': _bookVar('tocUrl', info?.noteUrl ?? ''),
            'durChapterIndex': idx,
          }, chapter: {
            'index': idx,
            'title': chapterTitle,
            'url': chapterUrl,
            'bookUrl': info?.bookUrl,
          });
          if (content == null || content.trim().isEmpty) {
            throw Exception('正文为空（ruleContent.content）');
          }
          step.url = chapterUrl;
          final preview = content.length > 300 ? content.substring(0, 300) : content;
          step.summary = '正文长度 ${content.length} 字符，预览：\n$preview';
          break;
      }
      sw.stop();
      final urls = _extractUrls(_engine.debugLog);
      if (mounted) {
        setState(() {
          step.durationMs = sw.elapsedMilliseconds;
          step.status = _StepStatus.ok;
          if (step.url.isEmpty && urls.isNotEmpty) {
            step.url = urls.first;
          }
          step.engineLogs = _engine.debugLog.toList();
        });
      }
    } catch (e) {
      sw.stop();
      if (mounted) {
        setState(() {
          step.durationMs = sw.elapsedMilliseconds;
          step.status = _StepStatus.fail;
          step.error = e.toString().replaceFirst('Exception: ', '');
          step.engineLogs = _engine.debugLog.toList();
        });
      }
    } finally {
      if (mounted) setState(() => _stepRunning = false);
    }
  }

  /// 重置所有分步调试状态
  void _resetSteps() {
    for (final s in _steps) {
      s.status = _StepStatus.idle;
      s.durationMs = 0;
      s.url = '';
      s.summary = '';
      s.error = null;
      s.engineLogs = [];
    }
    _pickedBook = null;
    _bookInfo = null;
    _tocChapters = [];
  }

  /// 分步调试单个步骤卡片
  Widget _stepCard(_DebugStep step) {
    final colorScheme = Theme.of(context).colorScheme;
    Color statusColor;
    String statusText;
    switch (step.status) {
      case _StepStatus.idle:
        statusColor = colorScheme.onSurfaceVariant;
        statusText = '未执行';
        break;
      case _StepStatus.running:
        statusColor = colorScheme.primary;
        statusText = '执行中…';
        break;
      case _StepStatus.ok:
        statusColor = colorScheme.primary;
        statusText = '成功';
        break;
      case _StepStatus.fail:
        statusColor = colorScheme.error;
        statusText = '失败';
        break;
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(step.icon, size: 20),
                const SizedBox(width: AppSpacing.s),
                Text(step.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: AppSpacing.s),
                // 状态标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: AppRadius.mAll,
                  ),
                  child: Text(statusText,
                      style: TextStyle(color: statusColor, fontSize: 11)),
                ),
                const Spacer(),
                // 耗时统计（Stopwatch）
                if (step.durationMs > 0)
                  Text('${step.durationMs} ms',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace')),
                const SizedBox(width: AppSpacing.s),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('执行'),
                  onPressed:
                      (_stepRunning || _running || _exploreRunning) ? null : () => _runStep(step),
                ),
              ],
            ),
            // 请求 URL
            if (step.url.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              _stepField('请求 URL', step.url),
            ],
            // 返回摘要
            if (step.summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              _stepField('返回摘要', step.summary),
            ],
            // 错误信息
            if (step.error != null) ...[
              const SizedBox(height: 6),
              _stepField('错误', step.error!, error: true),
            ],
            // 引擎日志（可展开）
            if (step.engineLogs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('引擎日志（${step.engineLogs.length} 行）',
                    style: const TextStyle(fontSize: 12)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.s),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.mAll,
                    ),
                    child: SelectableText(
                      step.engineLogs.join('\n'),
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 步骤详情字段（标签 + 等宽文本）
  Widget _stepField(String label, String value, {bool error = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.35,
            fontFamily: 'monospace',
            color: error
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  /// 分步调试页签内容
  Widget _buildStepView() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xs),
          child: Text(
            '每步可单独执行并统计耗时；「详情 / 目录 / 正文」默认复用前序步骤结果，也可在「变量」页临时覆盖地址后直接执行。',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        ..._steps.map(_stepCard),
        const SizedBox(height: AppSpacing.l),
      ],
    );
  }

  // ==================== 发现分类 ====================

  /// 加载书源发现分类（支持 JS 动态生成的分类），刷新时先清缓存。
  Future<void> _loadExploreKinds({bool refresh = false}) async {
    if (_kindsLoading) return;
    setState(() {
      _kindsLoading = true;
      _kindsError = null;
    });
    try {
      if (refresh) await _engine.clearExploreKindsCache(widget.source);
      var kinds = await _engine.getExploreKindsAsync(widget.source);
      if (kinds.isEmpty) kinds = _engine.getExploreKinds(widget.source);
      if (!mounted) return;
      setState(() {
        _exploreKinds = kinds.where((k) => (k['url'] ?? '').isNotEmpty).toList();
        if (_selectedKind < 0 || _selectedKind >= _exploreKinds.length) {
          _selectedKind = 0;
        }
        _kindsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _kindsError = '$e';
        _kindsLoading = false;
      });
    }
  }

  /// 当前选中发现分类的地址（供分步调试「发现」步骤联动）
  String _selectedKindUrl() {
    if (_exploreKinds.isEmpty) return '';
    var i = _selectedKind;
    if (i < 0 || i >= _exploreKinds.length) i = 0;
    return _exploreKinds[i]['url'] ?? '';
  }

  /// 单独调试选中的发现分类
  Future<void> _runExploreKind() async {
    if (_exploreRunning || _running || _stepRunning) return;
    if (_exploreKinds.isEmpty) {
      _toast('没有可用的发现分类');
      return;
    }
    var i = _selectedKind;
    if (i < 0 || i >= _exploreKinds.length) i = 0;
    final kind = _exploreKinds[i];
    final title = kind['title'] ?? '未命名';
    final url = kind['url'] ?? '';
    if (url.isEmpty) {
      _toast('该分类没有有效地址');
      return;
    }
    SourceNetworkLog.instance.clear();
    _engine.clearDebugLog();
    setState(() {
      _exploreRunning = true;
      _exploreStatus = '正在调试分类「$title」…';
      _exploreResults = [];
    });
    final sw = Stopwatch()..start();
    _log('【发现·分类】$title  $url', level: _LogLevel.stage);
    try {
      final results = await _engine.exploreByUrl(widget.source, url);
      sw.stop();
      _dumpEngineLog();
      if (!mounted) return;
      setState(() {
        _exploreResults = results;
        _exploreRunning = false;
        _exploreStatus = results.isEmpty
            ? '分类「$title」未返回书籍（耗时 ${sw.elapsedMilliseconds}ms，请检查 exploreUrl / ruleExplore）'
            : '分类「$title」返回 ${results.length} 本，耗时 ${sw.elapsedMilliseconds}ms';
      });
      if (results.isEmpty) {
        _log('发现结果为空（耗时 ${sw.elapsedMilliseconds}ms）', level: _LogLevel.error);
      } else {
        _log('发现 ${results.length} 本，前 5 本：', level: _LogLevel.ok);
        for (var n = 0; n < results.length && n < 5; n++) {
          final b = results[n];
          _log('  ${n + 1}. ${b.name} / ${b.author}  bookUrl=${b.bookUrl}');
        }
      }
    } catch (e) {
      sw.stop();
      _dumpEngineLog();
      if (!mounted) return;
      setState(() {
        _exploreRunning = false;
        _exploreStatus = '调试异常: $e';
      });
      _log('发现分类调试异常: $e', level: _LogLevel.error);
    }
  }

  /// 把选中分类填入调试目标并跑「发现 → 详情 → 目录 → 正文」完整链路
  void _runExploreChain() {
    if (_exploreKinds.isEmpty) {
      _toast('没有可用的发现分类');
      return;
    }
    var i = _selectedKind;
    if (i < 0 || i >= _exploreKinds.length) i = 0;
    final kind = _exploreKinds[i];
    _keywordController.text = '${kind['title'] ?? ''}::${kind['url'] ?? ''}';
    _tabController.animateTo(0);
    _runAll();
  }

  /// 发现分类页签内容
  Widget _buildExploreView() {
    final cs = Theme.of(context).colorScheme;
    final hasKinds = _exploreKinds.isNotEmpty;
    int? selIdx;
    if (hasKinds) {
      selIdx = _selectedKind;
      if (selIdx < 0 || selIdx >= _exploreKinds.length) selIdx = 0;
    }
    final selectedUrl = selIdx == null ? '' : (_exploreKinds[selIdx]['url'] ?? '');
    final busy = _exploreRunning || _kindsLoading || _running || _stepRunning;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('按分类调试发现页',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  '选择书源配置的发现分类，可单独跑该分类，或把分类填入调试目标串起「发现 → 详情 → 目录 → 正文」完整链路。',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.m),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: selIdx,
                        hint: const Text('暂无发现分类', style: TextStyle(fontSize: 13)),
                        items: [
                          for (var i = 0; i < _exploreKinds.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                _exploreKinds[i]['title'] ?? '未命名',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                        ],
                        onChanged: hasKinds
                            ? (v) => setState(() {
                                  _selectedKind = v ?? 0;
                                  _exploreStatus = '';
                                  _exploreResults = [];
                                })
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: '重新加载分类（清缓存）',
                      onPressed: busy ? null : () => _loadExploreKinds(refresh: true),
                    ),
                  ],
                ),
                if (selectedUrl.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('分类地址', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  SelectableText(selectedUrl,
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onSurface)),
                ],
                if (_kindsLoading)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.s),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_kindsError != null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.s),
                    child: Text('分类加载失败: $_kindsError',
                        style: TextStyle(fontSize: 11.5, color: cs.error)),
                  ),
                const SizedBox(height: AppSpacing.s),
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('单独调试此分类'),
                      onPressed: (busy || !hasKinds) ? null : _runExploreKind,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.account_tree_outlined, size: 18),
                      label: const Text('跑完整链路'),
                      onPressed: (busy || !hasKinds) ? null : _runExploreChain,
                    ),
                  ],
                ),
                if (_exploreStatus.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s),
                  Text(_exploreStatus,
                      style: TextStyle(
                          fontSize: 12,
                          color: _exploreResults.isEmpty ? cs.error : cs.primary)),
                ],
              ],
            ),
          ),
        ),
        if (!hasKinds && !_kindsLoading && _kindsError == null)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xl),
            child: AppEmptyState(
              icon: Icons.explore_outlined,
              title: '书源未配置发现分类',
              message: '该书源 exploreUrl 为空或未解析出分类；可直接在顶部输入「名称::发现URL」调试发现页。',
            ),
          ),
        for (var i = 0; i < _exploreResults.length; i++)
          Builder(builder: (_) {
            final b = _exploreResults[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 3),
              child: ListTile(
                leading: CircleAvatar(
                    radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                title: Text('${b.name} / ${b.author}', style: const TextStyle(fontSize: 13)),
                subtitle: Text(b.bookUrl ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
                onTap: () {
                  setState(() {
                    _bookVarCtl['bookUrl']!.text = b.bookUrl ?? '';
                    _bookVarCtl['name']!.text = b.name;
                    _bookVarCtl['author']!.text = b.author;
                  });
                  _toast('已填入「变量」页，可在「分步调试」直接跑详情 / 目录 / 正文');
                },
              ),
            );
          }),
        const SizedBox(height: AppSpacing.l),
      ],
    );
  }

  // ==================== 变量 ====================

  /// 读取书籍变量覆盖值，为空时回退 [fallback]
  String _bookVar(String key, [String fallback = '']) {
    final t = _bookVarCtl[key]?.text.trim() ?? '';
    return t.isEmpty ? fallback : t;
  }

  /// 用搜索 / 发现结果填充书籍变量（仅填空白字段，避免覆盖手动编辑）
  void _fillBookVars(SearchBook b, {bool onlyEmpty = false}) {
    void put(String k, String? v) {
      final c = _bookVarCtl[k]!;
      if (onlyEmpty && c.text.trim().isNotEmpty) return;
      c.text = v ?? '';
    }
    put('bookUrl', b.bookUrl);
    put('name', b.name);
    put('author', b.author);
    put('tocUrl', b.bookUrl);
  }

  /// 用目录首章填充章节变量
  void _fillChapterVars(BookChapter c, {bool onlyEmpty = false}) {
    void put(String k, String v) {
      final ctl = _bookVarCtl[k]!;
      if (onlyEmpty && ctl.text.trim().isNotEmpty) return;
      ctl.text = v;
    }
    put('chapterTitle', c.title);
    put('chapterUrl', c.url);
    put('durChapterIndex', '${c.index}');
  }

  /// 用当前分步调试的中间产物强制填充全部书籍变量
  void _fillBookVarsFromCurrent() {
    final b = _pickedBook;
    final info = _bookInfo;
    BookChapter? ch;
    if (_tocChapters.isNotEmpty) {
      ch = _tocChapters.firstWhere(
          (c) => c.url.isNotEmpty && !c.isVolume,
          orElse: () => _tocChapters.first);
    }
    setState(() {
      _bookVarCtl['bookUrl']!.text = info?.bookUrl ?? b?.bookUrl ?? '';
      _bookVarCtl['name']!.text = info?.name ?? b?.name ?? '';
      _bookVarCtl['author']!.text = info?.author ?? b?.author ?? '';
      _bookVarCtl['tocUrl']!.text = info?.noteUrl ?? '';
      _bookVarCtl['chapterTitle']!.text = ch?.title ?? '';
      _bookVarCtl['chapterUrl']!.text = ch?.url ?? '';
      _bookVarCtl['durChapterIndex']!.text = '${ch?.index ?? 0}';
    });
    _toast('已用当前调试结果填充书籍变量');
  }

  void _clearBookVars() {
    setState(() {
      for (final c in _bookVarCtl.values) {
        c.clear();
      }
    });
    _toast('已清空书籍变量覆盖值');
  }

  /// 保存源变量到内存中的书源对象（下一次调试起生效，不写入书源库）
  void _saveSourceVariable() {
    setState(() => widget.source.variable = _sourceVarController.text);
    _toast('源变量已保存，后续调试生效');
  }

  void _restoreSourceVariable() {
    setState(() {
      _sourceVarController.text = _originalVariable ?? '';
      widget.source.variable = _originalVariable;
    });
    _toast('已还原源变量');
  }

  /// 变量页签内容：源变量 + 书籍变量
  Widget _buildVariableView() {
    final cs = Theme.of(context).colorScheme;
    final comment = widget.source.variableComment?.trim() ?? '';
    final rulePut = widget.source.rulePut?.trim() ?? '';
    final ruleGet = widget.source.ruleGet?.trim() ?? '';
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.tune, size: 20, color: cs.primary),
                  const SizedBox(width: AppSpacing.s),
                  const Text('源变量 source.variable',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 6),
                Text(
                  '书源脚本通过 source.getVariable() 读取此值；这里为本次调试临时编辑，'
                  '点击「保存」后对后续所有调试生效，不写入书源库。',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('变量说明: $comment',
                      style: TextStyle(fontSize: 11.5, color: cs.primary)),
                ],
                const SizedBox(height: AppSpacing.s),
                TextField(
                  controller: _sourceVarController,
                  maxLines: 6,
                  minLines: 3,
                  style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: '变量内容（通常为 JSON）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('保存'),
                      onPressed: _saveSourceVariable,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text('还原'),
                      onPressed: _restoreSourceVariable,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const Text('复制'),
                      onPressed: () => _copyText(_sourceVarController.text, '源变量'),
                    ),
                  ],
                ),
                if (rulePut.isNotEmpty || ruleGet.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('书源变量规则（只读）', style: TextStyle(fontSize: 12)),
                    children: [
                      if (rulePut.isNotEmpty) _stepField('rulePut', rulePut),
                      if (ruleGet.isNotEmpty) _stepField('ruleGet', ruleGet),
                      const SizedBox(height: AppSpacing.s),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.menu_book_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: AppSpacing.s),
                  const Text('书籍变量 book / chapter',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 6),
                Text(
                  '这些值作为「详情 / 目录 / 正文」步骤的输入，可临时覆盖；'
                  '留空时自动使用上一步（搜索 / 发现 / 详情 / 目录）解析出的结果。',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.s),
                for (final entry in _bookVarLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s),
                    child: TextField(
                      controller: _bookVarCtl[entry.key],
                      style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        labelText: entry.value,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: const Text('从当前结果填充'),
                      onPressed: _fillBookVarsFromCurrent,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('清空'),
                      onPressed: _clearBookVars,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.l),
      ],
    );
  }

  // ==================== 原始源码 ====================

  /// 原始源码页签：查看搜索/详情/目录/正文各阶段抓到的原始 HTML/JSON。
  /// 聚合源的 data: 书址会把「传给 JS 的 hex 中间产物」塞进 lastRawResponse，
  /// 直接展示就是一串 hex。这里统一解码 + JSON 美化并明确标注来源。
  Widget _buildSourceView() {
    final items = <(String, String?)>[
      ('搜索源码', _searchSrc),
      ('详情源码', _bookSrc),
      ('目录源码', _tocSrc),
      ('正文源码', _contentSrc),
    ];
    final any = items.any((e) => e.$2 != null && e.$2!.isNotEmpty);
    final entries = SourceNetworkLog.instance.entries;
    if (!any && entries.isEmpty) {
      return const AppEmptyState(
        icon: Icons.code_outlined,
        title: '尚未抓取到源码',
        message: '执行「一键调试」后，这里会展示各阶段原始 HTML/JSON，'
            '并在「请求响应」页列出真实请求与响应。',
      );
    }
    final failures = entries.where((e) => !e.ok).length;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      children: [
        if (entries.isNotEmpty)
          Card(
            margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m, vertical: 6),
            child: ListTile(
              leading: Icon(Icons.http,
                  size: 20,
                  color: failures > 0
                      ? Theme.of(context).colorScheme.error
                      : null),
              title: Text('本次调试共 ${entries.length} 次请求，失败 $failures 次',
                  style: const TextStyle(fontSize: 13)),
              subtitle: const Text(
                  '含书源 JS 内 java.ajax 发出的请求，详见「请求响应」页签',
                  style: TextStyle(fontSize: 11)),
            ),
          ),
        for (final e in items)
          if (e.$2 != null && e.$2!.isNotEmpty)
            Builder(builder: (_) {
              final view = SourceNetworkLog.readable(e.$2!);
              final display = view.text.length > 20000
                  ? '${view.text.substring(0, 20000)}\n…（已截断，共 ${view.text.length} 字符）'
                  : view.text;
              return Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.m, vertical: 6),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: const Icon(Icons.code, size: 20),
                  title: Text('${e.$1}（${e.$2!.length} 字符）',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: view.note == null
                      ? null
                      : Text(view.note!,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                          right: AppSpacing.s, bottom: AppSpacing.s),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.copy_all_outlined, size: 16),
                            label: const Text('复制原文'),
                            onPressed: () =>
                                _copyText(e.$2!, '${e.$1}（原始）'),
                          ),
                          const SizedBox(width: 6),
                          TextButton.icon(
                            icon: const Icon(Icons.copy_outlined, size: 16),
                            label: const Text('复制可读版'),
                            onPressed: () => _copyText(view.text, e.$1),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.s),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: SelectableText(
                        display,
                        style: TextStyle(
                            fontSize: 10.5,
                            height: 1.35,
                            fontFamily: 'monospace',
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              );
            }),
      ],
    );
  }

  // ==================== 请求响应 ====================

  /// 请求响应页签：把每条网络请求的状态码、耗时、请求地址、响应大小、
  /// 来源通道、错误与响应预览结构化列出，并展示书源配置请求头与最近请求地址。
  Widget _buildNetworkView() {
    final entries = SourceNetworkLog.instance.entries.reversed.toList();
    final cs = Theme.of(context).colorScheme;
    final header = widget.source.header?.trim() ?? '';
    final isJsHeader = header.toLowerCase().startsWith('@js:');
    final headerText = header.isEmpty
        ? ''
        : (isJsHeader ? header : SourceNetworkLog.readable(header).text);
    final lastUrl = _engine.lastRequestUrl;
    final okCount = entries.where((e) => e.ok).length;
    final failCount = entries.length - okCount;
    final totalMs = entries.fold<int>(0, (a, e) => a + e.durationMs);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请求概览',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                    '共 ${entries.length} 次请求 · 成功 $okCount · 失败 $failCount · 累计耗时 ${totalMs}ms',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                    '每条请求展开后可查看状态码、耗时、请求地址、请求头、响应头、'
                    '最终地址、重定向链、响应大小与来源通道；'
                    '引擎主请求与书源 JS 内 java.ajax 发出的请求都会记录。',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        if (headerText.isNotEmpty)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.input_outlined, size: 20),
              title: const Text('书源配置请求头',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(isJsHeader ? 'JS 动态生成（source.header）' : 'source.header',
                  style: const TextStyle(fontSize: 11)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.s),
                  color: cs.surfaceContainerHighest,
                  child: SelectableText(headerText,
                      style: TextStyle(
                          fontSize: 11, fontFamily: 'monospace', color: cs.onSurface)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('复制请求头'),
                    onPressed: () => _copyText(header, '书源请求头'),
                  ),
                ),
              ],
            ),
          ),
        if (lastUrl != null && lastUrl.isNotEmpty)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.alt_route_outlined, size: 20),
              title: const Text('最近请求地址', style: TextStyle(fontSize: 13)),
              subtitle: SelectableText(
                lastUrl,
                style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                tooltip: '复制',
                onPressed: () => _copyText(lastUrl, '最近请求地址'),
              ),
            ),
          ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xl),
            child: AppEmptyState(
              icon: Icons.http_outlined,
              title: '暂无网络请求',
              message: '执行「一键调试」「分步调试」或「发现分类」后，这里会列出'
                  '真实请求的状态码、耗时、请求地址与响应预览。',
            ),
          ),
        for (final e in entries) _networkCard(e),
        const SizedBox(height: AppSpacing.l),
      ],
    );
  }

  Widget _networkCard(SourceNetworkEntry e) {
    final cs = Theme.of(context).colorScheme;
    final view = e.responsePreview == null
        ? null
        : SourceNetworkLog.readable(e.responsePreview!);
    final preview = view == null
        ? null
        : (view.text.length > 8000
            ? '${view.text.substring(0, 8000)}\n…（已截断）'
            : view.text);
    final statusColor = e.ok ? cs.primary : cs.error;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(e.ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 20, color: statusColor),
        title: Text('${e.clock}  ${e.method}  ${e.statusLabel}  ${e.durationMs}ms',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        subtitle: Text('${e.origin} · ${e.responseBytes} B · ${e.shortUrl}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
        children: [
          const SizedBox(height: AppSpacing.xs),
          _detailRow('状态码', e.statusLabel, color: statusColor),
          _detailRow('耗时', '${e.durationMs} ms'),
          _detailRow('方法', e.method),
          _detailRow('请求地址', e.url),
          if (e.finalUrl != null && e.finalUrl!.isNotEmpty)
            _detailRow(
              e.finalUrl != e.url ? '最终地址 · 重定向' : '最终地址',
              e.finalUrl!,
              color: e.finalUrl != e.url ? cs.tertiary : null,
            ),
          _detailRow('响应大小', '${e.responseBytes} B'),
          _detailRow('来源通道', e.origin),
          _detailRow('时间', e.clock),
          if (e.error != null) _detailRow('错误', e.error!, color: cs.error),
          _monoBlock('请求头', _headersText(e.requestHeaders)),
          _monoBlock('响应头', _headersText(e.responseHeaders)),
          if (e.hasRedirect) _monoBlock('重定向链', _redirectChainText(e)),
          if (preview != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.s),
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              color: cs.surfaceContainerHighest,
              child: SelectableText(preview,
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      fontFamily: 'monospace',
                      color: cs.onSurface)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: const Text('复制 URL'),
                onPressed: () => _copyText(e.url, '请求 URL'),
              ),
              if (preview != null)
                TextButton.icon(
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('复制响应'),
                  onPressed: () => _copyText(view!.text, '响应预览'),
                ),
              TextButton.icon(
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: const Text('复制详情'),
                onPressed: () => _copyText(_networkEntryText(e), '请求详情'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 请求响应的「标签 + 等宽文本」行
  Widget _detailRow(String label, String value, {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(value,
                style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: color ?? cs.onSurface)),
          ),
        ],
      ),
    );
  }

  /// 等宽文本展示块：标题 + 灰底圆角内容，用于请求头 / 响应头 / 重定向链
  Widget _monoBlock(String label, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m, vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: AppRadius.mAll,
            ),
            child: SelectableText(
              text,
              style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace',
                  color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  /// 把请求头 / 响应头整理为逐行「key: value」文本，为空时返回「无」
  String _headersText(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '无';
    return headers.entries.map((h) => '${h.key}: ${h.value}').join('\n');
  }

  /// 把重定向链整理为可读文本：首条地址起行，后续每条以「→」标记跳转
  String _redirectChainText(SourceNetworkEntry e) {
    if (e.redirects.isEmpty) return e.finalUrl ?? '无';
    return e.redirects.asMap().entries.map((entry) {
      return entry.key == 0 ? entry.value : '→ ${entry.value}';
    }).join('\n');
  }

  /// 单条网络请求的可复制纯文本详情
  String _networkEntryText(SourceNetworkEntry e) {
    final sb = StringBuffer();
    sb.writeln('时间: ${e.clock}');
    sb.writeln('方法: ${e.method}');
    sb.writeln('状态码: ${e.statusLabel}');
    sb.writeln('耗时: ${e.durationMs} ms');
    sb.writeln('响应大小: ${e.responseBytes} B');
    sb.writeln('来源通道: ${e.origin}');
    sb.writeln('请求地址: ${e.url}');
    if (e.finalUrl != null && e.finalUrl!.isNotEmpty) {
      sb.writeln('最终地址${e.finalUrl != e.url ? "（重定向）" : ""}: ${e.finalUrl}');
    }
    sb.writeln('----- 请求头 -----');
    sb.writeln(_headersText(e.requestHeaders));
    sb.writeln('----- 响应头 -----');
    sb.writeln(_headersText(e.responseHeaders));
    if (e.hasRedirect) {
      sb.writeln('----- 重定向链 -----');
      sb.writeln(_redirectChainText(e));
    }
    if (e.error != null) sb.writeln('错误: ${e.error}');
    if (e.responsePreview != null) {
      sb.writeln('----- 响应预览 -----');
      sb.writeln(SourceNetworkLog.readable(e.responsePreview!).text);
    }
    return sb.toString();
  }

  /// 网络请求日志纯文本（用于「仅复制网络请求日志」及日志导出）
  String _networkLogText() {
    final sb = StringBuffer();
    sb.writeln('===== 网络请求日志：${widget.source.bookSourceName} =====');
    final entries = SourceNetworkLog.instance.entries;
    if (entries.isEmpty) sb.writeln('(无)');
    for (final e in entries) {
      sb.writeln('${e.clock}  ${e.method}  ${e.statusLabel}  ${e.durationMs}ms  '
          '${e.responseBytes}B  [${e.origin}]');
      sb.writeln('  ${e.url}');
      if (e.finalUrl != null && e.finalUrl!.isNotEmpty) {
        sb.writeln('  最终地址${e.finalUrl != e.url ? "（重定向）" : ""}: ${e.finalUrl}');
      }
      _appendTextSection(sb, '请求头', _headersText(e.requestHeaders));
      _appendTextSection(sb, '响应头', _headersText(e.responseHeaders));
      if (e.hasRedirect) {
        _appendTextSection(sb, '重定向链', _redirectChainText(e));
      }
      if (e.error != null) sb.writeln('  错误: ${e.error}');
    }
    return sb.toString();
  }

  /// 向纯文本缓冲追加「标题 + 逐行缩进内容」区块
  void _appendTextSection(StringBuffer sb, String label, String text) {
    sb.writeln('  $label:');
    for (final line in text.split('\n')) {
      sb.writeln('    $line');
    }
  }

  // ==================== 日志导出 / 分享 ====================

  /// 汇总全部调试信息为纯文本
  String _exportLogText() {
    final sb = StringBuffer();
    final s = widget.source;
    sb.writeln('===== 书源调试日志 =====');
    sb.writeln('书源: ${s.bookSourceName}');
    sb.writeln('地址: ${s.bookSourceUrl}');
    sb.writeln('导出时间: ${DateTime.now()}');
    sb.writeln('调试目标: ${_keywordController.text.trim()}');
    sb.writeln();
    sb.writeln('----- 一键调试日志 -----');
    if (_logs.isEmpty) {
      sb.writeln('(无)');
    } else {
      for (final l in _logs) {
        sb.writeln(l.text);
      }
    }
    sb.writeln();
    sb.writeln('----- 分步调试 -----');
    for (final st in _steps) {
      sb.writeln('[${st.title}] 状态=${_stepStatusText(st.status)} 耗时=${st.durationMs}ms');
      if (st.url.isNotEmpty) sb.writeln('  请求地址: ${st.url}');
      if (st.summary.isNotEmpty) {
        sb.writeln('  ${st.summary.replaceAll('\n', '\n  ')}');
      }
      if (st.error != null) sb.writeln('  错误: ${st.error}');
      if (st.engineLogs.isNotEmpty) {
        sb.writeln('  引擎日志:');
        for (final l in st.engineLogs) {
          sb.writeln('    $l');
        }
      }
    }
    sb.writeln();
    sb.writeln('----- 发现分类 -----');
    for (var i = 0; i < _exploreKinds.length; i++) {
      final k = _exploreKinds[i];
      sb.writeln('${i == _selectedKind ? '*' : ' '} ${k['title'] ?? ''}  ${k['url'] ?? ''}');
    }
    if (_exploreStatus.isNotEmpty) sb.writeln('状态: $_exploreStatus');
    if (_exploreResults.isNotEmpty) {
      sb.writeln('结果 ${_exploreResults.length} 本:');
      for (final b in _exploreResults) {
        sb.writeln('  ${b.name} / ${b.author}  ${b.bookUrl ?? ''}');
      }
    }
    sb.writeln();
    sb.write(_networkLogText());
    sb.writeln();
    sb.writeln('----- 变量 -----');
    sb.writeln('源变量 source.variable: ${s.variable ?? ''}');
    if ((s.rulePut ?? '').isNotEmpty) sb.writeln('rulePut: ${s.rulePut}');
    if ((s.ruleGet ?? '').isNotEmpty) sb.writeln('ruleGet: ${s.ruleGet}');
    for (final e in _bookVarLabels.entries) {
      sb.writeln('${e.value}: ${_bookVarCtl[e.key]?.text ?? ''}');
    }
    sb.writeln();
    sb.writeln('----- 原始源码 -----');
    final srcItems = <(String, String?)>[
      ('搜索源码', _searchSrc),
      ('详情源码', _bookSrc),
      ('目录源码', _tocSrc),
      ('正文源码', _contentSrc),
    ];
    for (final item in srcItems) {
      final raw = item.$2;
      if (raw == null || raw.isEmpty) continue;
      final view = SourceNetworkLog.readable(raw);
      final text = view.text.length > 20000
          ? '${view.text.substring(0, 20000)}\n…（已截断，共 ${view.text.length} 字符）'
          : view.text;
      sb.writeln('### ${item.$1}（${raw.length} 字符${view.note == null ? '' : '，${view.note}'}）');
      sb.writeln(text);
      sb.writeln();
    }
    return sb.toString();
  }

  String _stepStatusText(_StepStatus s) {
    switch (s) {
      case _StepStatus.idle:
        return '未执行';
      case _StepStatus.running:
        return '执行中';
      case _StepStatus.ok:
        return '成功';
      case _StepStatus.fail:
        return '失败';
    }
  }

  void _onExportAction(String action) {
    switch (action) {
      case 'copy':
        _copyText(_exportLogText(), '全部调试日志');
        break;
      case 'share':
        Share.share(_exportLogText(),
            subject: '书源调试日志：${widget.source.bookSourceName}');
        break;
      case 'file':
        _exportLogFile();
        break;
      case 'network':
        _copyText(_networkLogText(), '网络请求日志');
        break;
    }
  }

  /// 把全部日志写成 txt 临时文件并通过系统分享面板分享
  Future<void> _exportLogFile() async {
    try {
      final dir = await getTemporaryDirectory();
      final safe = widget.source.bookSourceName
          .replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
      final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/书源调试_${safe}_$ts.txt');
      await file.writeAsString(_exportLogText());
      await Share.shareXFiles([XFile(file.path)],
          text: '书源调试日志：${widget.source.bookSourceName}');
    } catch (e) {
      _toast('导出文件失败: $e');
    }
  }

  // ==================== 通用 ====================

  Color _colorOf(_LogLevel level) {
    final cs = Theme.of(context).colorScheme;
    switch (level) {
      case _LogLevel.stage:
        return cs.primary;
      case _LogLevel.ok:
        return cs.tertiary;
      case _LogLevel.error:
        return cs.error;
      case _LogLevel.detail:
        return cs.onSurfaceVariant;
      case _LogLevel.info:
        return cs.onSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('调试: ${widget.source.bookSourceName}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share),
            tooltip: '导出日志',
            onSelected: _onExportAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('复制全部日志')),
              PopupMenuItem(value: 'share', child: Text('分享全部日志（纯文本）')),
              PopupMenuItem(value: 'file', child: Text('导出为 txt 文件')),
              PopupMenuItem(value: 'network', child: Text('仅复制网络请求日志')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: (_running || _stepRunning || _exploreRunning)
                ? null
                : () => setState(() {
                      _logs.clear();
                      _resetSteps();
                      _searchSrc = null;
                      _bookSrc = null;
                      _tocSrc = null;
                      _contentSrc = null;
                      _exploreResults = [];
                      _exploreStatus = '';
                      SourceNetworkLog.instance.clear();
                    }),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keywordController,
                    enabled: !_running && !_stepRunning && !_exploreRunning,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runAll(),
                    decoration: const InputDecoration(
                      labelText: '调试目标',
                      hintText: '搜索词 / 详情URL / ++目录URL / --正文URL / 发现::URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                FilledButton(
                  onPressed: (_running || _stepRunning || _exploreRunning) ? null : _runAll,
                  child: _running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('开始调试'),
                ),
              ],
            ),
          ),
          if (_running || _stepRunning || _exploreRunning)
            LinearProgressIndicator(
              value: _running && _progress > 0 ? _progress : null,
              minHeight: 2,
            ),
          // 页签：一键调试 / 分步调试 / 发现分类 / 请求响应 / 变量 / 原始源码
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: '一键调试'),
              Tab(text: '分步调试'),
              Tab(text: '发现分类'),
              Tab(text: '请求响应'),
              Tab(text: '变量'),
              Tab(text: '原始源码'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 一键调试：统一日志输出
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: _logs.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.terminal_outlined,
                          title: '暂无调试日志',
                          message: '输入关键词后点击「开始调试」',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: _logs.length,
                          itemBuilder: (_, i) {
                            final line = _logs[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: SelectableText(
                                line.text,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: _colorOf(line.level),
                                  fontFamily: 'monospace',
                                  fontWeight:
                                      line.level == _LogLevel.stage ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // 分步调试：每步单独执行 + 耗时 + URL/摘要
                _buildStepView(),
                // 发现分类：下拉选择 + 单独调试 / 完整链路
                _buildExploreView(),
                // 请求响应：状态码 / 耗时 / 请求地址 / 书源请求头
                _buildNetworkView(),
                // 变量：源变量 / 书籍变量临时编辑
                _buildVariableView(),
                // 原始源码：查看各阶段抓到的 HTML/JSON 原文（hex 自动解码）
                _buildSourceView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
