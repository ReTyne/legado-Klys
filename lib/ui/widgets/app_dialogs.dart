// 项目统一的 MD3 弹窗 / 反馈组件。
// 主题已在 AppTheme 定义 dialogTheme / bottomSheetTheme（圆角 24），
// 这些 helper 不覆写 backgroundColor / shape，保证深色、AMOLED、E-ink 一致。

import 'package:flutter/material.dart';

import 'package:legado_md3/constant/e_placement.dart';
import 'package:legado_md3/ui/theme/app_design.dart';
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
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.m),
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
              padding: const EdgeInsets.all(AppSpacing.l),
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

// ───────────────────────────────────────────────────────────────────────────
// AppBar 右上角 overflow 菜单
//
// 语义：各页 TitleBar 的溢出菜单（showAsAction="never"）是「锚定右上角的
// 下拉菜单」。本项目此前用 showAppMenuSheet（底部 sheet）承载，属于功能位置不一致。
// 这里提供锚定 AppBar actions 的 overflow 组件，替换这些底部 sheet：
//   - EOverflowMenuButton：放入 AppBar.actions，天然锚定右上角（PopupMenuButton
//     是 MenuAnchor 的高层封装，本项目已有十余处使用，稳定且风格一致）。
//   - 每个菜单项带稳定 Key('e_menu::<id>')，供 widget 测试用 getTopLeft(...).dy
//     做「严格顺序」断言，避免中文文案改动导致误判。
//   - checkable 项显示 trailing 勾选框（视觉降级、状态语义等价）。
//   - visibleByDefault=false 的项默认不渲染，
//     不伪造空壳。
//   - secondary：扩展功能，收在菜单末尾「更多功能」子分组，不占主界面入口，
//     以分隔线 + 分区标题区隔，保证功能仍可触达。
//
// 与 showAppMenuSheet 的分工：「长按列表项」本身就是上下文菜单，这类仍用
// showAppMenuSheet；只有 明确是 Toolbar overflow 的场景改用本组件。
// ───────────────────────────────────────────────────────────────────────────

/// 一个 overflow 菜单项。
class EOverflowItem {
  const EOverflowItem({
    required this.id,
    required this.label,
    this.onTap,
    this.icon,
    this.checkable = false,
    this.checked = false,
    this.visibleByDefault = true,
    this.sectionHeader,
  });

  /// 稳定标识。
  final String id;

  /// 显示文案。
  final String label;

  /// 点击回调（可选：若由 [EOverflowMenuButton.onSelected] 统一分发可省略）。
  final VoidCallback? onTap;

  final IconData? icon;

  /// 是否为可勾选（checkable）项。
  final bool checkable;

  /// checkable 项的当前勾选态。
  final bool checked;

  /// visible="false"：false 表示默认不渲染，不伪造空壳。
  final bool visibleByDefault;

  /// 非 null 时该项渲染为不可点击的分区标题（用于给菜单内部分组）。
  final String? sectionHeader;

  /// 稳定 Key，供顺序断言。
  String get menuKey => 'e_menu::$id';
}

/// 由 EPlacement 的 [EMenuItem] 列表构造 overflow 项，避免各页重复硬编码顺序。
/// [onTapFor] 为每项生成回调；[overrides] 可对个别项覆盖勾选态/可见性/文案。
List<EOverflowItem> eOverflowItemsFrom(
  List<EMenuItem> source, {
  required VoidCallback Function(String id) onTapFor,
  Map<String, ({bool? checked, bool? visible, String? label})> overrides =
      const {},
  Map<String, IconData> icons = const {},
}) {
  final items = <EOverflowItem>[];
  for (final e in source) {
    final ov = overrides[e.id];
    items.add(EOverflowItem(
      id: e.id,
      label: ov?.label ?? e.zh,
      onTap: onTapFor(e.id),
      icon: icons[e.id],
      checkable: e.checkable,
      checked: ov?.checked ?? e.checkedByDefault,
      visibleByDefault: ov?.visible ?? e.visibleByDefault,
    ));
  }
  return items;
}

