/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 _CardSection。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 卡片列表：每个 item 一张横向卡片（封面 + 标题/副标题/角标）。
class _CardSection extends StatelessWidget {
  const _CardSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items.map((item) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: _itemCover(context, item, width: 48, height: 66),
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.subtitle.isNotEmpty)
                    Text(item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  if (item.badge != null && item.badge!.isNotEmpty)
                    Text(item.badge!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cs.primary)),
                ],
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
