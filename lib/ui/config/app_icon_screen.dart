import 'package:flutter/material.dart';

import 'package:legado_md3/help/device/native_bridge.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

/// 动态桌面图标。
///
/// 别名来自原生 `LauncherIconHelper.aliasNames()`（Launcher1..7），
/// 通过 [NativeBridge.setLauncherIcon] 真实切换 LAUNCHER 入口组件。
/// 非 Android 平台通道会安全返回 false，页面给出明确提示而非假成功。
class AppIconScreen extends StatefulWidget {
  const AppIconScreen({super.key});

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  List<String> _aliases = <String>['default'];
  String _current = 'default';
  bool _loading = true;
  bool _switching = false;

  /// 8 个入口的展示名与线框图标（default + Launcher1..7）。
  static const Map<String, String> _labels = <String, String>{
    'default': '默认（松烟墨蓝）',
    'Launcher1': '靛青',
    'Launcher2': '黛绿',
    'Launcher3': '绛红',
    'Launcher4': '琥珀',
    'Launcher5': '紫藤',
    'Launcher6': '青灰',
    'Launcher7': '墨黑',
  };
  static const List<IconData> _icons = <IconData>[
    Icons.menu_book_outlined,
    Icons.auto_stories_outlined,
    Icons.local_library_outlined,
    Icons.favorite_outlined,
    Icons.star_outline,
    Icons.explore_outlined,
    Icons.book_outlined,
    Icons.nights_stay_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final aliases = await NativeBridge.instance.getLauncherAliases();
    final current = await NativeBridge.instance.getLauncherIcon();
    if (!mounted) return;
    setState(() {
      _aliases = <String>['default', ...aliases.where((a) => a != 'default')];
      _current = current;
      _loading = false;
    });
  }

  Future<void> _select(String name) async {
    if (_switching || name == _current) return;
    setState(() => _switching = true);
    final ok = await NativeBridge.instance.setLauncherIcon(name);
    if (!mounted) return;
    setState(() {
      _switching = false;
      if (ok) _current = name;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '已切换桌面图标为「${_labels[name] ?? name}」，桌面可能需要几秒刷新'
          : '当前平台不支持动态桌面图标（需 Android 原生通道）'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面图标'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: '刷新别名与当前图标',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.l),
              children: [
                const AppSectionHeader('选择一个应用图标'),
                Text(
                  '切换后系统会启用对应的 Launcher 别名组件，桌面图标随之改变；'
                  '当前：${_labels[_current] ?? _current}。',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.l),
                for (var i = 0; i < _aliases.length; i++)
                  _buildAliasTile(_aliases[i], i),
                const SizedBox(height: AppSpacing.m),
                Text(
                  '通过 NativeBridge.instance.setLauncherIcon / getLauncherAliases '
                  '/ getLauncherIcon 与原生通道 legado/launcher_icon 交互。',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
    );
  }

  Widget _buildAliasTile(String name, int index) {
    final cs = Theme.of(context).colorScheme;
    final selected = name == _current;
    final icon = _icons[index % _icons.length];
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      color: selected ? cs.primaryContainer : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: selected ? cs.onPrimaryContainer : cs.secondaryContainer,
          child: Icon(icon,
              size: 20,
              color: selected ? cs.primaryContainer : cs.onSecondaryContainer),
        ),
        title: Text(_labels[name] ?? name),
        subtitle: Text(name, style: const TextStyle(fontSize: 11)),
        trailing: selected
            ? Icon(Icons.check_circle, color: cs.primary)
            : (_switching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radio_button_unchecked)),
        onTap: () => _select(name),
      ),
    );
  }
}
