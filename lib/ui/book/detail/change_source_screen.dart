import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/bookmark.dart';
import 'package:legado_md3/data/model/book_highlight.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 换源：并发在所有启用书源检索同一本书，切换为目标源的目录地址。
///
/// 对齐 legado 原版 ChangeBookSourceDialog：换源后不再强制把进度清零，
/// 而是按「旧章节标题归一化」在新书源目录里匹配最接近的章节，保留阅读位置；
/// 无法匹配时回退到第 0 章（feature_gap §4-6）。
class ChangeSourceScreen extends StatefulWidget {
  final Book book;
  const ChangeSourceScreen({super.key, required this.book});

  @override
  State<ChangeSourceScreen> createState() => _ChangeSourceScreenState();
}

class _SourceResult {
  BookSource source;
  SearchBook? match;
  bool searching = true;
  String? error;
  _SourceResult(this.source);
}

class _ChangeSourceScreenState extends State<ChangeSourceScreen> {
  final DatabaseService _db = DatabaseService();
  final BookSourceEngine _engine = BookSourceEngine();
  final List<_SourceResult> _results = [];
  bool _loading = true;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _searchAll();
  }

  Future<void> _searchAll() async {
    final sources = await _db.getAllSources(enabled: true);
    _results
      ..clear()
      ..addAll(sources.map(_SourceResult.new));
    _total = _results.length;
    if (mounted) setState(() => _loading = false);

    // 并发池检索，每源最多 15s
    const concurrency = 8;
    int cursor = 0;
    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= _results.length) return;
        final r = _results[i];
        try {
          final list = await _engine.search(r.source, widget.book.name).timeout(
            const Duration(seconds: 15), onTimeout: () => []);
          // 优先同名，作者也匹配最佳
          SearchBook? best;
          for (final b in list) {
            if (b.name.replaceAll(RegExp(r'\s'), '') == widget.book.name.replaceAll(RegExp(r'\s'), '')) {
              best = b;
              if (widget.book.author.isEmpty || b.author.contains(widget.book.author) || widget.book.author.contains(b.author)) break;
            }
          }
          best ??= list.isNotEmpty ? list.first : null;
          if (mounted) setState(() { r.match = best; r.searching = false; _done++; });
        } catch (e) {
          if (mounted) setState(() { r.searching = false; r.error = '$e'; _done++; });
        }
      }
    }
    await Future.wait(List.generate(concurrency.clamp(1, _results.isEmpty ? 1 : _results.length), (_) => worker()));
  }

  /// 归一化章节标题：去空白 / 常见分隔符、统一小写、全角数字转半角，
  /// 容忍不同书源「第1章 / 1. / Chapter 1 / 第一章」等写法差异（§4-6）。
  static String _normalizeTitle(String raw) {
    var s = raw.toLowerCase();
    // 全角数字 → 半角
    const fullWidth = '０１２３４５６７８９';
    const halfWidth = '0123456789';
    for (var i = 0; i < fullWidth.length; i++) {
      s = s.replaceAll(fullWidth[i], halfWidth[i]);
    }
    // 去空白 + 逐个剔除常见标点分隔（避免复杂正则字符类）
    s = s.replaceAll(RegExp(r'\s+'), '');
    const punct = [
      '·', '・', ',', '，', '.', '。', '、', ':', '：', ';', '；',
      '!', '！', '?', '？', '"', '“', '”', '‘', '’',
      '[', ']', '【', '】', '(', ')', '（', '）',
      '<', '>', '《', '》', '-', '—', '_', '/', '\\', '|',
    ];
    for (final p in punct) {
      s = s.replaceAll(p, '');
    }
    return s;
  }

  /// 抽取标题里首个数字作为章节序号（跨源章节编号是最后的兜底匹配依据）。
  static int? _chapterNumber(String title) {
    const cnDigits = {
      '零': '0', '〇': '0', '一': '1', '二': '2', '三': '3', '四': '4',
      '五': '5', '六': '6', '七': '7', '八': '8', '九': '9',
    };
    var s = title;
    cnDigits.forEach((k, v) => s = s.replaceAll(k, v));
    final m = RegExp(r'\d+').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  /// 在新目录里按「归一化标题」匹配最接近的章节下标；找不到返回 -1。
  /// 策略：精确归一化 > 互相包含 > 章节号数值最接近（§4-6）。
  int _matchChapterIndex(List<BookChapter> chapters, String oldTitle) {
    final t = _normalizeTitle(oldTitle);
    if (t.isEmpty) return -1;
    // 1) 精确归一化匹配
    for (var i = 0; i < chapters.length; i++) {
      if (!chapters[i].isVolume && _normalizeTitle(chapters[i].title) == t) return i;
    }
    // 2) 互相包含（容忍「第X章」前缀 / 副标题后缀差异）
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      if (c.isVolume) continue;
      final ct = _normalizeTitle(c.title);
      if (ct.isEmpty) continue;
      if (ct.contains(t) || t.contains(ct)) return i;
    }
    // 3) 章节号数值最接近
    final n = _chapterNumber(oldTitle);
    if (n != null) {
      var bestIdx = -1;
      var bestDiff = 1 << 30;
      for (var i = 0; i < chapters.length; i++) {
        if (chapters[i].isVolume) continue;
        final cn = _chapterNumber(chapters[i].title);
        if (cn == null) continue;
        final diff = (cn - n).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0) return bestIdx;
    }
    return -1;
  }

  Future<void> _changeSource(_SourceResult r) async {
    final m = r.match;
    if (m == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「${r.source.bookSourceName}」未找到本书')));
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: '确认换源',
      content: '将《${widget.book.name}》更换为「${r.source.bookSourceName}」的源吗？',
    );
    if (!confirmed || !mounted) return;

    // 迁移 sheet 取消时完整恢复换源前的书籍字段，不留内存副作用
    final prev = (
      origin: widget.book.origin,
      originName: widget.book.originName,
      noteUrl: widget.book.noteUrl,
      bookUrl: widget.book.bookUrl,
      coverUrl: widget.book.coverUrl,
      lastChapter: widget.book.lastChapter,
      intro: widget.book.intro,
    );

    // 1) 记录换源前的章节标题（当前阅读进度所在章），作为进度匹配依据
    final oldChapters = await _db.getChapters(widget.book.name, widget.book.author);
    final oldIndex = widget.book.durChapterIndex;
    final oldTitle = (oldIndex >= 0 && oldIndex < oldChapters.length)
        ? oldChapters[oldIndex].title
        : '';

    // 2) 切换书籍来源字段（目录地址沿用搜索结果，缺省回退书籍地址）
    final tocUrl = (m.noteUrl?.isNotEmpty ?? false) ? m.noteUrl! : (m.bookUrl ?? '');
    widget.book
      ..origin = r.source.bookSourceUrl
      ..originName = r.source.bookSourceName
      ..noteUrl = (m.noteUrl?.isNotEmpty ?? false) ? m.noteUrl : m.bookUrl
      ..bookUrl = m.bookUrl ?? tocUrl
      ..coverUrl = (m.coverUrl?.isNotEmpty ?? false) ? m.coverUrl : widget.book.coverUrl
      ..lastChapter = (m.lastChapter?.isNotEmpty ?? false) ? m.lastChapter : widget.book.lastChapter
      ..intro = (m.intro?.isNotEmpty ?? false) ? m.intro : widget.book.intro;

    // 3) 拉取新书源目录（忙碌对话框），用于按标题匹配进度
    final info = <String, dynamic>{
      ...widget.book.jsContext(),
      'bookUrl': m.bookUrl ?? tocUrl,
      'tocUrl': tocUrl,
      'origin': r.source.bookSourceUrl,
      'originName': r.source.bookSourceName,
    };
    if (!mounted) return;
    final newChapters = await runWithBusyDialog<List<BookChapter>>(
      context,
      message: '正在获取新书源目录...',
      task: (() async {
        if (tocUrl.isEmpty) return <BookChapter>[];
        try {
          return await _engine
              .getToc(r.source, tocUrl, bookInfo: info)
              .timeout(const Duration(seconds: 20),
                  onTimeout: () => <BookChapter>[]);
        } catch (_) {
          return <BookChapter>[];
        }
      })(),
    );
    if (!mounted) return;

    // 4) 统计可迁移数据，弹出迁移选项 sheet（fork F21）
    final matched = newChapters.isNotEmpty ? _matchChapterIndex(newChapters, oldTitle) : -1;
    final bookmarks = await _db.getBookmarks(widget.book.name, widget.book.author);
    final highlights = await _db.getBookHighlights(widget.book.name, widget.book.author);
    if (!mounted) return;
    final options = await _showSourceMigrationSheet(
      context,
      bookName: widget.book.name,
      sourceName: r.source.bookSourceName,
      matchedTitle: matched >= 0 ? newChapters[matched].title : null,
      hasMatch: matched >= 0,
      bookmarkCount: bookmarks.length,
      highlightCount: highlights.length,
    );
    if (options == null || !mounted) {
      widget.book
        ..origin = prev.origin
        ..originName = prev.originName
        ..noteUrl = prev.noteUrl
        ..bookUrl = prev.bookUrl
        ..coverUrl = prev.coverUrl
        ..lastChapter = prev.lastChapter
        ..intro = prev.intro;
      return;
    }

    final keepProgress = options.keepProgress && matched >= 0;
    final newIndex = keepProgress ? matched : 0;
    final oldPagePos = widget.book.durChapterPos;

    // 5) 按章节标题把书签 / 高亮重映射到新源目录索引
    if (options.migrateBookmarks && bookmarks.isNotEmpty) {
      await _migrateBookmarks(bookmarks, newChapters);
    }
    if (options.migrateHighlights && highlights.isNotEmpty) {
      await _migrateHighlights(highlights, newChapters);
    }

    // 6) 目录落库：拉到新目录则直接保存（阅读页无需重复联网），否则清空让阅读页重拉
    if (newChapters.isNotEmpty) {
      await _db.saveChapters(widget.book.name, widget.book.author, newChapters);
      widget.book.lastChapterIndex = newChapters.length - 1;
    } else {
      await _db.deleteChapters(widget.book.name, widget.book.author);
      widget.book.lastChapterIndex = 0;
    }
    widget.book.durChapterIndex = newIndex;
    widget.book.durChapterPos = (keepProgress && options.keepPagePos) ? oldPagePos : 0;
    await _db.updateBook(widget.book);
    if (mounted) {
      final migrated = <String>[];
      if (options.migrateBookmarks && bookmarks.isNotEmpty) migrated.add('书签');
      if (options.migrateHighlights && highlights.isNotEmpty) migrated.add('高亮');
      final suffix = migrated.isEmpty ? '' : '，已迁移${migrated.join(' / ')}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(keepProgress
            ? '换源成功，已保留阅读进度$suffix'
            : '换源成功，将从头开始$suffix'),
      ));
      Navigator.pop(context, true);
    }
  }

  /// 书签按章节标题重映射：能匹配到新章节才迁移，匹配不到保留原记录不丢数据。
  Future<void> _migrateBookmarks(
      List<Bookmark> bookmarks, List<BookChapter> newChapters) async {
    if (newChapters.isEmpty) return;
    for (final b in bookmarks) {
      final idx = _matchChapterIndex(newChapters, b.chapterTitle);
      if (idx < 0) continue;
      if (b.id != null) await _db.deleteBookmark(b.id!);
      b.id = null;
      b.chapterIndex = idx;
      b.chapterTitle = newChapters[idx].title;
      await _db.insertBookmark(b);
    }
  }

  /// 划线 / 高亮按章节标题重映射（BookHighlight.id 为 final，重建对象）。
  Future<void> _migrateHighlights(
      List<BookHighlight> hs, List<BookChapter> newChapters) async {
    if (newChapters.isEmpty) return;
    for (final h in hs) {
      final idx = _matchChapterIndex(newChapters, h.chapterTitle);
      if (idx < 0) continue;
      if (h.id != null) await _db.deleteBookHighlight(h.id!);
      await _db.insertBookHighlight(BookHighlight(
        bookName: h.bookName,
        author: h.author,
        chapterIndex: idx,
        chapterTitle: newChapters[idx].title,
        content: h.content,
        start: h.start,
        end: h.end,
        color: h.color,
        note: h.note,
        createTime: h.createTime,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('换源 - ${widget.book.name}'),
        actions: [
          if (_done < _total)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Center(child: Text('$_done/$_total', style: const TextStyle(fontSize: 12))))
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新搜索',
              onPressed: () { setState(() { _done = 0; _results.clear(); _loading = true; }); _searchAll(); },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? const AppEmptyState(
                  icon: Icons.source_outlined,
                  title: '暂无可用书源',
                  message: '请先在书源管理中启用书源',
                )
              : RefreshIndicator(onRefresh: _searchAll, child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final r = _results[i];
                    final isCurrent = r.source.bookSourceUrl == widget.book.origin;
                    Widget trailing;
                    if (r.searching) {
                      trailing = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2));
                    } else if (r.match != null) {
                      trailing = isCurrent
                          ? Icon(Icons.check_circle, color: cs.primary)
                          : const Icon(Icons.swap_horiz);
                    } else {
                      trailing = Icon(Icons.do_not_disturb_alt, color: cs.onSurfaceVariant);
                    }
                    return ListTile(
                      leading: CircleAvatar(child: Text(r.source.bookSourceName.isNotEmpty ? r.source.bookSourceName[0] : '?')),
                      title: Text(r.source.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(r.searching ? '搜索中...' : r.match != null
                        ? '${r.match!.author}  ${r.match!.lastChapter ?? ''}'
                        : (r.error != null ? '搜索失败' : '未找到'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                      trailing: trailing,
                      enabled: !r.searching && r.match != null,
                      onTap: isCurrent ? null : () => _changeSource(r),
                    );
                  },
                )),
    );
  }
}


