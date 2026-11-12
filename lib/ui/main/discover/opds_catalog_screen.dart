import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:legado_md3/help/source/opds_engine.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// OPDS 目录浏览页：让 OpdsEngine 的目录 / 搜索 / 下载能力真正接入发现流，
/// 下载的书籍经 ImportBookService 入库，形成 UI → 引擎 → 书架 的完整闭环。
///
/// 导航型条目下钻目录，采集团型条目下载导入。
class OpdsCatalogScreen extends StatefulWidget {
  final String? initialUrl;
  const OpdsCatalogScreen({super.key, this.initialUrl});

  @override
  State<OpdsCatalogScreen> createState() => _OpdsCatalogScreenState();
}

class _OpdsCatalogScreenState extends State<OpdsCatalogScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  OpdsEngine? _engine;
  List<OpdsEntry> _entries = [];
  final List<String> _history = [];
  String _currentPath = '';
  bool _loading = false;
  String? _error;
  String? _importing;

  @override
  void initState() {
    super.initState();
    final url = widget.initialUrl;
    if (url != null && url.trim().isNotEmpty) {
      _urlController.text = url;
      _open(url.trim());
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 打开一个 OPDS 根目录（重置导航栈）
  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _error = '请输入有效的 http(s) OPDS 目录地址');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final engine = OpdsEngine(baseUrl: url);
    try {
      final list = await engine.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _entries = list;
        _currentPath = url;
        _history.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '打开目录失败: $e';
        _loading = false;
      });
    }
  }

  /// 加载指定 feed（下钻或返回时复用）
  Future<void> _load(String url, {bool pushHistory = false}) async {
    final engine = _engine;
    if (engine == null) return;
    if (pushHistory && _currentPath.isNotEmpty) _history.add(_currentPath);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await engine.fetchCatalog(path: url);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _currentPath = url;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (pushHistory && _history.isNotEmpty) _history.removeLast();
      setState(() {
        _error = '加载目录失败: $e';
        _loading = false;
      });
    }
  }

  void _back() {
    if (_history.isNotEmpty) {
      final previous = _history.removeLast();
      _load(previous);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _search(String keyword) async {
    final engine = _engine;
    if (engine == null || keyword.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await engine.search(keyword.trim());
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '搜索失败: $e';
        _loading = false;
      });
    }
  }

  /// 采集链接类型 → 本地文件扩展名（对齐 ImportBookService.supported）
  String _extFor(OpdsEntry entry) {
    for (final l in entry.links) {
      final t = (l.type ?? '').toLowerCase();
      if (t.contains('epub')) return 'epub';
      if (t.contains('pdf')) return 'pdf';
      if (t.contains('mobipocket')) return 'mobi';
    }
    final u = (entry.downloadUrl ?? '').toLowerCase().split('?').first;
    for (final e in ImportBookService.supported) {
      if (u.endsWith('.$e')) return e;
    }
    return 'epub';
  }

  String _safeFileName(String title) => title
      .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_')
      .trim();

  /// 下载并导入书架：引擎取字节 → 落临时文件 → ImportBookService 入库
  Future<void> _import(OpdsEntry entry) async {
    final engine = _engine;
    if (engine == null) return;
    setState(() => _importing = entry.title);
    try {
      final bytes = await engine.downloadBook(entry);
      if (bytes == null || bytes.isEmpty) {
        throw '下载内容为空或链接不可用';
      }
      final dir = await getTemporaryDirectory();
      final base = _safeFileName(entry.title.isEmpty ? 'opds_book' : entry.title);
      final file = File(p.join(dir.path, '$base.${_extFor(entry)}'));
      await file.writeAsBytes(bytes);
      final result = await ImportBookService().importPath(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('《${result.book.name}》已导入书架（${result.chapterCount} 章）'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _importing = null);
    }
  }

  void _onTap(OpdsEntry entry) {
    final nav = entry.navigationUrl;
    if (nav != null) {
      _load(nav, pushHistory: true);
      return;
    }
    if (entry.downloadUrl != null) {
      _import(entry);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该条目没有可下载的资源链接')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPDS 目录'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: _back,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.m, AppSpacing.m, AppSpacing.xs),
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
                    onSubmitted: (v) => _open(v.trim()),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                FilledButton(
                  onPressed: _loading ? null : () => _open(_urlController.text.trim()),
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
          if (_engine != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.xs, AppSpacing.m, AppSpacing.s),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索该 OPDS 目录',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward_outlined),
                    tooltip: '搜索目录',
                    onPressed: () => _search(_searchController.text),
                  ),
                ),
                onSubmitted: _search,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.s),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_engine == null) {
      return const AppEmptyState(
        icon: Icons.explore_outlined,
        title: '尚未打开目录',
        message: '输入 OPDS 目录地址后点击「打开」，即可浏览、搜索并导入书籍',
      );
    }
    if (!_loading && _entries.isEmpty && _error == null) {
      return const AppEmptyState(
        icon: Icons.folder_off_outlined,
        title: '该目录暂无条目',
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        final nav = e.navigationUrl;
        final downloading = _importing == e.title;
        return ListTile(
          leading: BookCover(
            name: e.title.isEmpty ? '书籍' : e.title,
            coverUrl: e.cover,
            width: 44,
            height: 60,
            radius: 4,
          ),
          title: Text(e.title.isEmpty ? '（无标题）' : e.title),
          subtitle: Text(
            [
              if (e.author != null && e.author!.isNotEmpty) e.author!,
              if (e.summary != null && e.summary!.isNotEmpty) e.summary!,
              if (e.categories.isNotEmpty) e.categories.join(' · '),
            ].join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: downloading
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(nav != null
                  ? Icons.folder_open_outlined
                  : (e.downloadUrl != null ? Icons.download_outlined : Icons.info_outline)),
          onTap: downloading ? null : () => _onTap(e),
        );
      },
    );
  }
}
