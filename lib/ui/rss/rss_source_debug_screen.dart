import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 调试日志等级：仅用于着色，不涉及执行逻辑。
enum _RssLogLevel { stage, ok, error, detail, request }

class _RssLogLine {
  final String text;
  final _RssLogLevel level;
  _RssLogLine(this.text, this.level);
}

/// 一次阶段请求的响应记录。
class _RssNetRecord {
  final String stage;
  final String url;
  final int elapsedMs;
  final int bytes;
  final String preview;
  _RssNetRecord({
    required this.stage,
    required this.url,
    required this.elapsedMs,
    required this.bytes,
    required this.preview,
  });
}

/// RSS 订阅源调试页。
///
/// 三段调试：分类（sortUrl）/ 列表（ruleArticles）/ 正文（ruleContent），
/// 每段输出解析结果、原始响应预览并计入请求响应日志；
/// 另提供源变量面板、全部日志复制与导出 txt 文件。
class RssSourceDebugScreen extends StatefulWidget {
  final RssSource source;
  const RssSourceDebugScreen({super.key, required this.source});

  @override
  State<RssSourceDebugScreen> createState() => _RssSourceDebugScreenState();
}

class _RssSourceDebugScreenState extends State<RssSourceDebugScreen>
    with SingleTickerProviderStateMixin {
  final RssService _service = RssService();
  late final TabController _tab;
  final List<_RssLogLine> _logs = <_RssLogLine>[];
  final List<_RssNetRecord> _net = <_RssNetRecord>[];
  final ScrollController _logScroll = ScrollController();

  bool _running = false;
  double _progress = 0;

  List<RssCategory> _categories = <RssCategory>[];
  List<RssArticle> _articles = <RssArticle>[];
  int _selectedCategory = 0;
  int _selectedArticle = 0;
  String? _content;
  String _categoryRaw = '';
  String _listRaw = '';
  String _contentRaw = '';

  late final TextEditingController _variableCtl;
  String _variableApplied = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _variableCtl = TextEditingController(text: widget.source.variable ?? '');
    _variableApplied = widget.source.variable ?? '';
  }

  @override
  void dispose() {
    _tab.dispose();
    _logScroll.dispose();
    _variableCtl.dispose();
    super.dispose();
  }

  // ==================== 日志 / 提示 ====================

  void _log(String text, {_RssLogLevel level = _RssLogLevel.detail}) {
    if (!mounted) return;
    setState(() => _logs.add(_RssLogLine(text, level)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Color _colorOf(_RssLogLevel level) {
    final cs = Theme.of(context).colorScheme;
    switch (level) {
      case _RssLogLevel.stage:
        return cs.primary;
      case _RssLogLevel.ok:
        return cs.tertiary;
      case _RssLogLevel.error:
        return cs.error;
      case _RssLogLevel.request:
        return cs.secondary;
      case _RssLogLevel.detail:
        return cs.onSurface;
    }
  }

  String _exportLogText() {
    final sb = StringBuffer();
    sb.writeln('RSS 订阅源调试日志');
    sb.writeln('源名称: ${widget.source.sourceName}');
    sb.writeln('源地址: ${widget.source.sourceUrl}');
    sb.writeln('时间: ${DateTime.now().toIso8601String()}');
    sb.writeln('----------------------------------------');
    for (final l in _logs) {
      sb.writeln(l.text);
    }
    return sb.toString();
  }

  void _copyText(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    _toast('已复制$what');
  }

  void _onExportAction(String action) {
    switch (action) {
      case 'copy':
        _copyText(_exportLogText(), '全部调试日志');
        break;
      case 'share':
        Share.share(_exportLogText(),
            subject: 'RSS 源调试日志：${widget.source.sourceName}');
        break;
      case 'file':
        _exportLogFile();
        break;
      case 'network':
        _copyText(_networkLogText(), '请求响应日志');
        break;
    }
  }

  String _networkLogText() {
    final sb = StringBuffer();
    for (final n in _net) {
      sb.writeln('[${n.stage}] ${n.url}');
      sb.writeln('  耗时 ${n.elapsedMs}ms  大小 ${n.bytes} 字符');
      sb.writeln('  预览: ${n.preview}');
    }
    return sb.toString();
  }

  Future<void> _exportLogFile() async {
    try {
      final dir = await getTemporaryDirectory();
      final safe =
          widget.source.sourceName.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
      final ts =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/rss_调试_${safe}_$ts.txt');
      await file.writeAsString(_exportLogText());
      await Share.shareXFiles([XFile(file.path)],
          text: 'RSS 源调试日志：${widget.source.sourceName}');
    } catch (e) {
      _toast('导出文件失败: $e');
    }
  }

  void _recordNet(String stage, String url, int elapsedMs, String raw) {
    final preview = raw.length > 400 ? raw.substring(0, 400) : raw;
    _net.add(_RssNetRecord(
      stage: stage,
      url: url,
      elapsedMs: elapsedMs,
      bytes: raw.length,
      preview: preview,
    ));
    _log('[$stage] $url  耗时 ${elapsedMs}ms  大小 ${raw.length} 字符',
        level: _RssLogLevel.request);
  }

  // ==================== 三段调试 ====================

  /// 分类：sortUrl 解析（含 <js> / @js: 求值与缓存）。
  Future<List<RssCategory>> _debugCategories() async {
    _log('===== 分类调试 =====', level: _RssLogLevel.stage);
    _log('sortUrl: ${widget.source.sortUrl ?? '(空)'}');
    _categoryRaw = widget.source.sortUrl ?? '';
    final sw = Stopwatch()..start();
    List<RssCategory> cats;
    try {
      cats = await _service.sortUrls(widget.source).timeout(
          const Duration(seconds: 20),
          onTimeout: () => <RssCategory>[]);
    } catch (e) {
      sw.stop();
      _log('分类解析异常: $e', level: _RssLogLevel.error);
      return <RssCategory>[];
    }
    sw.stop();
    if (cats.isEmpty) {
      _log('分类为空（请检查 sortUrl / JS 求值）', level: _RssLogLevel.error);
    } else {
      _log('解析到 ${cats.length} 个分类：', level: _RssLogLevel.ok);
      for (var i = 0; i < cats.length && i < 10; i++) {
        _log('  ${i + 1}. ${cats[i].name}  ->  ${cats[i].rawUrl}');
      }
    }
    _recordNet(
        '分类', widget.source.sourceUrl, sw.elapsedMilliseconds, _categoryRaw);
    if (mounted) {
      setState(() {
        _categories = cats;
        _selectedCategory = 0;
      });
    }
    return cats;
  }

  /// 列表：选中分类 → 文章规则解析。
  Future<List<RssArticle>> _debugList() async {
    if (_categories.isEmpty) {
      _log('请先执行分类调试', level: _RssLogLevel.error);
      return <RssArticle>[];
    }
    var i = _selectedCategory;
    if (i < 0 || i >= _categories.length) i = 0;
    final cat = _categories[i];
    _log('===== 列表调试：${cat.name} =====', level: _RssLogLevel.stage);
    final sw = Stopwatch()..start();
    String raw = '';
    List<RssArticle> list;
    try {
      // 原始响应与规则解析并发执行，调试页据此保留响应预览。
      final rawFuture = cat.rawUrl.startsWith('http')
          ? _service
              .fetchRaw(cat.rawUrl)
              .timeout(const Duration(seconds: 20), onTimeout: () => '')
          : Future<String>.value('');
      final listFuture = _service.fetchCategory(widget.source, cat).timeout(
          const Duration(seconds: 20),
          onTimeout: () => <RssArticle>[]);
      raw = await rawFuture;
      list = await listFuture;
    } catch (e) {
      sw.stop();
      _log('列表解析异常: $e', level: _RssLogLevel.error);
      return <RssArticle>[];
    }
    sw.stop();
    _listRaw = raw;
    _recordNet('列表', cat.rawUrl, sw.elapsedMilliseconds, raw);
    if (list.isEmpty) {
      _log('文章列表为空（请检查 ruleArticles / ruleTitle / ruleLink）',
          level: _RssLogLevel.error);
    } else {
      _log('解析到 ${list.length} 篇文章：', level: _RssLogLevel.ok);
      for (var n = 0; n < list.length && n < 10; n++) {
        _log('  ${n + 1}. ${list[n].title}  ->  ${list[n].link}');
      }
    }
    if (mounted) {
      setState(() {
        _articles = list;
        _selectedArticle = 0;
      });
    }
    return list;
  }

  /// 正文：选中文章 → ruleContent 解析。
  Future<String?> _debugContent() async {
    if (_articles.isEmpty) {
      _log('请先执行列表调试', level: _RssLogLevel.error);
      return null;
    }
    var i = _selectedArticle;
    if (i < 0 || i >= _articles.length) i = 0;
    final article = _articles[i];
    _log('===== 正文调试：${article.title} =====', level: _RssLogLevel.stage);
    final sw = Stopwatch()..start();
    String raw = '';
    String? content;
    try {
      final rawFuture = article.link.startsWith('http')
          ? _service
              .fetchRaw(article.link)
              .timeout(const Duration(seconds: 20), onTimeout: () => '')
          : Future<String>.value('');
      final contentFuture = _service
          .fetchArticleContent(widget.source, article)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
      raw = await rawFuture;
      content = await contentFuture;
    } catch (e) {
      sw.stop();
      _log('正文解析异常: $e', level: _RssLogLevel.error);
      return null;
    }
    sw.stop();
    _contentRaw = raw;
    _recordNet('正文', article.link, sw.elapsedMilliseconds, raw);
    if (content == null || content.trim().isEmpty) {
      _log('正文为空（请检查 ruleContent / 白黑名单）', level: _RssLogLevel.error);
    } else {
      final preview =
          content.length > 300 ? content.substring(0, 300) : content;
      _log('正文长度 ${content.length} 字符，预览：', level: _RssLogLevel.ok);
      _log(preview);
    }
    if (mounted) setState(() => _content = content);
    return content;
  }

  /// 一键跑完 分类 → 列表 → 正文 三段。
  Future<void> _runAll() async {
    RssService.removeSortCache();
    setState(() {
      _running = true;
      _progress = 0;
      _logs.clear();
      _net.clear();
      _categories = <RssCategory>[];
      _articles = <RssArticle>[];
      _content = null;
      _categoryRaw = '';
      _listRaw = '';
      _contentRaw = '';
    });
    _log('===== 开始调试：${widget.source.sourceName} =====',
        level: _RssLogLevel.stage);
    _log('源地址: ${widget.source.sourceUrl}');
    _log('变量: ${_variableApplied.isEmpty ? '(空)' : _variableApplied}');
    try {
      final cats = await _debugCategories();
      setState(() => _progress = 0.33);
      if (cats.isNotEmpty) {
        final list = await _debugList();
        setState(() => _progress = 0.66);
        if (list.isNotEmpty) await _debugContent();
      }
      setState(() => _progress = 1);
      _log('===== 调试完成 =====', level: _RssLogLevel.stage);
    } catch (e) {
      _log('调试异常: $e', level: _RssLogLevel.error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // ==================== 各页签视图 ====================

  Widget _buildLogView() {
    return _logs.isEmpty
        ? const AppEmptyState(
            icon: Icons.article_outlined,
            title: '暂无调试日志',
            message: '点击「一键调试」或切到分类 / 列表 / 正文页分段执行',
          )
        : ListView.builder(
            controller: _logScroll,
            padding: const EdgeInsets.all(AppSpacing.m),
            itemCount: _logs.length,
            itemBuilder: (_, i) {
              final l = _logs[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(
                  l.text,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: _colorOf(l.level),
                  ),
                ),
              );
            },
          );
  }

  Widget _buildCategoryView() {
    if (_categories.isEmpty) {
      return _stagePlaceholder('分类', '尚未解析到分类', _debugCategories);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s),
          child: FilledButton.tonalIcon(
            onPressed: _running ? null : _debugCategories,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新解析分类'),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = _categories[i];
              final sel = i == _selectedCategory;
              return ListTile(
                selected: sel,
                leading: CircleAvatar(
                    radius: 14,
                    child:
                        Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                title:
                    Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(c.rawUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('列表'),
                  onPressed: () {
                    setState(() => _selectedCategory = i);
                    _tab.animateTo(2);
                    _debugList();
                  },
                ),
                onTap: () => setState(() => _selectedCategory = i),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListView() {
    if (_articles.isEmpty) {
      return _stagePlaceholder('列表', '尚未解析到文章', _debugList);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _running ? null : _debugList,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新解析列表'),
              ),
              const SizedBox(width: AppSpacing.s),
              TextButton.icon(
                icon: const Icon(Icons.code, size: 16),
                label: const Text('查看原始响应'),
                onPressed: () => _showRaw('列表原始响应', _listRaw),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _articles.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = _articles[i];
              return ListTile(
                title:
                    Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(a.link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('正文'),
                  onPressed: () {
                    setState(() => _selectedArticle = i);
                    _tab.animateTo(3);
                    _debugContent();
                  },
                ),
                onTap: () => setState(() => _selectedArticle = i),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContentView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _running ? null : _debugContent,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新解析正文'),
              ),
              const SizedBox(width: AppSpacing.s),
              TextButton.icon(
                icon: const Icon(Icons.code, size: 16),
                label: const Text('查看原始响应'),
                onPressed: () => _showRaw('正文原始响应', _contentRaw),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          if (_content == null || _content!.isEmpty)
            const AppEmptyState(
              icon: Icons.notes_outlined,
              title: '暂无正文',
              message: '执行列表调试后点击「正文」或「重新解析正文」',
            )
          else
            SelectableText(_content!, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildNetworkView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s),
          child: Row(
            children: [
              Text('请求响应日志（${_net.length} 条）',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制'),
                onPressed: () => _copyText(_networkLogText(), '请求响应日志'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _net.isEmpty
              ? const AppEmptyState(
                  icon: Icons.http_outlined,
                  title: '暂无请求记录',
                  message: '执行三段调试后这里会列出各阶段响应',
                )
              : ListView.separated(
                  itemCount: _net.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = _net[i];
                    return ExpansionTile(
                      leading: const Icon(Icons.swap_vert, size: 18),
                      title: Text('[${n.stage}] ${n.url}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      subtitle: Text('耗时 ${n.elapsedMs}ms  ·  ${n.bytes} 字符',
                          style: const TextStyle(fontSize: 11)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.m),
                          child: SelectableText(
                            n.preview.isEmpty ? '(空响应)' : n.preview,
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildVariableView() {
    final s = widget.source;
    final fields = <String, String?>{
      'sourceUrl': s.sourceUrl,
      'sortUrl': s.sortUrl,
      'ruleArticles': s.ruleArticles,
      'ruleTitle': s.ruleTitle,
      'ruleLink': s.ruleLink,
      'ruleDescription': s.ruleDescription,
      'ruleContent': s.ruleContent,
      'ruleImage': s.ruleImage,
      'rulePubDate': s.rulePubDate,
      'header': s.header,
      'variable': s.variable,
      'jsLib': s.jsLib,
      'startJs': s.startJs,
      'injectJs': s.injectJs,
    };
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.m),
      children: [
        const AppSectionHeader('源变量（可编辑，应用于后续调试）'),
        TextField(
          controller: _variableCtl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'variable',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _variableApplied = _variableCtl.text;
                  widget.source.variable = _variableCtl.text;
                });
                _log('已应用源变量: $_variableApplied');
                _toast('变量已应用');
              },
              child: const Text('应用变量'),
            ),
            const SizedBox(width: AppSpacing.s),
            Text('当前生效: ${_variableApplied.isEmpty ? '(空)' : '已设置'}',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        const AppSectionHeader('规则字段（只读）'),
        ...fields.entries.map((e) => ListTile(
              dense: true,
              title: Text(e.key, style: const TextStyle(fontSize: 12)),
              subtitle: Text(
                (e.value == null || e.value!.isEmpty) ? '(空)' : e.value!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            )),
      ],
    );
  }

  Widget _stagePlaceholder(
      String stage, String message, Future<dynamic> Function() run) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: AppSpacing.m),
          FilledButton.tonalIcon(
            onPressed: _running
                ? null
                : () {
                    run();
                  },
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text('执行$stage调试'),
          ),
        ],
      ),
    );
  }

  void _showRaw(String title, String raw) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(raw.isEmpty ? '(空)' : raw,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _copyText(raw, title),
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('调试: ${widget.source.sourceName}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share),
            tooltip: '导出日志',
            onSelected: _onExportAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('复制全部日志')),
              PopupMenuItem(value: 'share', child: Text('分享全部日志（纯文本）')),
              PopupMenuItem(value: 'file', child: Text('导出为 txt 文件')),
              PopupMenuItem(value: 'network', child: Text('仅复制请求响应日志')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: _running
                ? null
                : () => setState(() {
                      _logs.clear();
                      _net.clear();
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
                  child: Text(
                    '分类 ${_categories.length}  ·  列表 ${_articles.length}  ·  正文 ${(_content?.length ?? 0)} 字',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                FilledButton(
                  onPressed: _running ? null : _runAll,
                  child: _running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('一键调试'),
                ),
              ],
            ),
          ),
          if (_running)
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              minHeight: 2,
            ),
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabs: const [
              Tab(text: '调试日志'),
              Tab(text: '分类'),
              Tab(text: '列表'),
              Tab(text: '正文'),
              Tab(text: '请求响应'),
              Tab(text: '变量'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildLogView(),
                _buildCategoryView(),
                _buildListView(),
                _buildContentView(),
                _buildNetworkView(),
                _buildVariableView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