/// 换源迁移选项（fork F21）：进度 / 章内位置 / 书签 / 高亮分别可选。
class _MigrationOptions {
  _MigrationOptions({required this.keepProgress});

  bool keepProgress;
  bool keepPagePos = true;
  bool migrateBookmarks = true;
  bool migrateHighlights = true;
}

Future<_MigrationOptions?> _showSourceMigrationSheet(
  BuildContext context, {
  required String bookName,
  required String sourceName,
  required String? matchedTitle,
  required bool hasMatch,
  required int bookmarkCount,
  required int highlightCount,
}) {
  return showModalBottomSheet<_MigrationOptions>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MigrationSheet(
      bookName: bookName,
      sourceName: sourceName,
      matchedTitle: matchedTitle,
      hasMatch: hasMatch,
      bookmarkCount: bookmarkCount,
      highlightCount: highlightCount,
    ),
  );
}

class _MigrationSheet extends StatefulWidget {
  const _MigrationSheet({
    required this.bookName,
    required this.sourceName,
    required this.matchedTitle,
    required this.hasMatch,
    required this.bookmarkCount,
    required this.highlightCount,
  });

  final String bookName;
  final String sourceName;
  final String? matchedTitle;
  final bool hasMatch;
  final int bookmarkCount;
  final int highlightCount;

