import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book_chapter.dart';

/// 离线缓存下载范围选择 - 对齐原版DownloadSheet
/// 返回 [startIndex, endIndex]
class DownloadSheet extends StatefulWidget {
  final List<BookChapter> chapters;
  final int currentIndex;
  const DownloadSheet({super.key, required this.chapters, required this.currentIndex});

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet> {
  late int _start;
  late int _end;

  @override
  void initState() {
    super.initState();
    _start = widget.currentIndex;
    _end = (widget.currentIndex + 49).clamp(0, widget.chapters.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('离线缓存', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        // 快捷范围
        Wrap(spacing: 8, children: [
          _quickChip('后5章', widget.currentIndex, widget.currentIndex + 4),
          _quickChip('后25章', widget.currentIndex, widget.currentIndex + 24),
          _quickChip('后50章', widget.currentIndex, widget.currentIndex + 49),
          _quickChip('后100章', widget.currentIndex, widget.currentIndex + 99),
          _quickChip('全部', 0, widget.chapters.length - 1),
        ]),
        const SizedBox(height: 16),
        ListTile(
          dense: true, title: const Text('起始章节'),
          subtitle: Text(widget.chapters.isNotEmpty ? widget.chapters[_start].title : ''),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickChapter(true),
        ),
        ListTile(
          dense: true, title: const Text('结束章节'),
          subtitle: Text(widget.chapters.isNotEmpty ? widget.chapters[_end].title : ''),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickChapter(false),
        ),
        Padding(padding: const EdgeInsets.all(16), child: Text('将缓存第 ${_start + 1} 章 到第 ${_end + 1} 章，共 ${_end - _start + 1} 章', style: const TextStyle(fontSize: 13, color: Colors.grey))),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => Navigator.pop(context, [_start, _end]), child: const Text('开始缓存')),
          const SizedBox(width: 16),
        ]),
      ]),
    ));
  }

  Widget _quickChip(String label, int s, int e) => ActionChip(
    label: Text(label, style: const TextStyle(fontSize: 12)),
    onPressed: () => setState(() {
      _start = s.clamp(0, widget.chapters.length - 1);
      _end = e.clamp(0, widget.chapters.length - 1);
    }),
  );

  Future<void> _pickChapter(bool isStart) async {
    final controller = ScrollController();
    int selected = isStart ? _start : _end;
    await showModalBottomSheet(context: context, isScrollControlled: true, builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
      builder: (context, _) => StatefulBuilder(builder: (context, setSheet) => Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(isStart ? '选择起始章节' : '选择结束章节', style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(child: ListView.builder(
          controller: controller,
          itemCount: widget.chapters.length,
          itemBuilder: (context, i) => RadioListTile<int>(
            dense: true, value: i, groupValue: selected,
            title: Text(widget.chapters[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
            onChanged: (v) => setSheet(() => selected = v ?? i),
          ),
        )),
        FilledButton(onPressed: () { setState(() { if (isStart) _start = selected; else _end = selected; }); Navigator.pop(context); }, child: const Text('确定')),
        const SizedBox(height: 8),
      ])),
    ));
  }
}
