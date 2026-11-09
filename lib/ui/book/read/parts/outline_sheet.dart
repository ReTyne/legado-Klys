/// 由 pdf_reader_screen.dart 按「一类一文件」拆出的 _OutlineSheet。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../pdf_reader_screen.dart';



/// 目录面板：展示已落库大纲，点击返回跳转动作，长按返回删除动作。
class _OutlineSheet extends StatelessWidget {
  const _OutlineSheet({required this.outlines, required this.totalPages});

  final List<PdfOutline> outlines;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.s, AppSpacing.s),
              child: Row(
                children: [
                  Text('目录 / 大纲',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (totalPages > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.s),
                      child: Text('共 $totalPages 页',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: '解析 PDF 内置大纲',
                    icon: const Icon(Icons.auto_stories_outlined),
                    onPressed: () => Navigator.pop(context, 'parse'),
                  ),
                  IconButton(
                    tooltip: '添加目录项',
                    icon: const Icon(Icons.add),
                    onPressed: () => Navigator.pop(context, 'add'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: outlines.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.list_alt_outlined,
                      title: '暂无目录',
                      message: '可解析 PDF 内置大纲，或手动添加目录项后点击跳转',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: outlines.length,
                      itemBuilder: (ctx, i) {
                        final o = outlines[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.only(
                              left: 16.0 + o.level * 16, right: AppSpacing.l),
                          leading: Icon(Icons.bookmark_outline,
                              size: 18, color: cs.primary),
                          title: Text(o.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text('${o.page + 1}',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                          onTap: () => Navigator.pop(ctx, 'go:${o.page}'),
                          onLongPress: () => Navigator.pop(ctx, 'del:$i'),
                        );
                      },
                    ),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
        ),
      ),
    );
  }
}
