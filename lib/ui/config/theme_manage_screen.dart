import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/constant/app_theme.dart';

class CustomTheme {
  final String id;
  final String name;
  final int primaryColor;
  final int secondaryColor;
  final int backgroundColor;
  final int surfaceColor;
  final bool isDark;
  CustomTheme({required this.id, required this.name, required this.primaryColor, required this.secondaryColor, required this.backgroundColor, required this.surfaceColor, this.isDark = false});
  factory CustomTheme.fromJson(Map<String, dynamic> json) => CustomTheme(
    id: json['id'] ?? '', name: json['name'] ?? '',
    primaryColor: json['primaryColor'] ?? 0xFF6750A4,
    secondaryColor: json['secondaryColor'] ?? 0xFF625B71,
    backgroundColor: json['backgroundColor'] ?? 0xFFFFFBFE,
    surfaceColor: json['surfaceColor'] ?? 0xFFFFFBFE,
    isDark: json['isDark'] ?? false,
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'primaryColor': primaryColor,
    'secondaryColor': secondaryColor, 'backgroundColor': backgroundColor,
    'surfaceColor': surfaceColor, 'isDark': isDark,
  };
}

class ThemeManageScreen extends StatefulWidget {
  const ThemeManageScreen({super.key});
  @override
  State<ThemeManageScreen> createState() => _ThemeManageScreenState();
}

