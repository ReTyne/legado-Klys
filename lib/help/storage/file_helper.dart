import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FileHelper {
  static Future<String> readFile(String path) => File(path).readAsString();

  /// 应用数据根目录
  static Future<Directory> getAppDataDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/legado');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 书籍缓存目录
  static Future<Directory> getBookCacheDir() async {
    final root = await getAppDataDir();
    final dir = Directory('${root.path}/book_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 备份目录
  static Future<Directory> getBackupDir() async {
    final root = await getAppDataDir();
    final dir = Directory('${root.path}/backup');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 导出目录
  static Future<Directory> getExportDir() async {
    final root = await getAppDataDir();
    final dir = Directory('${root.path}/export');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static Future<int> dirSize(Directory dir) async {
    int total = 0;
    if (!dir.existsSync()) return 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }
}
