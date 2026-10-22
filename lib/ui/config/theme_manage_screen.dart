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

/// 预设主题色（对齐 legado 取色习惯：Material 中低饱和主色 + 配套强调色/背景）
class _Preset {
  final String name;
  final int primary;
  final int accent;
  const _Preset(this.name, this.primary, this.accent);
}

const List<_Preset> _presets = [
  _Preset('默认紫', 0xFF6750A4, 0xFF625B71),
  _Preset('蓝色', 0xFF1976D2, 0xFF0288D1),
  _Preset('青色', 0xFF00838F, 0xFF0097A7),
  _Preset('绿色', 0xFF2E7D32, 0xFF00796B),
  _Preset('酸橙', 0xFF558B2F, 0xFF689F38),
  _Preset('黄色', 0xFFF9A825, 0xFFFBC02D),
  _Preset('橙色', 0xFFE64A19, 0xFFF57C00),
  _Preset('棕色', 0xFF795548, 0xFF8D6E63),
  _Preset('红色', 0xFFC62828, 0xFFD32F2F),
  _Preset('粉色', 0xFFC2185B, 0xFFD81B60),
  _Preset('紫色', 0xFF6A1B9A, 0xFF8E24AA),
  _Preset('靛蓝', 0xFF283593, 0xFF3949AB),
  _Preset('蓝灰', 0xFF37474F, 0xFF455A64),
  _Preset('深灰', 0xFF212121, 0xFF424242),
];

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

  // 补齐项：模式 / AMOLED / 前景不透明度
  ThemeMode _themeMode = ThemeMode.system;
  bool _amoled = false;
  double _foregroundOpacity = 1.0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<CustomTheme> get _all => [..._builtin, ..._custom];

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('custom_themes') ?? [];
    final savedId = prefs.getString('theme_selected_id') ?? '';
    final seed = prefs.getInt('seed_color') ?? 0xFF6750A4;
    final modeIdx = prefs.getInt('theme_mode') ?? 0;
    if (!mounted) return;
    setState(() {
      _custom
        ..clear()
        ..addAll(raw.map((s) => CustomTheme.fromJson(jsonDecode(s) as Map<String, dynamic>)));
      _themeMode = ThemeMode.values[modeIdx.clamp(0, ThemeMode.values.length - 1)];
      _amoled = prefs.getBool('theme_amoled') ?? false;
      _foregroundOpacity = prefs.getDouble('theme_foregroundOpacity') ?? 1.0;
      _selectedThemeId = savedId.isNotEmpty && _all.any((t) => t.id == savedId)
          ? savedId
          : _matchSeed(seed);
      _loaded = true;
    });
  }

  /// 持久化选中项；无显式记录时按当前主色匹配内置主题
  String _matchSeed(int seed) {
    final match = _all.where((t) => t.primaryColor == seed);
    return match.isNotEmpty ? match.first.id : 'default';
  }

  Future<void> _persistCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_themes', _custom.map((t) => jsonEncode(t.toJson())).toList());
  }

  Future<void> _setSelected(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_selected_id', id);
  }

  Future<void> _apply(CustomTheme theme) async {
    setState(() => _selectedThemeId = theme.id);
    await _setSelected(theme.id);
    if (!mounted) return;
    final appTheme = context.read<AppTheme>();
    await appTheme.setSeedColor(Color(theme.primaryColor));
    final target = theme.isDark ? ThemeMode.dark : ThemeMode.light;
    _themeMode = target;
    await appTheme.setThemeMode(target);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已应用「${theme.name}」')));
  }

  /// 直接应用预设色（不改主题对象，只换 seed）
  Future<void> _applyPreset(_Preset preset) async {
    setState(() {
      _selectedThemeId = 'preset_${preset.primary}';
      if (preset.primary == 0xFF212121 || preset.primary == 0xFF37474F) {
        _themeMode = ThemeMode.dark;
      }
    });
    await _setSelected(_selectedThemeId);
    if (!mounted) return;
    final appTheme = context.read<AppTheme>();
    await appTheme.setSeedColor(Color(preset.primary));
    await appTheme.setThemeMode(_themeMode);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已应用主色「${preset.name}」')));
  }

  Future<void> _setMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final appTheme = context.read<AppTheme>();
    await appTheme.setThemeMode(mode);
  }

  Future<void> _setAmoled(bool v) async {
    setState(() => _amoled = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_amoled', v);
  }

  Future<void> _setForegroundOpacity(double v) async {
    setState(() => _foregroundOpacity = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('theme_foregroundOpacity', v);
  }

  /* ---------------- 自定义色：Flutter 自带 HSV 取色器 ---------------- */

  Future<void> _showCustomColorPicker() async {
    final color = await showDialog<Color>(
      context: context,
      builder: (ctx) => const _HsvColorPickerDialog(),
    );
    if (color == null || !mounted) return;
    _addDialogColor(color);
  }

  void _addDialogColor(Color color) {
    final t = CustomTheme(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: '自定义 ${_toHex(color.value)}',
      primaryColor: color.value,
      secondaryColor: color.value,
      backgroundColor: Color.alphaBlend(color.withOpacity(0.08), Colors.white).value,
      surfaceColor: Colors.white.value,
    );
    setState(() => _custom.add(t));
    _persistCustom().then((_) => _apply(t));
  }

  static String _toHex(int v) => '#${(v & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

  void _showAddTheme() {
    final nameController = TextEditingController();
    int primary = 0xFF6750A4, bg = 0xFFFFFBFE;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setD) => AlertDialog(
      title: const Text('新建主题'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameController, decoration: const InputDecoration(labelText: '主题名称', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.colorize),
          label: Text('主色 ${_toHex(primary)}'),
          onPressed: () async {
            final c = await showDialog<Color>(context: context, builder: (ctx) => const _HsvColorPickerDialog(initial: Color(0xFF6750A4)));
            if (c != null) {
              setD(() => primary = c.value);
            }
          },
        ),
        const SizedBox(height: 12),
        _colorPresetsRow(primary, (c) => setD(() => primary = c)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.format_color_fill),
          label: Text('背景 ${_toHex(bg)}'),
          onPressed: () async {
            final c = await showDialog<Color>(context: context, builder: (ctx) => const _HsvColorPickerDialog(initial: Color(0xFFFFFBFE)));
            if (c != null) {
              setD(() => bg = c.value);
            }
          },
        ),
        const SizedBox(height: 12),
        _colorPresetsRow(bg, (c) => setD(() => bg = c)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () {
          if (nameController.text.isEmpty) return;
          final t = CustomTheme(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: nameController.text, primaryColor: primary,
            secondaryColor: primary, backgroundColor: bg, surfaceColor: bg,
          );
          setState(() => _custom.add(t));
          _persistCustom().then((_) => _apply(t));
          if (mounted) Navigator.pop(context);
        }, child: const Text('创建并应用')),
      ],
    )));
  }

  void _showThemeEdit(CustomTheme theme) {
    // 内置主题不可删除，只可重新应用；自定义可编辑/删除
    final isBuiltin = _builtin.any((t) => t.id == theme.id);
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(builder: (context, setSheet) => Padding(
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
              if (!mounted) return;
              if (sheetCtx.mounted) {
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(sheetCtx).showSnackBar(const SnackBar(content: Text('已删除主题')));
              }
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

  static Widget _colorPresetsRow(int color, ValueChanged<int> onChanged) {
    return Wrap(spacing: 8, runSpacing: 8, children: _presets.map((c) => GestureDetector(
      onTap: () => onChanged(c.primary),
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: Color(c.primary), shape: BoxShape.circle,
          border: Border.all(
            color: c.primary == color ? Colors.black : Colors.grey,
            width: c.primary == color ? 3 : 1,
          ),
        ),
      ),
    )).toList());
  }

  Widget _colorPickerRow(String label, int color, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 60, child: Text(label)),
          Container(width: 28, height: 28, decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle, border: Border.all(color: Colors.grey))),
          const Spacer(),
          Text(_toHex(color), style: const TextStyle(fontSize: 12)),
          IconButton(
            tooltip: 'HSV 取色',
            icon: const Icon(Icons.colorize, size: 18),
            onPressed: () async {
              final c = await showDialog<Color>(context: context, builder: (ctx) => _HsvColorPickerDialog(initial: Color(color)));
              if (c != null) onChanged(c.value);
            },
          ),
        ]),
        const SizedBox(height: 8),
        _colorPresetsRow(color, onChanged),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('主题管理')),
      body: ListView(children: [
        _buildAppearanceSection(cs),
        _buildPresetSection(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('我的主题', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.primary)),
        ),
        ..._all.map((theme) {
          final selected = _selectedThemeId == theme.id;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Card(
              color: selected ? Color(theme.primaryColor).withOpacity(0.1) : Theme.of(context).cardTheme.color,
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Color(theme.primaryColor), child: Icon(theme.isDark ? Icons.dark_mode : Icons.light_mode, color: Colors.white, size: 20)),
                title: Text(theme.name),
                subtitle: Text('主色: ${_toHex(theme.primaryColor)} · 背景: ${_toHex(theme.backgroundColor)}'),
                trailing: selected ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.radio_button_unchecked),
                onTap: () => _apply(theme),
                onLongPress: () => _showThemeEdit(theme),
              ),
            ),
          );
        }),
        const SizedBox(height: 80),
      ]),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'presetFab',
            tooltip: 'HSV 自定义主色',
            onPressed: _showCustomColorPicker,
            child: const Icon(Icons.colorize),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'addFab',
            tooltip: '新建主题',
            onPressed: _showAddTheme,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(ColorScheme cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('外观模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.primary)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('跟随系统')),
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('浅色')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('深色')),
          ],
          selected: {_themeMode},
          onSelectionChanged: (set) => _setMode(set.first),
        ),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: const Text('AMOLED 纯黑前景', style: TextStyle(fontSize: 14)),
        subtitle: const Text('深色时使用纯黑背景，省电（theme_amoled）', style: TextStyle(fontSize: 11)),
        value: _amoled,
        onChanged: _setAmoled,
      ),
      ListTile(
        dense: true,
        title: Text('前景不透明度: ${(_foregroundOpacity * 100).round()}%'),
        subtitle: Slider(
          value: _foregroundOpacity,
          min: 0.3, max: 1.0, divisions: 14,
          label: '${(_foregroundOpacity * 100).round()}%',
          onChanged: _setForegroundOpacity,
        ),
      ),
      if (_loaded && _selectedThemeId.startsWith('preset_'))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('当前：预设主色方案（未保存到「我的主题」）', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
    ]);
  }

  Widget _buildPresetSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text('预设主题色（${_presets.length}）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _presets.map((p) {
            final selected = _selectedThemeId == 'preset_${p.primary}';
            return GestureDetector(
              onTap: () => _applyPreset(p),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Color(p.primary),
                    shape: BoxShape.circle,
                    border: Border.all(width: selected ? 3 : 1, color: selected ? Theme.of(context).colorScheme.outline : Colors.transparent),
                  ),
                  child: selected ? const Icon(Icons.check, color: Colors.white, size: 22) : null,
                ),
                const SizedBox(height: 4),
                SizedBox(width: 52, child: Text(p.name, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }
}

