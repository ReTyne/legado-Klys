import "package:flutter/material.dart";

/// 页面基类，提供统一标题栏与加载/错误/空态渲染
abstract class BaseScreen extends StatelessWidget {
  const BaseScreen({super.key});

  String? get title => null;
  Widget buildBody(BuildContext context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title == null ? null : AppBar(title: Text(title!)),
      body: buildBody(context),
    );
  }

  Widget loading() => const Center(child: CircularProgressIndicator());

  Widget errorView(String msg, {VoidCallback? onRetry}) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: Colors.grey),
      const SizedBox(height: 8),
      Text(msg, textAlign: TextAlign.center),
      if (onRetry != null) ...[
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ]),
  );

  Widget emptyView([String text = '暂无数据']) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
      const SizedBox(height: 8),
      Text(text, style: const TextStyle(color: Colors.grey)),
    ]),
  );
}
