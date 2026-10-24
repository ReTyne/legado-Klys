import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/ui/book/source/qr_share_screen.dart';
import 'package:legado_md3/ui/config/theme_manage_screen.dart';

/// 主题分享编解码：主题 JSON 的导出 / 导入 / 二维码 data URI。
///
/// 主题数据结构复用主题管理页的 [CustomTheme]（字段勿在此重复定义）；
/// 持久化位置与 `ThemeManageScreen` 一致：SharedPreferences `custom_themes`
/// （JSON 字符串列表，同 id 覆盖）。
class ThemeShare {
  ThemeShare._();

  static final ThemeShare instance = ThemeShare._();

  /// 与 ThemeManageScreen 共用的「我的主题」存储键
  static const String kCustomThemesKey = 'custom_themes';

  /// 主题 → JSON 字符串
  static String exportThemeJson(CustomTheme theme) => jsonEncode(theme.toJson());

  /// JSON → 主题对象（解析失败 / 结构不符返回 null）。
  /// 兼容分享端的别名键（themeName / colorPrimary / colorAccent / colorBackground / colorSurface）。
  static CustomTheme? parseThemeJson(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map) return null;
      final m = Map<String, dynamic>.from(data);
      m['name'] ??= m['themeName'];
      m['primaryColor'] ??= _colorValue(m['colorPrimary']);
      m['secondaryColor'] ??= _colorValue(m['colorAccent']);
      m['backgroundColor'] ??= _colorValue(m['colorBackground']);
      m['surfaceColor'] ??= _colorValue(m['colorSurface']);
      return CustomTheme.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  /// 导入主题 JSON：解析并写入「我的主题」列表（同 id 覆盖，否则追加）。
  /// 返回导入后的主题；解析失败返回 null（不写库）。
  static Future<CustomTheme?> importThemeJson(String json) async {
    final theme = parseThemeJson(json);
    if (theme == null) return null;
    // id 为空（来源不含 id）时生成一个，避免互相覆盖
    final id = theme.id.isNotEmpty
        ? theme.id
        : 'imported_${DateTime.now().millisecondsSinceEpoch}';
    final target = id == theme.id
        ? theme
        : CustomTheme(
            id: id,
            name: theme.name.isEmpty ? '导入主题' : theme.name,
            primaryColor: theme.primaryColor,
            secondaryColor: theme.secondaryColor,
            backgroundColor: theme.backgroundColor,
            surfaceColor: theme.surfaceColor,
            isDark: theme.isDark,
            amoled: theme.amoled,
          );
    final prefs = await SharedPreferences.getInstance();
    final entries =
        (prefs.getStringList(kCustomThemesKey) ?? const <String>[]).toList();
    final encoded = jsonEncode(target.toJson());
    final existing = entries.indexWhere((e) {
      try {
        final m = jsonDecode(e);
        return m is Map && m['id'] == id;
      } catch (_) {
        return false;
      }
    });
    if (existing >= 0) {
      entries[existing] = encoded;
    } else {
      entries.add(encoded);
    }
    await prefs.setStringList(kCustomThemesKey, entries);
    return target;
  }

  /// 导出主题二维码 PNG 的 data URI（`data:image/png;base64,...`）。
  /// 内容超出二维码容量（版本 10 / 纠错 M）或编码异常时返回 null。
  static Future<String?> exportThemeQrDataUri(CustomTheme theme) async {
    try {
      final qr = QrEncoder.encode(exportThemeJson(theme));
      final png = qr.toPngBytes(scale: 10, quietZone: 4);
      return 'data:image/png;base64,${base64Encode(png)}';
    } on QrEncodeException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 颜色值归一：int 原样返回；`#RRGGBB` / `RRGGBB` 字符串转 ARGB int；其余原样返回。
  static dynamic _colorValue(dynamic v) {
    if (v is int) return v;
    if (v is String) {
      final hex = v.replaceFirst('#', '').trim();
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        return hex.length <= 6 ? 0xFF000000 | parsed : parsed;
      }
    }
    return v;
  }
}
