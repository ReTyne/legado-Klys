import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 书源调试页（对齐 legado）：
/// * 「一键调试」：输入搜索内容后一键跑完整链路
///   搜索 → 书籍详情 → 目录 → 第一章正文，统一输出日志。
/// * 「分步调试」：搜索/发现/详情/目录/正文各自可单独执行，
///   每步用 Stopwatch 统计耗时，并展示该步请求 URL、返回摘要与引擎日志。
class SourceDebugScreen extends StatefulWidget {
  final BookSource source;

  const SourceDebugScreen({super.key, required this.source});

  @override
  State<SourceDebugScreen> createState() => _SourceDebugScreenState();
}

class _SourceDebugScreenState extends State<SourceDebugScreen>
    with SingleTickerProviderStateMixin {
  final _keywordController = TextEditingController();
  final BookSourceEngine _engine = BookSourceEngine();
  final List<_LogLine> _logs = [];
  bool _running = false;
  double _progress = 0;

  // 各阶段原始源码（对齐 legado 调试页「查看源码」）
  String? _searchSrc;
  String? _bookSrc;
  String? _tocSrc;
  String? _contentSrc;

  // 分步调试：三个页签（一键调试 / 分步调试 / 原始源码）
  late final TabController _tabController;
  // 分步调试各步骤状态
  final List<_DebugStep> _steps = [];
  bool _stepRunning = false;
  // 分步调试中间产物（供依赖步骤复用）
  SearchBook? _pickedBook;
  Book? _bookInfo;
  List<BookChapter> _tocChapters = [];

  @override
  void initState() {
    super.initState();
    // 默认关键词：优先书源 ruleSearch.checkKeyWord（对齐 legado 调试页推荐词，
    // 见 BookSourceDebugActivity「binding.textMy.text = ruleSearch?.checkKeyWord」），
    // 回退顶层 checkKeyWord，最后回退「我的」。
    _keywordController.text = _defaultKeyword(widget.source);
    _tabController = TabController(length: 3, vsync: this);
    _initSteps();
  }

  /// 调试页默认关键词（对齐 legado getCheckKeyword：忽略明显不是关键词的值）
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

  /// 解析调试输入，路由到对应阶段（对齐 legado Debug.startDebug）：
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

  /// 单独执行一个调试步骤，统计耗时并记录 URL / 摘要 / 引擎日志
  Future<void> _runStep(_DebugStep step) async {
    if (_stepRunning || _running) return;
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
          step.summary = '共 ${results.length} 本，前 5 本：\n${results
              .take(5)
              .map((b) => '  ${b.name} / ${b.author}')
              .join('\n')}';
          break;
        case 'explore':
          if ((source.exploreUrl ?? '').trim().isEmpty) {
            throw Exception('书源未配置 exploreUrl');
          }
          final results = await _engine.explore(source);
          _pickedBook = results.isNotEmpty ? results.first : null;
          if (results.isEmpty) {
            throw Exception('发现结果为空（请检查 exploreUrl / ruleExplore）');
          }
          step.summary = '共 ${results.length} 本，前 5 本：\n${results
              .take(5)
              .map((b) => '  ${b.name} / ${b.author}')
              .join('\n')}';
          break;
        case 'info':
          final book = _pickedBook;
          if (book == null || (book.bookUrl ?? '').isEmpty) {
            throw Exception('请先执行「搜索」或「发现」获取书籍');
          }
          final info = await _engine.getBookInfo(source, book.bookUrl!,
              presetName: book.name, presetAuthor: book.author);
          if (info == null) throw Exception('详情解析失败（ruleBookInfo）');
          _bookInfo = info;
          step.url = book.bookUrl!;
          step.summary = '书名: ${info.name}  作者: ${info.author}\n分类: ${info.kind}\n目录地址: ${info.noteUrl}';
          break;
        case 'toc':
          final info = _bookInfo;
          if (info == null) throw Exception('请先执行「详情」');
          final tocUrl = info.noteUrl ?? info.bookUrl ?? '';
          final chapters = await _engine.getToc(source, tocUrl, bookInfo: {
            'bookUrl': info.bookUrl ?? '',
            'name': info.name,
            'author': info.author,
            'tocUrl': tocUrl,
            'durChapterIndex': 0,
          });
          if (chapters.isEmpty) throw Exception('目录为空（ruleToc.chapterList）');
          _tocChapters = chapters;
          step.url = tocUrl;
          step.summary = '共 ${chapters.length} 章，前 3 章：\n${chapters
              .take(3)
              .map((c) => '  ${c.index + 1}. ${c.title} -> ${c.url}')
              .join('\n')}';
          break;
        case 'content':
          if (_tocChapters.isEmpty) throw Exception('请先执行「目录」');
          final info = _bookInfo;
          final ch = _tocChapters.firstWhere(
              (c) => c.url.isNotEmpty && !c.isVolume,
              orElse: () => _tocChapters.first);
          final content = await _engine.getContent(source, ch.url, bookInfo: {
            'bookUrl': info?.bookUrl,
            'name': info?.name,
            'author': info?.author,
            'tocUrl': info?.noteUrl,
            'durChapterIndex': ch.index,
          }, chapter: {
            'index': ch.index,
            'title': ch.title,
            'url': ch.url,
            'bookUrl': info?.bookUrl,
          });
          if (content == null || content.trim().isEmpty) {
            throw Exception('正文为空（ruleContent.content）');
          }
          step.url = ch.url;
          final preview = content.length > 300 ? content.substring(0, 300) : content;
          step.summary = '正文长度 ${content.length} 字符，预览：\n$preview';
          break;
      }
      sw.stop();
      final urls = _extractUrls(_engine.debugLog);
      if (mounted) setState(() {
        step.durationMs = sw.elapsedMilliseconds;
        step.status = _StepStatus.ok;
        if (step.url.isEmpty && urls.isNotEmpty) {
          step.url = urls.first;
        }
        step.engineLogs = _engine.debugLog.toList();
      });
    } catch (e) {
      sw.stop();
      if (mounted) setState(() {
        step.durationMs = sw.elapsedMilliseconds;
        step.status = _StepStatus.fail;
        step.error = e.toString().replaceFirst('Exception: ', '');
        step.engineLogs = _engine.debugLog.toList();
      });
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
        statusColor = Colors.grey;
        statusText = '未执行';
        break;
      case _StepStatus.running:
        statusColor = colorScheme.primary;
        statusText = '执行中…';
        break;
      case _StepStatus.ok:
        statusColor = const Color(0xFF2E7D32);
        statusText = '成功';
        break;
      case _StepStatus.fail:
        statusColor = const Color(0xFFC62828);
        statusText = '失败';
        break;
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(step.icon, size: 20),
                const SizedBox(width: 8),
                Text(step.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 8),
                // 状态标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(statusText,
                      style: TextStyle(color: statusColor, fontSize: 11)),
                ),
                const Spacer(),
                // 耗时统计（Stopwatch）
                if (step.durationMs > 0)
                  Text('${step.durationMs} ms',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFamily: 'monospace')),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('执行'),
                  onPressed:
                      (_stepRunning || _running) ? null : () => _runStep(step),
                ),
              ],
            ),
            // 请求 URL
            if (step.url.isNotEmpty) ...[
              const SizedBox(height: 8),
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
              const SizedBox(height: 4),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('引擎日志（${step.engineLogs.length} 行）',
                    style: const TextStyle(fontSize: 12)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      step.engineLogs.join('\n'),
                      style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          fontFamily: 'monospace',
                          color: Color(0xFF555555)),
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

  /// 原始源码页签：查看搜索/详情/目录/正文各阶段抓到的原始 HTML/JSON。
  Widget _buildSourceView() {
    final items = <(String, String?)>[
      ('搜索源码', _searchSrc),
      ('详情源码', _bookSrc),
      ('目录源码', _tocSrc),
      ('正文源码', _contentSrc),
    ];
    final any = items.any((e) => e.$2 != null && e.$2!.isNotEmpty);
    if (!any) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '尚未抓取到源码。\n执行「一键调试」后，这里会展示各阶段的原始 HTML/JSON。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.6),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final e in items)
          if (e.$2 != null && e.$2!.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(Icons.code, size: 20),
                title: Text('${e.$1}（${e.$2!.length} 字符）',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.black.withOpacity(0.04),
                    child: SelectableText(
                      e.$2!.length > 20000
                          ? '${e.$2!.substring(0, 20000)}\n…（已截断，共 ${e.$2!.length} 字符）'
                          : e.$2!,
                      style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          fontFamily: 'monospace',
                          color: Color(0xFF333333)),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// 步骤详情字段（标签 + 等宽文本）
  Widget _stepField(String label, String value, {bool error = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.35,
            fontFamily: 'monospace',
            color: error ? const Color(0xFFC62828) : const Color(0xFF333333),
          ),
        ),
      ],
    );
  }

  /// 分步调试页签内容
  Widget _buildStepView() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '每步可单独执行并统计耗时；「详情 / 目录 / 正文」依赖前序步骤结果，请按顺序执行。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        ..._steps.map(_stepCard),
        const SizedBox(height: 16),
      ],
    );
  }

  Color _colorOf(_LogLevel level) {
    switch (level) {
      case _LogLevel.stage:
        return const Color(0xFF1565C0);
      case _LogLevel.ok:
        return const Color(0xFF2E7D32);
      case _LogLevel.error:
        return const Color(0xFFC62828);
      case _LogLevel.detail:
        return const Color(0xFF777777);
      case _LogLevel.info:
        return const Color(0xFF333333);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('调试: ${widget.source.bookSourceName}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: (_running || _stepRunning)
                ? null
                : () => setState(() {
                      _logs.clear();
                      _resetSteps();
                      _searchSrc = null;
                      _bookSrc = null;
                      _tocSrc = null;
                      _contentSrc = null;
                    }),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keywordController,
                    enabled: !_running && !_stepRunning,
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
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_running || _stepRunning) ? null : _runAll,
                  child: _running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('开始调试'),
                ),
              ],
            ),
          ),
          if (_running || _stepRunning) LinearProgressIndicator(value: _progress, minHeight: 2),
          // 页签：一键调试 / 分步调试
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '一键调试'),
              Tab(text: '分步调试'),
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
                      ? const Center(child: Text('输入关键词后点击「开始调试」', style: TextStyle(color: Colors.grey)))
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
                // 原始源码：查看各阶段抓到的 HTML/JSON 原文
                _buildSourceView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _LogLevel { stage, ok, error, detail, info }

class _LogLine {
  _LogLine(this.text, this.level);
  final String text;
  final _LogLevel level;
}

/// 分步调试步骤执行状态
enum _StepStatus { idle, running, ok, fail }

/// 分步调试步骤：记录执行状态、耗时（Stopwatch 统计）、请求 URL、返回摘要与引擎日志
class _DebugStep {
  _DebugStep(this.key, this.title, this.icon);
  final String key;
  final String title;
  final IconData icon;
  _StepStatus status = _StepStatus.idle;
  int durationMs = 0;
  String url = '';
  String summary = '';
  String? error;
  List<String> engineLogs = [];
}
