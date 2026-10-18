import 'package:flutter/material.dart';
import 'package:legado_md3/help/source/opds_engine.dart';

/// OPDS 书源浏览页：输入 OPDS 目录地址，浏览和搜索书籍
class OpdsScreen extends StatefulWidget {
  final String? initialUrl;
  const OpdsScreen({super.key, this.initialUrl});

  @override
  State<OpdsScreen> createState() => _OpdsScreenState();
}

class _OpdsScreenState extends State<OpdsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  OpdsEngine? _engine;
  List<OpdsEntry> _entries = [];
  bool _loading = false;
  String? _error;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
      _loadCatalog(widget.initialUrl!);
    }
  }

  Future<void> _loadCatalog(String url) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _engine = OpdsEngine(baseUrl: url);
      final entries = await _engine!.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
        if (!_history.contains(url)) _history.add(url);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _doSearch() async {
    final kw = _searchController.text.trim();
    if (kw.isEmpty || _engine == null) return;
    setState(() => _loading = true);
    try {
      final entries = await _engine!.search(kw);
      if (!mounted) return;
      setState(() {
        _entries = entries;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPDS 书源'),
        actions: [
          if (_history.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.history),
              itemBuilder: (_) => _history.reversed
                  .map((u) => PopupMenuItem(value: u, child: Text(u, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onSelected: (u) {
                _urlController.text = u;
                _loadCatalog(u);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
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
                    onSubmitted: _loadCatalog,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _loadCatalog(_urlController.text.trim()),
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
                      hintText: '输入关键字搜索',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _doSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _doSearch,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('错误: $_error', style: const TextStyle(color: Colors.red)))
                    : _entries.isEmpty
                        ? const Center(child: Text('暂无内容，请输入 OPDS 地址'))
                        : ListView.builder(
                            itemCount: _entries.length,
                            itemBuilder: (context, i) {
                              final entry = _entries[i];
                              return ListTile(
                                leading: entry.cover != null
                                    ? Image.network(entry.cover!, width: 50, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.book))
                                    : const Icon(Icons.book),
                                title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  '${entry.author ?? "未知"}${entry.summary != null ? " · ${entry.summary!}" : ""}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: entry.downloadUrl != null
                                    ? const Icon(Icons.download, size: 18)
                                    : const Icon(Icons.chevron_right),
                                onTap: () {
                                  // 导航链接：进入子目录
                                  final navLink = entry.links.where((l) =>
                                      l.type == 'application/atom+xml' || l.rel?.contains('subsection') == true).toList();
                                  if (navLink.isNotEmpty) {
                                    _urlController.text = navLink.first.href;
                                    _loadCatalog(navLink.first.href);
                                  } else if (entry.downloadUrl != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('下载: ${entry.downloadUrl}')),
                                    );
                                  }
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
