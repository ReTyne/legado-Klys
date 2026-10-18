import "package:flutter/material.dart";

/// 统一加载态组件
class LoadingWidget extends StatelessWidget {
  final String? message;
  final double size;
  const LoadingWidget({super.key, this.message, this.size = 36});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 3)),
      if (message != null) ...[
        const SizedBox(height: 12),
        Text(message!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    ]),
  );
}
