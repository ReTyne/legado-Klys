/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 _RankingSection。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 排行榜：带序号徽章的列表，前三名强调色。
class _RankingSection extends StatelessWidget {
  const _RankingSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items.asMap().entries.map((e) {
          final item = e.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RankBadge(index: e.key),
                  const SizedBox(width: 8),
                  _itemCover(context, item, width: 40, height: 56),
                ],
              ),
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                item.subtitle.isNotEmpty ? item.subtitle : (item.badge ?? ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              trailing: Icon(Icons.chevron_right,
                  size: 18, color: cs.onSurfaceVariant),
              onTap: () => onTap(item),
            ),
          );
        }).toList(),
      ),
    );
  }
}
