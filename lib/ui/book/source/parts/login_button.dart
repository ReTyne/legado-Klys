/// 由 source_login_screen.dart 按「一类一文件」拆出的 _LoginButton。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../source_login_screen.dart';


/// 书源 loginUi 按钮：对齐 legado-E `item_fillet_text.xml` 的统一圆角
/// 文字块。原版所有按钮同一背景 / 文字色、按 flexBasisPercent 规则排布，
/// 并不按按钮名做「主操作 / 危险 / 次级」三色分级——多套配色正是
/// 「顺序虽对却像随便排、感官怪」的来源。这里直接复用共享 FilletButton。
class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilletButton(
        label: label,
        onPressed: onPressed,
        enabled: !busy,
      );
}
