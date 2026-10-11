import 'package:shared_preferences/shared_preferences.dart';

/// 应用级偏好设置
class AppPreferences {
  final SharedPreferences _prefs;
  AppPreferences(this._prefs);

  static Future<AppPreferences> create() async =>
      AppPreferences(await SharedPreferences.getInstance());

  // 语言
  int get language => _prefs.getInt('oc_language') ?? 0;
  Future<void> setLanguage(int v) => _prefs.setInt('oc_language', v);

  // 自动检查更新
  bool get autoCheckUpdate => _prefs.getBool('oc_autoCheckUpdate') ?? true;
  Future<void> setAutoCheckUpdate(bool v) => _prefs.setBool('oc_autoCheckUpdate', v);

  // Web 服务
  bool get webAutoStart => _prefs.getBool('oc_webAutoStart') ?? false;
  int get webPort => _prefs.getInt('oc_webPort') ?? 1122;
  Future<void> setWebPort(int v) => _prefs.setInt('oc_webPort', v);

  // 本地密码
  String? get localPassword => _prefs.getString('oc_password');
  Future<void> setLocalPassword(String v) => _prefs.setString('oc_password', v);

  // WebDAV
  String? get webdavUrl => _prefs.getString('webdav_url');
  String? get webdavUser => _prefs.getString('webdav_user');
  String? get webdavPass => _prefs.getString('webdav_pass');
  String get webdavDir => _prefs.getString('webdav_dir') ?? 'Legado/backup';
}
