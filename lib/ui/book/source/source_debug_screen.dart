import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 书源调试页（对齐 legado）：输入搜索内容后一键跑完整链路
/// 搜索 → 书籍详情 → 目录 → 第一章正文，统一输出日志。
class SourceDebugScreen extends StatefulWidget {
  final BookSource source;

  const SourceDebugScreen({super.key, required this.source});

  @override
  State<SourceDebugScreen> createState() => _SourceDebugScreenState();
}

class _SourceDebugScreenState extends State<SourceDebugScreen> {
  final _keywordController = TextEditingController();
  final BookSourceEngine _engine = BookSourceEngine();
  final List<_LogLine> _logs = [];
  bool _running = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _keywordController.text = '我的';
  }

  @override
  void dispose() {
    _keywordController.dispose();
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

  Future<void> _runAll() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      _log('请输入搜索关键词', level: _LogLevel.error);
      return;
    }
    setState(() {
      _running = true;
      _logs.clear();
      _progress = 0;
    });
    final source = widget.source;
    _log('===== 开始调试：${source.bookSourceName} =====', level: _LogLevel.stage);
    _log('书源地址: ${source.bookSourceUrl}');

    SearchBook? firstBook;
    try {
      // 1) 搜索
      _progress = 0.1;
      _log('【1/4】搜索「$keyword」…', level: _LogLevel.stage);
      final results = await _engine.search(source, keyword);
      _dumpEngineLog();
      if (results.isEmpty) {
        _log('搜索结果为空（请检查 searchUrl / 登录 / 规则）', level: _LogLevel.error);
        _finish(false);
        return;
      }
      _log('搜索到 ${results.length} 本，前 3 本：', level: _LogLevel.ok);
      for (var i = 0; i < results.length && i < 3; i++) {
        final b = results[i];
        _log('  ${i + 1}. ${b.name} / ${b.author}  bookUrl=${b.bookUrl}');
      }
      firstBook = results.first;
      _progress = 0.35;

      // 2) 详情
      final detailUrl = firstBook.bookUrl;
      if (detailUrl == null || detailUrl.isEmpty) {
        _log('首本书缺少 bookUrl', level: _LogLevel.error);
        _finish(false);
        return;
      }
      _log('【2/4】获取书籍详情：${firstBook.name}', level: _LogLevel.stage);
      final info = await _engine.getBookInfo(source, detailUrl,
          presetName: firstBook.name, presetAuthor: firstBook.author);
      _dumpEngineLog();
      if (info == null) {
        _log('详情解析失败（ruleBookInfo）', level: _LogLevel.error);
        _finish(false);
        return;
      }
      _log('书名: ${info.name}  作者: ${info.author}', level: _LogLevel.ok);
      _log('分类: ${info.kind}  最新: ${info.lastChapter}');
      _log('目录地址: ${info.noteUrl}');
      _progress = 0.6;

      // 3) 目录
      final tocUrl = info.noteUrl ?? detailUrl;
      _log('【3/4】获取目录…', level: _LogLevel.stage);
      final chapters = await _engine.getToc(source, tocUrl, bookInfo: {
        'bookUrl': info.bookUrl ?? detailUrl,
        'name': info.name,
        'author': info.author,
        'tocUrl': tocUrl,
        'durChapterIndex': 0,
      });
      _dumpEngineLog();
      if (chapters.isEmpty) {
        _log('目录为空（ruleToc.chapterList）', level: _LogLevel.error);
        _finish(false);
        return;
      }
      _log('目录共 ${chapters.length} 章，前 3 章：', level: _LogLevel.ok);
      for (var i = 0; i < chapters.length && i < 3; i++) {
        _log('  ${i + 1}. ${chapters[i].title} -> ${chapters[i].url}');
      }
      _progress = 0.8;

      // 4) 第一章正文
      final firstChapter = chapters.firstWhere((c) => c.url.isNotEmpty && !c.isVolume,
          orElse: () => chapters.first);
      _log('【4/4】获取正文：${firstChapter.title}', level: _LogLevel.stage);
      final content = await _engine.getContent(source, firstChapter.url, bookInfo: {
        'bookUrl': info.bookUrl,
        'name': info.name,
        'author': info.author,
        'tocUrl': info.noteUrl,
        'durChapterIndex': firstChapter.index,
      }, chapter: {
        'index': firstChapter.index,
        'title': firstChapter.title,
        'url': firstChapter.url,
        'bookUrl': info.bookUrl,
      });
      _dumpEngineLog();
      if (content == null || content.trim().isEmpty) {
        _log('正文为空（ruleContent.content）', level: _LogLevel.error);
        _finish(false);
        return;
      }
      final preview = content.length > 300 ? content.substring(0, 300) : content;
      _log('正文长度 ${content.length} 字符，预览：', level: _LogLevel.ok);
      _log(preview, level: _LogLevel.detail);

      _progress = 1;
      _log('===== 全链路调试通过 ✓ =====', level: _LogLevel.stage);
      _finish(true);
    } catch (e) {
      _dumpEngineLog();
      _log('调试异常: $e', level: _LogLevel.error);
      _finish(false);
    }
  }

  void _finish(bool ok) {
    if (mounted) setState(() => _running = false);
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
            onPressed: _running ? null : () => setState(_logs.clear),
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
                    enabled: !_running,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runAll(),
                    decoration: const InputDecoration(
                      labelText: '搜索内容',
                      hintText: '输入书名/作者，一键调试搜索→详情→目录→正文',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _running ? null : _runAll,
                  child: _running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('开始调试'),
                ),
              ],
            ),
          ),
          if (_running) LinearProgressIndicator(value: _progress, minHeight: 2),
          Expanded(
            child: Container(
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
