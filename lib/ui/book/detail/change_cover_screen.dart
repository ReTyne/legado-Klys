import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/di/book_provider.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 换封面（对齐 legado 原版 ChangeCoverDialog）：
/// 支持自定义 URL、预设封面，以及「按书名从已启用书源搜索封面」的网格选择
/// （feature_gap §4-5）。书源搜索复用 BookSourceEngine.search，不引新依赖。
class ChangeCoverScreen extends StatefulWidget {
  final Book book;
  const ChangeCoverScreen({super.key, required this.book});

  @override
  State<ChangeCoverScreen> createState() => _ChangeCoverScreenState();
}

class _ChangeCoverScreenState extends State<ChangeCoverScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _urlController = TextEditingController();
  String? _previewUrl;
  List<String> _sourceCovers = [];
  bool _coverSearching = false;
  bool _coverSearched = false;

  @override
  void initState() {
    super.initState();
    // 优先显示已设置的自定义封面，否则用书源封面
    final cur = widget.book.customCoverUrl ?? widget.book.coverUrl ?? '';
    _urlController.text = cur;
    _previewUrl = cur.isEmpty ? null : cur;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _setUrl(String? url) {
    _urlController.text = url ?? '';
    setState(() => _previewUrl = (url != null && url.isNotEmpty) ? url : null);
  }

  /// 并发在已启用书源中按书名检索，收集去重后的 coverUrl（当前书源优先）。
  Future<List<String>> _searchCovers() async {
    try {
      final sources = await _db.getAllSources(enabled: true);
      sources.sort((a, b) {
        final ac = a.bookSourceUrl == widget.book.origin ? 0 : 1;
        final bc = b.bookSourceUrl == widget.book.origin ? 0 : 1;
        return ac - bc;
      });
      final use = sources.take(8).toList();
      final engine = BookSourceEngine();
      final covers = <String>{};
      await Future.wait(use.map((s) async {
        try {
          final list = await engine.search(s, widget.book.name).timeout(
                const Duration(seconds: 10),
                onTimeout: () => <SearchBook>[],
              );
          for (final b in list) {
            final url = b.coverUrl ?? '';
            if (url.isNotEmpty) covers.add(url);
          }
        } catch (_) {}
      }));
      return covers.toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _searchSourceCovers() async {
    if (_coverSearching) return;
    setState(() => _coverSearching = true);
    try {
      final covers = await runWithBusyDialog<List<String>>(
        context,
        message: '正在从书源搜索封面...',
        task: _searchCovers(),
      );
      if (!mounted) return;
      setState(() {
        _sourceCovers = covers;
        _coverSearched = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _sourceCovers = [];
          _coverSearched = true;
        });
      }
    } finally {
      if (mounted) setState(() => _coverSearching = false);
    }
  }

  Future<void> _saveCover() async {
    // 就地修改，避免重建 Book 丢失阅读进度/目录地址/分组等字段
    final url = _urlController.text.trim();
    widget.book.customCoverUrl = url.isEmpty ? null : url;
    await _db.updateBook(widget.book);
    if (mounted && context.mounted) await context.read<BookProvider>().loadBooks();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(url.isEmpty ? '已恢复书源默认封面' : '封面已更新')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('换封面 - ${widget.book.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 150,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: cs.surfaceContainerHighest,
              ),
              child: _previewUrl != null && _previewUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(_previewUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.broken_image,
                              size: 48, color: cs.onSurfaceVariant)))
                  : Icon(Icons.book, size: 48, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '封面URL',
              hintText: '输入图片URL',
            ),
            onChanged: (v) => setState(() => _previewUrl = v.isEmpty ? null : v),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _setUrl(null),
                child: const Text('恢复默认封面'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(onPressed: _saveCover, child: const Text('保存')),
            ),
          ]),
          const SizedBox(height: 16),
          // 对齐原版 ChangeCoverDialog：封面来自书源搜索结果（§4-5）
          const AppSectionHeader('从书源搜索封面'),
          Row(
            children: [
              Expanded(
                child: Text('按《${widget.book.name}》在已启用书源中检索封面',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
              FilledButton.icon(
                onPressed: _coverSearching ? null : _searchSourceCovers,
                icon: const Icon(Icons.image_search_outlined, size: 18),
                label: const Text('搜索'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_coverSearched && _sourceCovers.isEmpty)
            const AppEmptyState(
              icon: Icons.image_not_supported_outlined,
              title: '未搜索到封面',
              message: '可尝试手动输入封面 URL',
            )
          else if (_sourceCovers.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.7,
              ),
              itemCount: _sourceCovers.length,
              itemBuilder: (_, i) => _buildCoverChoice(_sourceCovers[i]),
            ),
          const SizedBox(height: 16),
          const AppSectionHeader('预设封面'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _buildPresetCover('https://picsum.photos/seed/book1/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book2/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book3/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book4/300/400'),
          ]),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCoverChoice(String url) => _buildPresetCover(url);

  Widget _buildPresetCover(String url) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _setUrl(url),
      child: Container(
        width: 60,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _previewUrl == url ? cs.primary : cs.outlineVariant,
            width: _previewUrl == url ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.broken_image, size: 20, color: cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}
