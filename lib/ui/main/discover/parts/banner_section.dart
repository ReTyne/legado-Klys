/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 _BannerSection。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 横幅：横向可滚动的大图卡片（封面 + 标题/副标题叠加）。
class _BannerSection extends StatelessWidget {
  const _BannerSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.m),
        itemBuilder: (context, i) {
          final item = items[i];
          return SizedBox(
            width: 260,
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => onTap(item),
                child: Row(
                  children: [
                    _itemCover(context, item, width: 100, height: 152, radius: 0),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.m),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface)),
                            if (item.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(item.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                            ],
                            if (item.badge != null && item.badge!.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.s),
                              AppTag(item.badge!, accent: true),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
