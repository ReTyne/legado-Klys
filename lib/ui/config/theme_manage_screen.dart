import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/constant/app_theme.dart';
import 'package:legado_md3/help/config/app_config.dart';
import 'package:legado_md3/help/config/theme_share.dart';

import 'package:legado_md3/ui/theme/app_design.dart';
part 'parts/preset.dart';
part 'parts/theme_manage_screen.dart';
part 'parts/theme_manage_screen_state.dart';
part 'parts/hsv_color_picker_dialog.dart';
part 'parts/hsv_color_picker_dialog_state.dart';


class CustomTheme {
  final String id;
  final String name;
  final int primaryColor;
  final int secondaryColor;
  final int backgroundColor;
  final int surfaceColor;
  final bool isDark;
  /// 是否标记为适合 AMOLED 纯黑前景（用于主题分类筛选）
  final bool amoled;
  CustomTheme({required this.id, required this.name, required this.primaryColor, required this.secondaryColor, required this.backgroundColor, required this.surfaceColor, this.isDark = false, this.amoled = false});
  factory CustomTheme.fromJson(Map<String, dynamic> json) => CustomTheme(
    id: json['id'] ?? '', name: json['name'] ?? '',
    primaryColor: json['primaryColor'] ?? 0xFF6750A4,
    secondaryColor: json['secondaryColor'] ?? 0xFF625B71,
    backgroundColor: json['backgroundColor'] ?? 0xFFFFFBFE,
    surfaceColor: json['surfaceColor'] ?? 0xFFFFFBFE,
    isDark: json['isDark'] ?? false,
    amoled: json['amoled'] ?? false,
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'primaryColor': primaryColor,
    'secondaryColor': secondaryColor, 'backgroundColor': backgroundColor,
    'surfaceColor': surfaceColor, 'isDark': isDark, 'amoled': amoled,
  };
}