class _ThemeManageScreenState extends State<ThemeManageScreen> {
  static final _builtin = [
    CustomTheme(id: 'default', name: '默认主题', primaryColor: 0xFF6750A4, secondaryColor: 0xFF625B71, backgroundColor: 0xFFFFFBFE, surfaceColor: 0xFFFFFBFE),
    CustomTheme(id: 'blue', name: '蓝色主题', primaryColor: 0xFF1976D2, secondaryColor: 0xFF0288D1, backgroundColor: 0xFFF5F9FF, surfaceColor: 0xFFFFFFFF),
    CustomTheme(id: 'green', name: '绿色主题', primaryColor: 0xFF2E7D32, secondaryColor: 0xFF00796B, backgroundColor: 0xFFF1F8E9, surfaceColor: 0xFFFFFFFF),
    CustomTheme(id: 'orange', name: '橙色主题', primaryColor: 0xFFE64A19, secondaryColor: 0xFFF57C00, backgroundColor: 0xFFFFF3E0, surfaceColor: 0xFFFFFFFF),
    CustomTheme(id: 'dark', name: '深色主题', primaryColor: 0xFFBB86FC, secondaryColor: 0xFF03DAC6, backgroundColor: 0xFF121212, surfaceColor: 0xFF1E1E1E, isDark: true),
  ];
  final List<CustomTheme> _custom = [];
  String _selectedThemeId = 'default';

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<CustomTheme> get _all => [..._builtin, ..._custom];

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('custom_themes') ?? [];
    final seed = context.read<AppTheme>().seedColor.value;
    setState(() {
      _custom
        ..clear()
        ..addAll(raw.map((s) => CustomTheme.fromJson(jsonDecode(s))));
      // 选中项与当前主色匹配
      final match = _all.where((t) => t.primaryColor == seed);
      _selectedThemeId = match.isNotEmpty ? match.first.id : 'default';
    });
  }

  Future<void> _persistCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_themes', _custom.map((t) => jsonEncode(t.toJson())).toList());
  }

  Future<void> _apply(CustomTheme theme) async {
    setState(() => _selectedThemeId = theme.id);
    final appTheme = context.read<AppTheme>();
    await appTheme.setSeedColor(Color(theme.primaryColor));
    if (theme.isDark) {
      await appTheme.setThemeMode(ThemeMode.dark);
    } else if (appTheme.themeMode == ThemeMode.dark) {
      await appTheme.setThemeMode(ThemeMode.light);
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已应用「${theme.name}」')));
  }

  void _showAddTheme() {
    final nameController = TextEditingController();
    int primary = 0xFF6750A4, bg = 0xFFFFFBFE;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setD) => AlertDialog(
      title: const Text('新建主题'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameController, decoration: const InputDecoration(labelText: '主题名称', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        _colorPickerRow('主色调', primary, (c) => setD(() => primary = c)),
        _colorPickerRow('背景色', bg, (c) => setD(() => bg = c)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          if (nameController.text.isEmpty) return;
          final t = CustomTheme(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: nameController.text, primaryColor: primary,
            secondaryColor: primary, backgroundColor: bg, surfaceColor: bg,
          );
          setState(() => _custom.add(t));
          await _persistCustom();
          if (mounted) { Navigator.pop(context); _apply(t); }
        }, child: const Text('创建并应用')),
      ],
    )));
  }

  void _showThemeEdit(CustomTheme theme, int index) {
    // 内置主题不可删除，只可重新应用；自定义可编辑/删除
    final isBuiltin = _builtin.any((t) => t.id == theme.id);
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setSheet) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('主题: ${theme.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _colorPickerRow('主色调', theme.primaryColor, (c) {
            final nt = CustomTheme(id: theme.id, name: theme.name, primaryColor: c, secondaryColor: theme.secondaryColor, backgroundColor: theme.backgroundColor, surfaceColor: theme.surfaceColor, isDark: theme.isDark);
            setSheet(() => _updateTheme(theme.id, nt));
          }),
          _colorPickerRow('背景色', theme.backgroundColor, (c) {
            final nt = CustomTheme(id: theme.id, name: theme.name, primaryColor: theme.primaryColor, secondaryColor: theme.secondaryColor, backgroundColor: c, surfaceColor: c, isDark: theme.isDark);
            setSheet(() => _updateTheme(theme.id, nt));
          }),
          const SizedBox(height: 16),
          Row(children: [
            if (!isBuiltin) TextButton.icon(onPressed: () async {
              setState(() => _custom.removeWhere((t) => t.id == theme.id));
              await _persistCustom();
              if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除主题'))); }
            }, icon: const Icon(Icons.delete_outline, color: Colors.red), label: const Text('删除', style: TextStyle(color: Colors.red))),
            const Spacer(),
            FilledButton(onPressed: () { final cur = _all.firstWhere((t) => t.id == theme.id); Navigator.pop(context); _apply(cur); }, child: const Text('应用')),
          ]),
        ]),
      )),
    );
  }

  void _updateTheme(String id, CustomTheme nt) {
    final i = _custom.indexWhere((t) => t.id == id);
    if (i >= 0) { _custom[i] = nt; _persistCustom(); }
  }

  Widget _colorPickerRow(String label, int color, ValueChanged<int> onChanged) {
    const colors = [0xFF6750A4, 0xFF1976D2, 0xFF2E7D32, 0xFFE64A19, 0xFFC62828, 0xFF00838F, 0xFF6A1B9A, 0xFF37474F, 0xFF000000, 0xFFFFFFFF];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        SizedBox(width: 60, child: Text(label)),
        Expanded(child: Wrap(spacing: 8, children: colors.map((c) => GestureDetector(
          onTap: () => onChanged(c),
          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: c == color ? Colors.black : Colors.grey, width: c == color ? 3 : 1))),
        )).toList())),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主题管理')),
      body: ListView.builder(
        itemCount: _all.length,
        itemBuilder: (context, index) {
          final theme = _all[index];
          final selected = _selectedThemeId == theme.id;
          return Card(
            color: selected ? Color(theme.primaryColor).withOpacity(0.1) : null,
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Color(theme.primaryColor), child: Icon(theme.isDark ? Icons.dark_mode : Icons.light_mode, color: Colors.white, size: 20)),
              title: Text(theme.name),
              subtitle: Text('主色: #${theme.primaryColor.toRadixString(16).toUpperCase().padLeft(8, '0')}'),
              trailing: selected ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.radio_button_unchecked),
              onTap: () => _apply(theme),
              onLongPress: () => _showThemeEdit(theme, index),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddTheme, child: const Icon(Icons.add)),
    );
  }
}
