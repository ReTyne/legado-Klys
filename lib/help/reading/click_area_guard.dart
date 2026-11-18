/// 九宫格点击区守卫：防止所有区域都没有配置「显示菜单」。
///
/// 包含可单测的纯 Dart 校验函数，以及基于 SharedPreferences 的
/// 读取/逐区持久化封装（动作编码与 prefer_key_map.dart 的 9 个独立键一致：
/// 3 = 显示菜单，中心区下标 4）。
library;

import 'package:legado_md3/help/config/prefer_key_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「显示菜单」动作编码。
const int menuClickAction = 3;

/// 九区缺省矩阵（左列上一章 / 中列菜单 / 右列下一章）。
const List<int> defaultClickActions = <int>[1, 3, 2, 1, 3, 2, 1, 3, 2];

/// 纯校验：九区是否都不等于 3（没有任何菜单区域）。
bool clickAreaNeedsGuard(List<int> actions) =>
    actions.length == 9 && actions.every((a) => a != menuClickAction);

/// 纯修复：命中守卫时把中心区（index 4）写回 3，返回新列表。
/// 未命中时原样返回（列表内容不变）。
List<int> applyClickAreaGuard(List<int> actions) {
  if (!clickAreaNeedsGuard(actions)) return List<int>.from(actions);
  final fixed = List<int>.from(actions);
  fixed[4] = menuClickAction;
  return fixed;
}

/// 读取九区配置；未配置（无 CSV）时返回 null。
List<int>? readClickActions(SharedPreferences prefs) {
  final raw = prefs.getString(PreferKeyMap.clickActionsKey);
  if (raw == null) return null;
  final parts = raw
      .split(',')
      .map((e) => int.tryParse(e.trim()) ?? 2)
      .toList();
  return parts.length == 9 ? parts : null;
}

/// 逐区持久化：单键 CSV + Android 互通的 9 个独立 `clickAction*` 键。
Future<void> persistClickActions(
  SharedPreferences prefs,
  List<int> actions,
) async {
  final csv = actions.join(',');
  await prefs.setString(PreferKeyMap.clickActionsKey, csv);
  final perArea = PreferKeyMap.exportClickActions(csv);
  for (final entry in perArea.entries) {
    await prefs.setInt(entry.key, entry.value as int);
  }
}

/// 读取当前九区，若全非菜单则把中心区修复为菜单并逐区持久化，返回 true。
/// 未配置、长度异常或已含菜单时不做任何改动，返回 false。
Future<bool> detectClickArea(SharedPreferences prefs) async {
  final actions = readClickActions(prefs);
  if (actions == null || !clickAreaNeedsGuard(actions)) return false;
  await persistClickActions(prefs, applyClickAreaGuard(actions));
  return true;
}
