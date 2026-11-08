// 项目统一的 MD3 弹窗 / 反馈组件。
// 主题已在 AppTheme 定义 dialogTheme / bottomSheetTheme（圆角 24），
// 这些 helper 不覆写 backgroundColor / shape，保证深色、AMOLED、E-ink 一致。

import 'package:flutter/material.dart';

/// 确认框（含危险变体）。返回是否确认。
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String cancelText = '取消',
  String confirmText = '确定',
  bool danger = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: cs.error, foregroundColor: cs.onError)
              : null,
          onPressed: () => Navigator.pop(d, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 不可取消忙碌对话框 + 自动关闭。替换各页逐字重复的 4 处 builder。
Future<T> runWithBusyDialog<T>(
  BuildContext context, {
  required String message,
  required Future<T> task,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(message),
          ]),
        ),
      ),
    ),
  );
  try {
    return await task;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: false).pop();
  }
}

/// 底部菜单（SafeArea + min Column + ListTile 项）。
Future<void> showAppMenuSheet(
  BuildContext context, {
  String? title,
  required List<AppMenuSheetItem> items,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ...items.map((it) => ListTile(
                leading: it.icon == null ? null : Icon(it.icon),
                title: Text(it.title),
                subtitle: it.subtitle == null ? null : Text(it.subtitle!),
                onTap: () {
                  Navigator.pop(context);
                  it.onTap();
                },
              )),
        ]),
      ),
    ),
  );
}

class AppMenuSheetItem {
  const AppMenuSheetItem({
    required this.title,
    required this.onTap,
    this.icon,
    this.subtitle,
  });

  final String title;
  final VoidCallback onTap;
  final IconData? icon;
  final String? subtitle;
}

/// 单选对话框（RadioListTile）。返回选中的值或 null。
Future<T?> showAppRadioDialog<T>(
  BuildContext context, {
  required String title,
  required List<AppRadioOption<T>> options,
  required T groupValue,
}) {
  return showDialog<T>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((o) => RadioListTile<T>(
                    value: o.value,
                    groupValue: groupValue,
                    title: Text(o.label),
                    onChanged: (v) => Navigator.pop(d, v),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

class AppRadioOption<T> {
  const AppRadioOption(this.value, this.label);
  final T value;
  final String label;
}

/// 颜色选择（预设色块）。返回选中的颜色或 null。
Future<Color?> showAppColorPicker(
  BuildContext context, {
  required List<Color> colors,
  Color? selected,
}) {
  final cs = Theme.of(context).colorScheme;
  return showDialog<Color>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('选择颜色'),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: colors
            .map((c) => GestureDetector(
                  onTap: () => Navigator.pop(d, c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: c == selected
                          ? Border.all(color: cs.primary, width: 3)
                          : Border.all(color: cs.outlineVariant, width: 1),
                    ),
                    child: c == selected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                ))
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
