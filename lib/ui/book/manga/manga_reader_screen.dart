import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/local/app_database.dart';

class MangaReaderScreen extends StatefulWidget {
  final Book book;
  final int initialChapter;
  const MangaReaderScreen({super.key, required this.book, this.initialChapter = 0});

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  final DatabaseService _db = DatabaseService();
  List<BookChapter> _chapters = [];
  int _currentChapter = 0;
  bool _loading = true;
  bool _showMenu = false;
  int _scrollMode = 0; // 0:连续滚动 1:翻页

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.initialChapter;
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    final chapters = await _db.getChapters(widget.book.name, widget.book.author);
    setState(() {
      _chapters = chapters;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showMenu = !_showMenu),
        child: Stack(
          children: [
            _buildContent(),
            if (_showMenu) _buildMenu(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_chapters.isEmpty) {
      return const Center(child: Text('暂无章节', style: TextStyle(color: Colors.white)));
    }
    final chapter = _chapters[_currentChapter];
    final images = _parseImages(chapter.content ?? '');

    if (_scrollMode == 0) {
      return ListView.builder(
        itemCount: images.length,
        itemBuilder: (context, index) => CachedNetworkImage(
          imageUrl: images[index],
          fit: BoxFit.fitWidth,
          placeholder: (context, url) => Container(height: 200, color: Colors.grey[900], child: const Center(child: CircularProgressIndicator())),
          errorWidget: (context, url, error) => Container(height: 200, color: Colors.grey[900], child: const Icon(Icons.broken_image, color: Colors.grey)),
        ),
      );
    } else {
      return PageView.builder(
        itemCount: images.length,
        itemBuilder: (context, index) => Center(
          child: CachedNetworkImage(
            imageUrl: images[index],
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      );
    }
  }

  List<String> _parseImages(String content) {
    final regex = RegExp(r'<img[^>]+src="([^"]+)"');
    return regex.allMatches(content).map((m) => m.group(1)!).toList();
  }

  Widget _buildMenu() {
    return Positioned.fill(
      child: Column(
        children: [
          Container(
            color: Colors.black87,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  Expanded(child: Text(_chapters.isNotEmpty ? _chapters[_currentChapter].title : '', style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(icon: const Icon(Icons.list, color: Colors.white), onPressed: _showChapterList),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMenuButton(Icons.swap_vert, '滚动模式', () => setState(() => _scrollMode = 0)),
                    _buildMenuButton(Icons.swap_horiz, '翻页模式', () => setState(() => _scrollMode = 1)),
                    _buildMenuButton(Icons.skip_previous, '上一章', _prevChapter),
                    _buildMenuButton(Icons.skip_next, '下一章', _nextChapter),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('章节', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _chapters.isNotEmpty ? _currentChapter.toDouble() : 0,
                        max: (_chapters.length - 1).toDouble(),
                        onChanged: (v) => setState(() => _currentChapter = v.toInt()),
                      ),
                    ),
                    Text('${_currentChapter + 1}/${_chapters.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _prevChapter() {
    if (_currentChapter > 0) setState(() => _currentChapter--);
  }

  void _nextChapter() {
    if (_currentChapter < _chapters.length - 1) setState(() => _currentChapter++);
  }

  void _showChapterList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => ListView.builder(
        itemCount: _chapters.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(_chapters[index].title, style: TextStyle(color: index == _currentChapter ? Theme.of(context).colorScheme.primary : Colors.white70, fontSize: 14)),
          selected: index == _currentChapter,
          onTap: () {
            setState(() => _currentChapter = index);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}
