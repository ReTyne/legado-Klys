/// 由 rss_read_screen.dart 按「一类一文件」拆出的 _TextBody。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../rss_read_screen.dart';


/// 文本正文（按段渲染，朗读时高亮当前段）
class _TextBody extends StatelessWidget {
  const _TextBody({
    required this.article,
    required this.paragraphs,
    required this.fontSize,
    required this.onOriginal,
    required this.scrollController,
    this.highlightIndex = -1,
    this.highlightKey,
  });
  final RssArticle article;
  final List<String> paragraphs;
  final double fontSize;
  final VoidCallback onOriginal;
  final ScrollController scrollController;
  /// 朗读中的段落索引，-1 表示未朗读
  final int highlightIndex;
  final GlobalKey? highlightKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(article.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4)),
        const SizedBox(height: 12),
        if ((article.image ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Image.network(article.image!,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        Row(children: [
          if (article.author != null) ...[
            Icon(Icons.person_outline, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(article.author!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(width: 12),
          ],
          Icon(Icons.access_time, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(article.pubDate != null ? DateTime.fromMillisecondsSinceEpoch(article.pubDate!).toString().substring(0, 16) : '', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
        const Divider(height: 24),
        for (var i = 0; i < paragraphs.length; i++)
          Container(
            key: i == highlightIndex ? highlightKey : null,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: i == highlightIndex
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                : null,
            decoration: i == highlightIndex
                ? BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.45),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(paragraphs[i],
                style: TextStyle(fontSize: fontSize, height: 1.8)),
          ),
        const SizedBox(height: 24),
        if (article.link.isNotEmpty)
          Center(child: TextButton.icon(
            onPressed: onOriginal,
            icon: const Icon(Icons.open_in_browser), label: const Text('阅读原文'),
          )),
        const SizedBox(height: 40),
      ]),
    );
  }
}
