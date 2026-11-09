/// 由 homepage_module_widgets.dart 按「一类一文件」拆出的 _RankBadge。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../homepage_module_widgets.dart';


class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.index, this.small = false});
  final int index;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = index < 3;
    return Container(
      width: small ? 20 : 24,
      height: small ? 20 : 24,
      decoration: BoxDecoration(
        color: top ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: AppRadius.sAll,
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontSize: small ? 11 : 13,
          fontWeight: FontWeight.bold,
          color: top ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
