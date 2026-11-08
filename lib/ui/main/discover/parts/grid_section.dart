/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 _GridSection。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 网格 / 网格排行：自适应列数的网格，ranked 时左上角叠加序号。
class _GridSection extends StatelessWidget {
  const _GridSection({
    required this.items,
    required this.onTap,
    required this.ranked,
  });
  final List<HomepageItem> items;
  final HomepageItemTap onTap;
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 720
            ? 5
            : width >= 520
                ? 4
                : 3;
        const spacing = 10.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (context, i) {
              final item = items[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onTap(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _itemCover(context, item,
                                width: double.infinity,
                                height: double.infinity),
                          ),
                          if (ranked)
                            Positioned(
                              left: 4,
                              top: 4,
                              child: _RankBadge(index: i, small: true),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurface)),
                    if (item.subtitle.isNotEmpty)
                      Text(item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10, color: cs.onSurfaceVariant)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