  @override
  State<_MigrationSheet> createState() => _MigrationSheetState();
}

class _MigrationSheetState extends State<_MigrationSheet> {
  late final _MigrationOptions _opt =
      _MigrationOptions(keepProgress: widget.hasMatch);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('换源迁移选项',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('《${widget.bookName}》→ ${widget.sourceName}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: Icon(
                    widget.hasMatch
                        ? Icons.my_location
                        : Icons.warning_amber_outlined,
                    color: widget.hasMatch ? cs.primary : cs.error,
                  ),
                  title: Text(widget.hasMatch
                      ? '已匹配到章节「${widget.matchedTitle}」'
                      : '未匹配到对应章节，将从头开始'),
                  subtitle: const Text('按章节标题归一化在新源目录中定位'),
                ),
                SwitchListTile(
                  title: const Text('保留阅读进度'),
                  subtitle: Text(widget.hasMatch
                      ? '跳到匹配章节；关闭则从第 1 章开始'
                      : '无匹配章节，该选项不可用'),
                  value: _opt.keepProgress && widget.hasMatch,
                  onChanged: widget.hasMatch
                      ? (v) => setState(() => _opt.keepProgress = v)
                      : null,
                ),
                SwitchListTile(
                  title: const Text('保留章内阅读位置'),
                  subtitle: const Text('沿用当前章节内的页 / 字符偏移'),
                  value: _opt.keepPagePos &&
                      _opt.keepProgress &&
                      widget.hasMatch,
                  onChanged: (_opt.keepProgress && widget.hasMatch)
                      ? (v) => setState(() => _opt.keepPagePos = v)
                      : null,
                ),
                SwitchListTile(
                  title: Text('迁移书签（${widget.bookmarkCount} 条）'),
                  subtitle: const Text('按章节标题重新映射到新目录'),
                  value: _opt.migrateBookmarks && widget.bookmarkCount > 0,
                  onChanged: widget.bookmarkCount > 0
                      ? (v) => setState(() => _opt.migrateBookmarks = v)
                      : null,
                ),
                SwitchListTile(
                  title:
                      Text('迁移划线 / 高亮（${widget.highlightCount} 条）'),
                  subtitle: const Text('按章节标题重新映射，保留颜色与批注'),
                  value: _opt.migrateHighlights && widget.highlightCount > 0,
                  onChanged: widget.highlightCount > 0
                      ? (v) => setState(() => _opt.migrateHighlights = v)
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    '无法匹配到新章节的书签 / 高亮会原样保留，不会丢失。',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      const SizedBox(width: 8),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, _opt),
                          child: const Text('确定换源')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
