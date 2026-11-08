// 项目统一的 MD3 公共组件集。
// 所有组件内部自行读取 Theme.of(context).colorScheme，不接收颜色参数，
// 跟随全局 AppTheme（含 AMOLED / E-ink / 字体缩放）。语义映射：
// 主文字 onSurface、次要 onSurfaceVariant、强调 primary、
// 容器 surfaceContainer*、危险 error、描边 outlineVariant。

import 'package:flutter/material.dart';
import 'package:legado_md3/ui/theme/app_design.dart';

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
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 无障碍：空态图标此前无任何语义，读屏用户无法感知状态；
            // 文本与操作按钮保留原生语义，避免被 ExcludeSemantics 误排除。
            Semantics(
              label: '空状态：$title',
              child: Icon(icon, size: 64, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: cs.onSurface)),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
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
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              label: '错误状态：加载失败',
              child: Icon(Icons.error_outline, size: 64, color: cs.error),
            ),
            const SizedBox(height: AppSpacing.l),
            Text('加载失败', style: TextStyle(fontSize: 16, color: cs.onSurface)),
            const SizedBox(height: AppSpacing.s),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.l),
            Semantics(
              button: true,
              label: retryLabel,
              child: FilledButton(
                  onPressed: onRetry, child: Text(retryLabel)),
            ),
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
    // 无障碍：加载进度对读屏用户此前是「静默」的，补 label 播报。
    // 无 message 且非 compact 时保持与裸 Center(child: CircularProgressIndicator())
    // 完全等价的布局，便于各页面零差异地收敛到统一组件。
    final Widget progress = Semantics(
      label: message ?? '加载中',
      child: const CircularProgressIndicator(),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Center(child: progress),
      );
    }
    if (message == null) {
      return Center(child: progress);
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          progress,
          const SizedBox(height: AppSpacing.l),
          Text(message!),
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

/// 异步四态统一容器。
///
/// 把各页面重复的
/// `if (_loading) Center(CircularProgressIndicator) else if (_error != null)
///  ... else if (list.isEmpty) ... else ListView.builder(...)`
/// 样板收敛到一处。空态 / 错误态 / 加载态都复用本项目无障碍增强过的
/// 公共组件，保证全应用一致的主题与读屏体验。
class AppAsyncState extends StatelessWidget {
  const AppAsyncState({
    super.key,
    required this.loading,
    required this.isEmpty,
    required this.child,
    this.error,
    this.onRetry,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyTitle = '暂无内容',
    this.emptyMessage,
    this.emptyAction,
    this.loadingMessage,
  });

  final bool loading;
  final bool isEmpty;
  final String? error;
  final VoidCallback? onRetry;
  final Widget child;

  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;
  final String? loadingMessage;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return AppLoadingIndicator(message: loadingMessage);
    }
    if (error != null && onRetry != null) {
      return AppErrorState(message: error!, onRetry: onRetry!);
    }
    if (isEmpty) {
      return AppEmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        action: emptyAction,
      );
    }
    return child;
  }
}

/// 响应式内容容器：宽屏时把内容居中并限制最大宽度，避免大屏上
/// 文本行过长、列表被拉伸；窄屏时原样铺满。用于表单、列表、设置页等内容型页面。
class AppAdaptiveBody extends StatelessWidget {
  const AppAdaptiveBody({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!AppBreakpoints.isWide(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
