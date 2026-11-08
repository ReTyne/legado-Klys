import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/model/homepage_module.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

part 'parts/homepage_action.dart';
part 'parts/homepage_item.dart';
part 'parts/homepage_module_data.dart';
part 'parts/homepage_item_tap.dart';
part 'parts/homepage_module_view.dart';
part 'parts/banner_section.dart';
part 'parts/button_group_section.dart';
part 'parts/card_section.dart';
part 'parts/grid_section.dart';
part 'parts/ranking_section.dart';
part 'parts/rank_badge.dart';
part 'parts/waterfall_section.dart';


/// 当前启用的首页模块集 id 持久化（Feed 与模块集管理页共用）。
/// - null / 0：不使用模块集，展示全部启用模块（DAO 已按 customOrder 排序）。
/// - 其它：只展示该模块集 moduleIds 内、且启用的模块，顺序按 moduleIds。
class HomepageSetStore {
  HomepageSetStore._();

  static const String activeSetIdKey = 'homepage_active_set_id';

  static Future<int?> loadActiveSetId() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt(activeSetIdKey);
      return (v == null || v <= 0) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveActiveSetId(int? id) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (id == null || id <= 0) {
        await p.remove(activeSetIdKey);
      } else {
        await p.setInt(activeSetIdKey, id);
      }
    } catch (_) {}
  }

  /// 解析 HomepageCustomSet.moduleIds（JSON 数组）为模块 id 列表。
  static List<int> parseModuleIds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <int>[];
    try {
      final d = jsonDecode(raw);
      if (d is List) {
        return d
            .map<int>((e) => e is int ? e : int.tryParse('$e') ?? -1)
            .where((e) => e > 0)
            .toList();
      }
    } catch (_) {}
    return const <int>[];
  }

  static String encodeModuleIds(List<int> ids) => jsonEncode(ids);
}

/// 首页模块类型的中文标签（Feed 与管理页共用）。
String homepageModuleTypeLabel(HomepageModuleType t) => switch (t) {
      HomepageModuleType.banner => '横幅',
      HomepageModuleType.buttonGroup => '按钮组',
      HomepageModuleType.card => '卡片',
      HomepageModuleType.grid => '网格',
      HomepageModuleType.gridRanking => '网格排行',
      HomepageModuleType.ranking => '排行榜',
      HomepageModuleType.waterfall => '瀑布流',
      HomepageModuleType.custom => '自定义',
    };
