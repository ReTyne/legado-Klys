// 项目统一的 MD3 公共组件集。
// 所有组件内部自行读取 Theme.of(context).colorScheme，不接收颜色参数，
// 跟随全局 AppTheme（含 AMOLED / E-ink / 字体缩放）。语义映射：
// 主文字 onSurface、次要 onSurfaceVariant、强调 primary、
// 容器 surfaceContainer*、危险 error、描边 outlineVariant。

import 'package:flutter/material.dart';

/// 分组标题（固定范式 fromLTRB(16,16,16,8) / 13 / bold / primary）。
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: cs.primary,
        ),
      ),
    );
  }
}

/// 设置 / 我的 / 底部菜单通用跳转项。
class AppMenuItem extends StatelessWidget {
  const AppMenuItem({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing = const Icon(Icons.chevron_right),
    this.dense = false,
    this.enabled = true,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  final bool dense;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: icon == null ? null : Icon(icon),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      trailing: trailing,
      dense: dense,
      enabled: enabled,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// 开关设置项（对应 settings._sw）。
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.dense = true,
    this.contentPadding,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;
  final IconData? icon;
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: dense,
      contentPadding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 16),
      secondary: icon == null ? null : Icon(icon),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 整数 ±1 步进项（对应 settings._step）。
class AppStepTile extends StatelessWidget {
  const AppStepTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 11)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: '减少',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 40,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: '增加',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ]),
    );
  }
}

/// 统一空态：大图标 64 + 标题 + 说明 + 可选动作。
/// 颜色取 onSurfaceVariant，替换各页内联的 Colors.grey* 三件套。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: cs.onSurface)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 统一错误态 + 重试按钮。
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryLabel = '重试',
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: cs.error),
            const SizedBox(height: 16),
            Text('加载失败', style: TextStyle(fontSize: 16, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

/// 整页 / 局部加载指示。
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.message, this.compact = false});

  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!),
          ],
        ],
      ),
    );
  }
}

/// 横向 FilterChip 分组页签（替换 bookshelf / source_manage 两处重复）。
class AppChipTabs<T> extends StatelessWidget {
  const AppChipTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.height = 48,
  });

  final List<T> items;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return FilterChip(
            label: Text(labelOf(item)),
            selected: item == selected,
            onSelected: (_) => onSelected(item),
          );
        },
      ),
    );
  }
}

/// 详情页小标签 / 强调按钮。
class AppTag extends StatelessWidget {
  const AppTag(this.text, {super.key, this.accent = false, this.onTap});

  final String text;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = accent ? cs.primaryContainer : cs.secondaryContainer;
    final fg = accent ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
    );
    return onTap == null
        ? child
        : GestureDetector(onTap: onTap, child: child);
  }
}

/// 详情页「行内图标 18 + 内容 + 右侧强调」行。
class AppInfoRow extends StatelessWidget {
  const AppInfoRow({
    super.key,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: child),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 设置分组（标题 + 若干 tile）。
class AppSettingsGroup extends StatelessWidget {
  const AppSettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(title),
        ...children,
      ],
    );
  }
}
