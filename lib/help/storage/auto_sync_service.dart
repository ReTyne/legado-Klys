import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/storage/backup_service.dart';
import 'package:legado_md3/help/storage/webdav_service.dart';

/// 启动时自动 WebDAV 同步（实验室开关 lab_webdavOpen）。
/// 仅当：实验室总开关开启 + 自动同步开启 + 已配置 WebDAV 地址 时，
/// 静默上传一份完整备份。任何失败都被吞掉，绝不影响启动。
class AutoSyncService {
  AutoSyncService._();

  /// 同步阅读进度开关（settings_screen「同步阅读进度」：备份时一并上传进度）
  static const String keySyncProgress = 'webdav_syncProgress';

  static Future<void> syncOnOpen() async {
    try {
      final p = await SharedPreferences.getInstance();
      final labOn = p.getBool('lab_enabled') ?? false;
      final autoOn = p.getBool('lab_webdavOpen') ?? false;
      if (!labOn || !autoOn) return;

      final url = (p.getString('webdav_url') ?? '').trim();
      if (url.isEmpty) return;
      final user = p.getString('webdav_user');
      final pass = p.getString('webdav_pass');

      final webdav = WebDavService()
        ..configure(baseUrl: url, username: user, password: pass);
      if (!await webdav.testConnection()) return;

      final backup = await BackupService().createBackup();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final ok = await webdav.uploadBackup('backup_$ts.json', utf8.encode(jsonEncode(backup)));
      if (!ok) return;

      // webdav_syncProgress：备份上传成功后，一并上传阅读进度（默认开启，同 settings_screen 口径）
      if (p.getBool(keySyncProgress) ?? true) {
        final progress = await DatabaseService().getAllBookProgress();
        if (progress.isNotEmpty) {
          await webdav.uploadReadingProgress(progress.map((e) => e.toMap()).toList());
        }
      }
    } catch (_) {
      // 自动同步是后台增强能力，失败静默，不打扰用户、不阻断启动
    }
  }
}
