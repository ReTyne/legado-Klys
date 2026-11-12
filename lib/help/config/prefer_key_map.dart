/// 偏好键名映射层：Android ↔ Flutter(legado_md3) 备份互通。
///
/// 逐字**字符串值**（约 20 个键的
/// 常量名 ≠ 键名，照常量名拼写会静默读不到值，见扫描报告 #29/#30）。
///
/// Flutter 侧 `AppPrefs`（app_constants.dart）有 4 个自造键名与上游不一致，
/// 备份导入 Android `config.xml` 时这些设置会静默丢失。本层提供：
///  - [UpstreamPrefKey]：上游字符串键权威表；
///  - [PreferKeyMap]：Flutter↔上游键名双向映射与批量往返（仅键名，值原样）；
///  - 值级转换器（themeMode / clickActions），不等价处显式标注。
///
/// 消费闭环见 app_constants.dart 的 `AppPrefs.loadFrom`（别名双读）与
/// `AppPrefs.importFromUpstream` / `AppPrefs.exportForUpstream`。
library;

/// 上游 `constant/PreferKey.kt` 的字符串键（权威值，非 Flutter 键）。
/// 只列出与「键名≠常量名」及本项目自造键相关的条目，供导入识别。
class UpstreamPrefKey {
  UpstreamPrefKey._();

  static const String useDefaultCover = 'useDefaultCover';
  static const String coverShowName = 'coverShowName';
  static const String coverShowAuthor = 'coverShowAuthor';
  static const String exportToWebDav = 'webDavCacheBackup';
  static const String themeMode = 'themeMode';
  static const String ttsEngine = 'appTtsEngine';
  static const String prevKeys = 'prevKeyCodes';
  static const String nextKeys = 'nextKeyCodes';
  static const String textSelectAble = 'selectText';
  static const String keepLight = 'keep_light';
  static const String processText = 'process_text';
  static const String doublePageHorizontal = 'doubleHorizontalPage';
  static const String readUrlOpenInBrowser = 'readUrlInBrowser';
  // 九宫格点击动作 9 个独立键（PreferKey.kt:26-34）
  static const String clickActionTL = 'clickActionTopLeft';
  static const String clickActionTC = 'clickActionTopCenter';
  static const String clickActionTR = 'clickActionTopRight';
  static const String clickActionML = 'clickActionMiddleLeft';
  static const String clickActionMC = 'clickActionMiddleCenter';
  static const String clickActionMR = 'clickActionMiddleRight';
  static const String clickActionBL = 'clickActionBottomLeft';
  static const String clickActionBC = 'clickActionBottomCenter';
  static const String clickActionBR = 'clickActionBottomRight';
}

/// 九宫格点击动作上游键顺序（行优先：TL,TC,TR,ML,MC,MR,BL,BC,BR）。
const List<String> kUpstreamClickActionKeys = <String>[
  UpstreamPrefKey.clickActionTL,
  UpstreamPrefKey.clickActionTC,
  UpstreamPrefKey.clickActionTR,
  UpstreamPrefKey.clickActionML,
  UpstreamPrefKey.clickActionMC,
  UpstreamPrefKey.clickActionMR,
  UpstreamPrefKey.clickActionBL,
  UpstreamPrefKey.clickActionBC,
  UpstreamPrefKey.clickActionBR,
];

/// Flutter ↔ 上游键名映射层。
class PreferKeyMap {
  PreferKeyMap._();

  /// Flutter 键 → 上游键（仅登记不一致项；相同键名直通）。
  /// 依据扫描报告 #30 的自造键 + #34 theme_mode。
  static const Map<String, String> flutterToUpstream = <String, String>{
    'cover_useDefault': UpstreamPrefKey.useDefaultCover,
    'cover_showName': UpstreamPrefKey.coverShowName,
    'cover_showAuthor': UpstreamPrefKey.coverShowAuthor,
    'exportToWebDav': UpstreamPrefKey.exportToWebDav,
    'theme_mode': UpstreamPrefKey.themeMode,
  };