/// 构建一个带稳定 Key、勾选态、分区标题的 PopupMenuItem 列表。
List<PopupMenuEntry<String>> _eOverflowEntries(
  BuildContext context,
  List<EOverflowItem> items, {
  String? secondaryLabel,
  List<EOverflowItem>? secondary,
}) {
  final theme = Theme.of(context);
  final entries = <PopupMenuEntry<String>>[];

  PopupMenuEntry<String> buildItem(EOverflowItem it) {
    if (it.sectionHeader != null) {
      return PopupMenuItem<String>(
        key: Key(it.menuKey),
        enabled: false,
        height: AppSpacing.xxl,
        child: Text(it.sectionHeader!,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.primary)),
      );
    }
    return PopupMenuItem<String>(
      key: Key(it.menuKey),
      value: it.id,
      child: Row(
        children: [
          if (it.icon != null) ...[
            Icon(it.icon, size: 20),
            const SizedBox(width: AppSpacing.s),
          ],
          Expanded(child: Text(it.label, overflow: TextOverflow.ellipsis)),
          if (it.checkable) ...[
            const SizedBox(width: AppSpacing.s),
            Icon(
              it.checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: it.checked
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }

  for (final it in items) {
    if (!it.visibleByDefault) continue; // visible=false 项默认不渲染
    entries.add(buildItem(it));
  }
  if (secondary != null && secondary.isNotEmpty) {
    final visibleSecondary =
        secondary.where((e) => e.visibleByDefault).toList();
    if (visibleSecondary.isNotEmpty) {
      entries.add(const PopupMenuDivider());
      if (secondaryLabel != null) {
        entries.add(PopupMenuItem<String>(
          key: const Key('e_menu::__secondary_header__'),
          enabled: false,
          height: AppSpacing.xxl,
          child: Text(secondaryLabel,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ));
      }
      for (final it in visibleSecondary) {
        entries.add(buildItem(it));
      }
    }
  }
  return entries;
}

/// 锚定 AppBar 右上角的 overflow 菜单按钮（替换原「更多」底部 sheet）。
class EOverflowMenuButton extends StatelessWidget {
  const EOverflowMenuButton({
    super.key,
    required this.items,
    this.onSelected,
    this.secondary,
    this.secondaryLabel = '更多功能',
    this.tooltip = '更多',
    this.icon = const Icon(Icons.more_vert_outlined),
  });

  /// 主界面项。
  final List<EOverflowItem> items;

  /// 可选统一点击分发（收到 id）；与各项自带 [EOverflowItem.onTap] 二者至少其一。
  final void Function(String id)? onSelected;

  /// 扩展功能次级项，收在末尾子分组，不占主界面入口。
  final List<EOverflowItem>? secondary;

  /// 次级分组标题。
  final String secondaryLabel;

  final String tooltip;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final all = <EOverflowItem>[...items, ...?secondary];
    return PopupMenuButton<String>(
      tooltip: tooltip,
      icon: icon,
      onSelected: (id) {
        onSelected?.call(id);
        for (final it in all) {
          if (it.id == id) {
            it.onTap?.call();
            break;
          }
        }
      },
      itemBuilder: (ctx) => _eOverflowEntries(
        ctx,
        items,
        secondaryLabel: secondary == null ? null : secondaryLabel,
        secondary: secondary,
      ),
    );
  }
}

/// 命令式 overflow 菜单（供非 AppBar 场景自定义锚点），基于 showMenu。
/// 返回被点击项的 id，未选中返回 null；点击后不自动触发各项 onTap，由调用方按
/// 返回的 id 分发（避免与 EOverflowMenuButton 的双重分发语义混淆）。
Future<String?> showAppOverflowMenu(
  BuildContext context, {
  required RelativeRect position,
  required List<EOverflowItem> items,
  List<EOverflowItem>? secondary,
  String secondaryLabel = '更多功能',
}) {
  return showMenu<String>(
    context: context,
    position: position,
    items: _eOverflowEntries(
      context,
      items,
      secondaryLabel: secondary == null ? null : secondaryLabel,
      secondary: secondary,
    ),
  );
}
