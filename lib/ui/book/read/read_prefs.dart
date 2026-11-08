import 'package:shared_preferences/shared_preferences.dart';

/// 第十轮 C 组：不落在 [ReadConfig]（主代理独占模型 `lib/data/model/read_config.dart`）
/// 内的阅读配置项，统一在此集中定义键并用 SharedPreferences 持久化。
///
/// 覆盖 Sigma `pref_config_read.xml` 的 4 个额外键
/// （progressBarBehavior / showBrightnessView / expandTextMenu / mouseWheelPage）
/// 与本域新增的「双指预览替换 / 跟随系统亮度 / 自动页数估算」。
/// 阅读页与阅读设置页共用本文件，避免键名分叉形成新的数据孤岛。
class ReadPrefs {
  ReadPrefs._();

  /// 进度条行为：'page' 章内按页拖动 / 'chapter' 按章拖动（默认）
  static const String kProgressBarBehavior = 'read_progressBarBehavior';

  /// 是否在阅读设置面板显示真实亮度视图
  static const String kShowBrightnessView = 'read_showBrightnessView';

  /// 文字选择菜单是否展开全部动作（关闭时仅保留常用 4 项）
  static const String kExpandTextMenu = 'read_expandTextMenu';

  /// 鼠标/触控板滚轮（PointerScrollEvent）翻页
  static const String kMouseWheelPage = 'read_mouseWheelPage';

  /// 双指点击预览替换净化效果
  static const String kTwoFingerReplacePreview = 'read_twoFingerReplacePreview';

  /// 亮度跟随系统（真实系统背光，而非遮罩）
  static const String kFollowSystemBrightness = 'read_followSystemBrightness';

  /// 进入章节时自动估算并落库页数
  static const String kPageEstimateAuto = 'read_pageEstimateAuto';

  static Future<bool> getBool(String key, {bool fallback = true}) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> setBool(String key, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, value);
    } catch (_) {}
  }

  static Future<String> getString(String key, {String fallback = ''}) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> setString(String key, String value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, value);
    } catch (_) {}
  }
}
