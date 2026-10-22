import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme extends ChangeNotifier {
  static const String _keyThemeMode = 'theme_mode';
  static const String _keySeedColor = 'seed_color';
  static const String _keyDynamicColor = 'dynamic_color';
  static const String _keyFontFamily = 'font_family';
  // AMOLED 纯黑背景（深色模式下把各类 surface 压到纯黑省电）
  static const String _keyAmoled = 'theme_amoled';
  // 前景不透明度：AMOLED 下容器背景的灰度（0=纯黑，1=标准深灰）
  static const String _keyForegroundOpacity = 'theme_foregroundOpacity';

  // 全局字体缩放（fontScale）
  static const String _keyFontScale = 'fontScale';
  // 自定义字体文件路径（read_font_path）
  static const String _keyFontPath = 'read_font_path';
  static const Set<String> _loadedFonts = <String>{};

  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xFF6750A4);
  bool _dynamicColor = true;
  String _fontFamily = '';
  double _fontScale = 1.0;
  bool _amoled = false;
  double _foregroundOpacity = 0.0;
  // 实验室：墨水屏(E-ink)优化——去除页面切换动画、提高对比度
  bool _eink = false;
  bool get eink => _eink;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get dynamicColor => _dynamicColor;
  String get fontFamily => _fontFamily;
  bool get amoled => _amoled;
  double get foregroundOpacity => _foregroundOpacity;
  double get fontScale => _fontScale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[prefs.getInt(_keyThemeMode) ?? 0];
    _seedColor = Color(prefs.getInt(_keySeedColor) ?? 0xFF6750A4);
    _dynamicColor = prefs.getBool(_keyDynamicColor) ?? true;
    _fontScale = (prefs.getDouble(_keyFontScale) ?? 1.0).clamp(0.5, 3.0);
    final fontPath = prefs.getString(_keyFontPath) ?? '';
    if (fontPath.isNotEmpty) {
      _fontFamily = await _loadFontFile(fontPath);
    } else {
      _fontFamily = prefs.getString(_keyFontFamily) ?? '';
    }
    _amoled = prefs.getBool(_keyAmoled) ?? false;
    _foregroundOpacity = (prefs.getDouble(_keyForegroundOpacity) ?? 0.0).clamp(0.0, 1.0);
    final labOn = prefs.getBool('lab_enabled') ?? false;
    _eink = labOn && (prefs.getBool('lab_eink') ?? false);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeedColor, color.value);
    notifyListeners();
  }

  Future<void> setDynamicColor(bool value) async {
    _dynamicColor = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDynamicColor, value);
    notifyListeners();
  }

  Future<void> setAmoled(bool value) async {
    _amoled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAmoled, value);
    notifyListeners();
  }

  Future<void> setForegroundOpacity(double value) async {
    _foregroundOpacity = value.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyForegroundOpacity, _foregroundOpacity);
    notifyListeners();
  }

  /// 注册自定义字体文件（支持设备文件路径与 assets 路径）。
  ///
  /// 成功返回该字体的 family 名（用于 ThemeData.fontFamily），失败返回空串。
  /// 用 static Set 去重，避免每次重建都重复注册。
  static Future<String> _loadFontFile(String path) async {
    final family = path.split(RegExp(r'[\\/]')).last.split('.').first.trim();
    if (family.isEmpty) return '';
    if (_loadedFonts.contains(family)) return family;
    try {
      Uint8List bytes;
      if (path.startsWith('assets/')) {
        final data = await rootBundle.load(path);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } else {
        bytes = await File(path).readAsBytes();
      }
      final loader = FontLoader(family);
      loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
      await loader.load();
      _loadedFonts.add(family);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFontFamily, family);
      return family;
    } catch (_) {
      // 字体文件损坏或不可读时退回内置字体，不影响启动
      return '';
    }
  }

  Future<void> setFontScale(double value) async {
    _fontScale = value.clamp(0.5, 3.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontScale, _fontScale);
    notifyListeners();
  }

  /// 切换自定义字体：传入字体文件路径，空串表示恢复系统字体。
  Future<void> setFontPath(String path) async {
    _fontFamily = path.isEmpty ? '' : await _loadFontFile(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFontPath, path);
    notifyListeners();
  }

  ThemeData get lightTheme => _buildTheme(Brightness.light);
  ThemeData get darkTheme => _buildTheme(Brightness.dark);

  /// AMOLED 下容器背景的灰度。opacity=0 → 纯黑；=1 → 标准深灰(#121212 附近)
  Color _elevatedSurface() {
    final v = (11 + 11 * _foregroundOpacity).round();
    return Color.fromARGB(255, v, v, v);
  }

  ThemeData _buildTheme(Brightness brightness) {
    final useAmoled = brightness == Brightness.dark && _amoled;
    final base = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
      // 墨水屏模式提高对比度
      contrastLevel: _eink ? 0.5 : 0.0,
    );
    final colorScheme = useAmoled
        ? base.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: Colors.black,
            surfaceContainer: Colors.black,
            surfaceContainerHigh: _elevatedSurface(),
            surfaceContainerHighest: _elevatedSurface(),
            onSurface: const Color(0xFFE6E1E5),
          )
        : base;

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: _fontFamily.isNotEmpty ? _fontFamily : null,
      // 墨水屏模式去除页面切换动画，减少残影
      pageTransitionsTheme: _eink
          ? const PageTransitionsTheme(builders: {
              TargetPlatform.android: _NoTransitionsBuilder(),
              TargetPlatform.iOS: _NoTransitionsBuilder(),
            })
          : null,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardTheme(
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 0.5,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainerHigh),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
      searchViewTheme: SearchViewThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
    return _fontScale == 1.0
        ? theme
        : theme.copyWith(
            textTheme: theme.textTheme.apply(fontSizeFactor: _fontScale),
            primaryTextTheme: theme.primaryTextTheme.apply(fontSizeFactor: _fontScale),
          );
  }
}

/// 无页面切换动画（墨水屏模式），直接显示目标页面
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
