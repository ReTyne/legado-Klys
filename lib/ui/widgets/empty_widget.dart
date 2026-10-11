import "package:flutter/material.dart";

/// 统一空态组件
class EmptyWidget extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionText;
  const EmptyWidget({super.key, this.text = '暂无数据', this.icon = Icons.inbox_outlined, this.onAction, this.actionText});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 64, color: Colors.grey.shade400),
      const SizedBox(height: 12),
      Text(text, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
      if (onAction != null && actionText != null) ...[
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onAction, child: Text(actionText!)),
      ],
    ]),
  );
}
