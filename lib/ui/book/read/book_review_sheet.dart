import 'package:flutter/material.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/v14_models.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 段评气泡（对齐 Sigma `ReviewColumn`）：正文页脚/段尾展示评论数量，
/// 超过 999 截断为 `999+`。阅读页每页右下角常驻一个，点开 [BookReviewSheet]。
class ReviewColumn extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? foreground;

  const ReviewColumn({
    super.key,
    required this.count,
    required this.onTap,
    this.onLongPress,
    this.foreground,
  });

  String get countText => count > 999 ? '999+' : (count > 0 ? '$count' : '');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = foreground ?? cs.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress ?? onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.92),
          borderRadius: AppRadius.mAll,
          border: Border.all(color: cs.outlineVariant, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mode_comment_outlined, size: 14, color: fg),
            if (countText.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(countText, style: TextStyle(fontSize: 11, color: fg)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 段评面板：按「书 + 章 + 段落」查看 / 发表 / 点赞。
///
/// 数据走 v14 `book_reviews` 表：`DatabaseService().getBookReviews` /
/// `insertBookReview` / `likeBookReview`，真实落库、非内存桩。
class BookReviewSheet extends StatefulWidget {
  final String bookName;
  final String author;
  final int chapterIndex;
  final String chapterTitle;

  /// 当前页拆分出的段落文本（用于段落定位与预览）
  final List<String> paragraphs;

  /// 初始选中的段落下标
  final int initialParagraphIndex;

  const BookReviewSheet({
    super.key,
    required this.bookName,
    required this.author,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.paragraphs,
    this.initialParagraphIndex = 0,
  });

  /// 统一入口，返回是否发表过评论（供阅读页刷新气泡计数）
  static Future<bool> open(
    BuildContext context, {
    required String bookName,
    required String author,
    required int chapterIndex,
    required String chapterTitle,
    required List<String> paragraphs,
    int initialParagraphIndex = 0,
  }) async {
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => BookReviewSheet(
            bookName: bookName,
            author: author,
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            paragraphs: paragraphs,
            initialParagraphIndex: initialParagraphIndex,
          ),
        ) ??
        false;
  }

  @override
  State<BookReviewSheet> createState() => _BookReviewSheetState();
}

class _BookReviewSheetState extends State<BookReviewSheet> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _input = TextEditingController();
  List<BookReview> _all = [];
  int _paragraphIndex = 0;
  int _totalInChapter = 0;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _paragraphIndex = widget.initialParagraphIndex.clamp(
        0, widget.paragraphs.isEmpty ? 0 : widget.paragraphs.length - 1);
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _db.getBookReviews(
        widget.bookName, widget.author, widget.chapterIndex);
    if (!mounted) return;
    setState(() {
      _all = list;
      _totalInChapter = list.length;
      _loading = false;
    });
  }

  List<BookReview> get _current => _all
      .where((r) => r.paragraphIndex == _paragraphIndex)
      .toList()
    ..sort((a, b) => (b.likes).compareTo(a.likes));

  String _paragraphPreview(int index) {
    if (index < 0 || index >= widget.paragraphs.length) return '全文';
    final t = widget.paragraphs[index].trim();
    if (t.isEmpty) return '第 ${index + 1} 段';
    return t.length > 18 ? '${t.substring(0, 18)}…' : t;
  }

  Future<void> _publish() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    await _db.insertBookReview(BookReview(
      bookName: widget.bookName,
      author: widget.author,
      chapterIndex: widget.chapterIndex,
      paragraphIndex: _paragraphIndex,
      content: text,
      userName: '我',
    ));
    _input.clear();
    _dirty = true;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('段评已发表'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _like(BookReview r) async {
    final id = r.id;
    if (id == null) return;
    await _db.likeBookReview(id);
    _dirty = true;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.l,
          right: AppSpacing.l,
          top: AppSpacing.m,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.mode_comment_outlined, size: 20),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text('段评 · ${widget.chapterTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  Text('本章 $_totalInChapter 条',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  IconButton(
                    tooltip: '关闭段评',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, _dirty),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              // 段落选择：按页内段落切换，评论按 paragraphIndex 归档
              if (widget.paragraphs.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.paragraphs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s),
                    itemBuilder: (c, i) {
                      final selected = i == _paragraphIndex;
                      final count =
                          _all.where((r) => r.paragraphIndex == i).length;
                      return FilterChip(
                        label: Text(
                          '${_paragraphPreview(i)}${count > 0 ? ' · $count' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _paragraphIndex = i),
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppSpacing.s),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const AppLoadingIndicator()
                    : _current.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.mode_comment_outlined,
                            title: '本段暂无段评',
                            message: '在下方输入框发表第一条评论',
                          )
                        : ListView.separated(
                            itemCount: _current.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (c, i) {
                              final r = _current[i];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: cs.primaryContainer,
                                  child: Text(
                                    (r.userName ?? '读').isNotEmpty
                                        ? (r.userName ?? '读')[0]
                                        : '读',
                                    style: TextStyle(
                                        fontSize: 12, color: cs.primary),
                                  ),
                                ),
                                title: Text(r.content),
                                subtitle: Text(r.userName ?? '匿名读者',
                                    style: const TextStyle(fontSize: 11)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${r.likes}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant)),
                                    IconButton(
                                      tooltip: '点赞这条段评',
                                      icon: const Icon(
                                          Icons.thumb_up_outlined,
                                          size: 18),
                                      onPressed: () => _like(r),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.s),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '写下对这一段的想法…',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _publish(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  FilledButton(
                    onPressed: _publish,
                    child: const Text('发表'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
