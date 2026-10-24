import 'package:shared_preferences/shared_preferences.dart';

/// 视频播放配置（对齐 legado-E `model/VideoPlay.kt` 的 `video_config` 偏好）。
///
/// E 的四个配置项：
/// * autoPlay —— 是否自动播放（默认 true）
/// * startFull —— 直接全屏（默认 false，需先启用自动播放）
/// * longPressSpeed —— 长按倍速，以 0.1x 为单位的整数（默认 30 = 3.0x，
///   取值范围 5–60 即 0.5x–6.0x）
/// * fullBottomProgressBar —— 全屏底部进度条（默认 true）
class VideoPlayConfig {
  VideoPlayConfig._();

  /// 长按倍速以 0.1x 为步进（E: NumberPickerDialog min 5 / max 60）
  static const int minSpeedTenths = 5;
  static const int maxSpeedTenths = 60;
  static const int defaultSpeedTenths = 30;

  static bool autoPlay = true;
  static bool startFull = false;
  static int longPressSpeedTenths = defaultSpeedTenths;
  static bool fullBottomProgressBar = true;

  /// 长按倍速显示文本（E: press_speed_summary "长按倍速 %.1f"）
  static String get longPressSpeedLabel =>
      '${(longPressSpeedTenths / 10).toStringAsFixed(1)}x';

  /// 应用启动/进入播放器时加载（E: videoPrefs 懒加载等价物）
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    autoPlay = p.getBool('autoPlay') ?? true;
    startFull = p.getBool('startFull') ?? false;
    longPressSpeedTenths =
        (p.getInt('longPressSpeed') ?? defaultSpeedTenths)
            .clamp(minSpeedTenths, maxSpeedTenths);
    fullBottomProgressBar = p.getBool('fullBottomProgressBar') ?? true;
  }

  static Future<void> setAutoPlay(bool v) async {
    autoPlay = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('autoPlay', v);
  }

  static Future<void> setStartFull(bool v) async {
    startFull = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('startFull', v);
  }

  static Future<void> setLongPressSpeed(int tenths) async {
    longPressSpeedTenths = tenths.clamp(minSpeedTenths, maxSpeedTenths);
    final p = await SharedPreferences.getInstance();
    await p.setInt('longPressSpeed', longPressSpeedTenths);
  }

  static Future<void> setFullBottomProgressBar(bool v) async {
    fullBottomProgressBar = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('fullBottomProgressBar', v);
  }
}
