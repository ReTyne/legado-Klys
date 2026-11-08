/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 _ButtonGroupSection。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


/// 按钮组：流式排列的动作按钮。
class _ButtonGroupSection extends StatelessWidget {
  const _ButtonGroupSection({required this.items, required this.onTap});
  final List<HomepageItem> items;
  final HomepageItemTap onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map((item) => ActionChip(
                  avatar: const Icon(Icons.apps_outlined, size: 16),
                  label: Text(item.title),
                  onPressed: () => onTap(item),
                ))
            .toList(),
      ),
    );
  }
}
