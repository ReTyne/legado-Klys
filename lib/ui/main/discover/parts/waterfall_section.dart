/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 _WaterfallSection。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 瀑布流：两列不等高卡片，按序号交错高度形成瀑布效果。
class _WaterfallSection extends StatelessWidget {
  const _WaterfallSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final left = <HomepageItem>[];
    final right = <HomepageItem>[];
    for (var i = 0; i < items.length; i++) {
      (i % 2 == 0 ? left : right).add(items[i]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _waterfallColumn(context, left, 0, cs),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _waterfallColumn(context, right, 1, cs),
          ),
        ],
      ),
    );
  }

  Widget _waterfallColumn(BuildContext context, List<HomepageItem> list,
      int columnSeed, ColorScheme cs) {
    return Column(
      children: list.asMap().entries.map((e) {
        final item = e.value;
        final tall = (e.key + columnSeed) % 2 == 0;
        final h = tall ? 168.0 : 128.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: double.infinity,
                    height: h,
                    child: _itemCover(context, item,
                        width: double.infinity, height: h, radius: 0),
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
                      style:
                          TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
