import 'package:flutter/material.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';

/// 章节换源 - 对齐原版ChangeChapterSourceSheet
/// 列出可用书源，选择后用指定源重新加载章节
class ChangeChapterSourceSheet extends StatefulWidget {
  final String bookName;
  final String author;
  const ChangeChapterSourceSheet({super.key, required this.bookName, required this.author});

  @override
  State<ChangeChapterSourceSheet> createState() => _ChangeChapterSourceSheetState();
}

class _ChangeChapterSourceSheetState extends State<ChangeChapterSourceSheet> {
  final _db = DatabaseService();
  List<BookSource> _sources = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sources = await _db.getAllSources(enabled: true);
    setState(() { _sources = sources; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
      builder: (context, scrollController) => Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('章节换源', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('选择其他书源加载本章内容', style: TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(height: 8),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
            ? const Center(child: Text('没有可用书源'))
            : ListView.builder(
                controller: scrollController,
                itemCount: _sources.length,
                itemBuilder: (context, i) {
                  final s = _sources[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.source_outlined),
                    title: Text(s.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.bookSourceGroup ?? s.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(context, s),
                  );
                },
              )),
      ]),
    );
  }
}