  /// 上游键 → Flutter 键（[flutterToUpstream] 的反转）。
  static final Map<String, String> upstreamToFlutter =
      Map<String, String>.fromEntries(
    flutterToUpstream.entries.map(
      (MapEntry<String, String> e) => MapEntry<String, String>(e.value, e.key),
    ),
  );

  /// 单个键：Flutter → 上游（无映射则原样返回）。
  static String toUpstream(String flutterKey) =>
      flutterToUpstream[flutterKey] ?? flutterKey;

  /// 单个键：上游 → Flutter（无映射则原样返回）。
  static String fromUpstream(String upstreamKey) =>
      upstreamToFlutter[upstreamKey] ?? upstreamKey;

  /// 批量导出：Flutter prefs Map → 上游键名 Map（值原样）。
  static Map<String, dynamic> exportToUpstream(Map<String, dynamic> flutter) {
    final Map<String, dynamic> out = <String, dynamic>{};
    flutter.forEach((String k, dynamic v) {
      out[toUpstream(k)] = v;
    });
    return out;
  }

  /// 批量导入：上游 config.xml prefs Map → Flutter 键名 Map（值原样）。
  static Map<String, dynamic> importFromUpstream(Map<String, dynamic> upstream) {
    final Map<String, dynamic> out = <String, dynamic>{};
    upstream.forEach((String k, dynamic v) {
      out[fromUpstream(k)] = v;
    });
    return out;
  }

  /// #34：Android `themeMode` 为 String "0/1/2/3"（"3"=EInk），
  /// Flutter `theme_mode` 为 int(ThemeMode.index)，EInk 另拆 `lab_eink` 开关。
  /// 这里做数值/字符串互转；EInk("3") 合并进独立键的语义无法完全等价
  /// （不等价，显式标注）：导入 "3" 退回 0(跟随系统)，导出用 [eink] 合成 "3"。
  static int importThemeMode(Object? upstream) {
    if (upstream is int) return upstream.clamp(0, 2);
    final int? parsed = int.tryParse(upstream?.toString() ?? '');
    if (parsed == null) return 0;
    return parsed == 3 ? 0 : parsed.clamp(0, 2);
  }

  static String exportThemeMode(int mode, {bool eink = false}) =>
      eink ? '3' : mode.clamp(0, 2).toString();

  /// #31：Android 9 个独立 `clickAction*` 键 ↔ Flutter 单键 `click_actions` 逗号串。
  ///
  /// 仅做**结构**映射（9 键 ↔ 9 段 CSV），值原样搬运。上游动作编码 0/1/2
  /// 与 Flutter 0-14 不同、默认矩阵也不同，**未做码值翻译（不等价，显式标注）**。
  static const String clickActionsKey = 'click_actions';

  /// 上游 9 键 → Flutter 单键 CSV。缺失键用 [fallbackSegments] 对应位补齐。
  static String importClickActions(
    Map<String, dynamic> upstream, {
    List<String> fallbackSegments = const <String>[
      '2', '2', '1', '2', '0', '1', '2', '1', '1'
    ],
  }) {
    final List<String> segs = <String>[];
    for (int i = 0; i < kUpstreamClickActionKeys.length; i++) {
      final Object? v = upstream[kUpstreamClickActionKeys[i]];
      final String fb =
          i < fallbackSegments.length ? fallbackSegments[i] : '0';
      segs.add(v == null ? fb : v.toString());
    }
    return segs.join(',');
  }

  /// Flutter 单键 CSV → 上游 9 键 Map。
  static Map<String, dynamic> exportClickActions(String csv) {
    final List<String> segs = csv.split(',');
    final Map<String, dynamic> out = <String, dynamic>{};
    for (int i = 0; i < kUpstreamClickActionKeys.length; i++) {
      final String raw = i < segs.length ? segs[i].trim() : '';
      out[kUpstreamClickActionKeys[i]] = int.tryParse(raw) ?? 0;
    }
    return out;
  }
}
