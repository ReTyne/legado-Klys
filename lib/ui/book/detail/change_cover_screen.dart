import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/di/book_provider.dart';

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

  Future<void> _saveCover() async {
    // 就地修改，避免重建 Book 丢失阅读进度/目录地址/分组等字段
    final url = _urlController.text.trim();
    widget.book.customCoverUrl = url.isEmpty ? null : url;
    await _db.updateBook(widget.book);
    await context.read<BookProvider>().loadBooks();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(url.isEmpty ? '已恢复书源默认封面' : '封面已更新')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('换封面 - ${widget.book.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(
              width: 150, height: 200,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey[200]),
              child: _previewUrl != null && _previewUrl!.isNotEmpty
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(_previewUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48)))
                  : const Icon(Icons.book, size: 48, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(labelText: '封面URL', border: OutlineInputBorder(), hintText: '输入图片URL'),
            onChanged: (v) => setState(() => _previewUrl = v.isEmpty ? null : v),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _setUrl(null),
              child: const Text('恢复默认封面'),
            )),
            const SizedBox(width: 16),
            Expanded(child: FilledButton(onPressed: _saveCover, child: const Text('保存'))),
          ]),
          const SizedBox(height: 24),
          const Text('预设封面', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _buildPresetCover('https://picsum.photos/seed/book1/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book2/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book3/300/400'),
            _buildPresetCover('https://picsum.photos/seed/book4/300/400'),
          ]),
        ],
      ),
    );
  }

  Widget _buildPresetCover(String url) {
    return GestureDetector(
      onTap: () => _setUrl(url),
      child: Container(width: 60, height: 80, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: _previewUrl == url ? Theme.of(context).colorScheme.primary : Colors.grey)), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(url, fit: BoxFit.cover))),
    );
  }
}
