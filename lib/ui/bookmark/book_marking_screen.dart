import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book_marking.dart';
import 'package:legado_md3/data/local/app_database.dart';

class BookMarkingScreen extends StatefulWidget {
  final String bookName;
  final String author;
  const BookMarkingScreen({super.key, required this.bookName, required this.author});

  @override
  State<BookMarkingScreen> createState() => _BookMarkingScreenState();
}

class _BookMarkingScreenState extends State<BookMarkingScreen> {
  final DatabaseService _db = DatabaseService();
  List<BookMarking> _markings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMarkings();
  }

  Future<void> _loadMarkings() async {
    final markings = await _db.getBookMarkings(widget.bookName, widget.author);
    setState(() {
      _markings = markings;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.bookName.isEmpty ? '书籍标记' : '书籍标记 - ${widget.bookName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _markings.isEmpty
              ? const Center(child: Text('暂无标记'))
              : ListView.builder(
                  itemCount: _markings.length,
                  itemBuilder: (context, index) {
                    final marking = _markings[index];
                    return Dismissible(
                      key: ValueKey(marking.id),
                      onDismissed: (_) async {
                        if (marking.id != null) await _db.deleteBookMarking(marking.id!);
                        setState(() => _markings.removeAt(index));
                      },
                      child: Card(
                        child: ListTile(
                          leading: Container(width: 4, height: 40, color: Color(marking.color ?? 0xFF6750A4)),
                          title: Text(marking.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (widget.bookName.isEmpty)
                              Text('《${marking.bookName}》', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text('第${marking.chapterIndex + 1}章: ${marking.chapterTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            if (marking.note != null && marking.note!.isNotEmpty) Text('笔记: ${marking.note}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.blue)),
                          ]),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async {
                            if (marking.id != null) {
                              await _db.deleteBookMarking(marking.id!);
                              _loadMarkings();
                            }
                          }),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
