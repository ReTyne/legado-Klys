import 'package:shared_preferences/shared_preferences.dart';

/// 阅读偏好设置
class ReadPreferences {
  final SharedPreferences _prefs;
  ReadPreferences(this._prefs);

  static Future<ReadPreferences> create() async =>
      ReadPreferences(await SharedPreferences.getInstance());

  double get fontSize => _prefs.getDouble('read_fontSize') ?? 18;
  Future<void> setFontSize(double v) => _prefs.setDouble('read_fontSize', v);

  double get lineSpacing => _prefs.getDouble('read_lineSpacing') ?? 1.5;
  Future<void> setLineSpacing(double v) => _prefs.setDouble('read_lineSpacing', v);

  int get pageAnim => _prefs.getInt('read_pageAnim') ?? 0;
  Future<void> setPageAnim(int v) => _prefs.setInt('read_pageAnim', v);

  int get bgColor => _prefs.getInt('read_bgColor') ?? 0xFFF7F1E1;
  Future<void> setBgColor(int v) => _prefs.setInt('read_bgColor', v);

  int get textColor => _prefs.getInt('read_textColor') ?? 0xFF333333;
  Future<void> setTextColor(int v) => _prefs.setInt('read_textColor', v);

  bool get replaceEnable => _prefs.getBool('oc_replaceDefault') ?? true;
  double get ttsRate => _prefs.getDouble('tts_rate') ?? 1.0;
  bool get clickNextPage => _prefs.getBool('read_clickNext') ?? true;
}
