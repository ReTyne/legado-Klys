/// 由 source_login_screen.dart 按「一类一文件」拆出的 _LoginButton。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../source_login_screen.dart';


class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isPrimary = label.contains('登录') && !label.contains('退出') && !label.contains('注册');
    final child = Text(label);
    return isPrimary
        ? FilledButton(onPressed: busy ? null : onPressed, child: child)
        : OutlinedButton(onPressed: busy ? null : onPressed, child: child);
  }
}
