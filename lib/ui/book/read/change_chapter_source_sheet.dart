/// 由 reading_screen.dart 拆分还原（历史合并点）。
/// 以 part 形式归属同一库，私有成员互通，外部 import 路径不变。
part of 'reading_screen.dart';

/// 章节换源 - 对齐原版ChangeChapterSourceSheet
/// 列出可用书源，选择后用指定源重新加载章节
class ChangeChapterSourceSheet extends StatefulWidget {
  final String bookName;
  final String author;
  /// 当前书籍来源，列出时排除，避免重复选择
  final String? currentOrigin;
  const ChangeChapterSourceSheet({super.key, required this.bookName, required this.author, this.currentOrigin});

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
    final all = await _db.getAllSources(enabled: true);
    // 排除当前书源
    final sources = widget.currentOrigin == null || widget.currentOrigin!.isEmpty
        ? all
        : all.where((s) => s.bookSourceUrl != widget.currentOrigin).toList();
    setState(() { _sources = sources; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
      builder: (context, scrollController) => Column(children: [
        const Padding(padding: EdgeInsets.all(AppSpacing.l), child: Text('章节换源', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l), child: Text('选择其他书源加载本章内容', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
        const SizedBox(height: AppSpacing.s),
        Expanded(child: _loading
          ? const AppLoadingIndicator()
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