/// Flutter 自带 HSV 取色对话框：Hue/Saturation/Value 三条滑块 + 明暗预览，不依赖三方色盘包
class _HsvColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _HsvColorPickerDialog({this.initial = const Color(0xFF6750A4)});

  @override
  State<_HsvColorPickerDialog> createState() => _HsvColorPickerDialogState();
}

class _HsvColorPickerDialogState extends State<_HsvColorPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity, height: 56,
          decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text('#${(_hsv.toColor().value & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(height: 8),
        _hsvSlider('色相 H', _hsv.hue, 0.0, 360.0, Theme.of(context).sliderTheme.activeTrackColor ?? cs.primary,
          (v) => setState(() => _hsv = _hsv.withHue(v))),
        _hsvSlider('饱和度 S', _hsv.saturation, 0.0, 1.0, Colors.grey,
          (v) => setState(() => _hsv = _hsv.withSaturation(v))),
        _hsvSlider('明度 V', _hsv.value, 0.0, 1.0, Colors.grey,
          (v) => setState(() => _hsv = _hsv.withValue(v))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('确定')),
      ],
    );
  }

  Widget _hsvSlider(String label, double value, double min, double max, Color color, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 11))),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(activeTrackColor: color, thumbColor: color, inactiveTrackColor: Colors.grey.shade400),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ),
    ]);
  }
}
