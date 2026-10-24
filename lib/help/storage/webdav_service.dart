import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/read_record.dart';

/// WebDAV备份服务
class WebDavService {
  final Dio _dio = Dio();
  String? _baseUrl;

  /// 配置WebDAV
  void configure({required String baseUrl, String? username, String? password}) {
    _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    _dio.options.headers = {
      if (username != null && password != null)
        'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
    };
  }

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      if (_baseUrl == null) return false;
      final response = await _dio.request(
        _baseUrl!,
        options: Options(method: 'PROPFIND', headers: {'Depth': '0'}),
      );
      return response.statusCode == 207;
    } catch (e) {
      return false;
    }
  }

  /// 上传备份
  Future<bool> uploadBackup(String fileName, List<int> data) async {
    try {
      if (_baseUrl == null) return false;
      final url = '${_baseUrl}legado_backup/$fileName';
      // 确保目录存在
      try {
        await _dio.request('${_baseUrl}legado_backup/', options: Options(method: 'MKCOL'));
      } catch (_) {}
      final response = await _dio.put(url, data: data);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  /// 下载备份
  Future<List<int>?> downloadBackup(String fileName) async {
    try {
      if (_baseUrl == null) return null;
      final url = '${_baseUrl}legado_backup/$fileName';
      final response = await _dio.get(url, options: Options(responseType: ResponseType.bytes));
      return response.data as List<int>;
    } catch (e) {
      return null;
    }
  }

  /// 列出备份文件
  Future<List<String>> listBackups() async {
    try {
      if (_baseUrl == null) return [];
      final url = '${_baseUrl}legado_backup/';
      final response = await _dio.request(
        url,
        options: Options(method: 'PROPFIND', headers: {'Depth': '1'}),
      );
      // 解析XML响应提取文件名
      final body = response.data.toString();
      final files = <String>[];
      final regex = RegExp(r'<d:href>([^<]+)</d:href>');
      for (final match in regex.allMatches(body)) {
        final href = match.group(1)!;
        if (href.endsWith('.json') || href.endsWith('.bak') || href.endsWith('.zip')) {
          files.add(href.split('/').last);
        }
      }
      return files;
    } catch (e) {
      return [];
    }
  }

  /// 删除备份
  Future<bool> deleteBackup(String fileName) async {
    try {
      if (_baseUrl == null) return false;
      final url = '${_baseUrl}legado_backup/$fileName';
      final response = await _dio.delete(url);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  /// 列出指定目录下的所有条目（isDir 区分目录/文件），用于远程书库浏览
  Future<List<WebDavEntry>> listDir(String dir) async {
    try {
      if (_baseUrl == null) return [];
      var d = dir.trim();
      if (d.isEmpty) d = '/';
      if (!d.endsWith('/')) d = '$d/';
      if (d.startsWith('/')) d = d.substring(1);
      final url = '$_baseUrl$d';
      final response = await _dio.request(
        url,
        options: Options(method: 'PROPFIND', headers: {'Depth': '1'}),
      );
      final body = response.data.toString();
      final entries = <WebDavEntry>[];
      // 按 <D:response> 块解析，提取 href 与是否集合
      final respRegex = RegExp(r'<[a-zA-Z]*:?response>(.*?)<[a-zA-Z]*:\/response>', dotAll: true);
      final hrefRegex = RegExp(r'<[a-zA-Z]*:?href>([^<]+)</[a-zA-Z]*:?href>');
      final dirRegex = RegExp(r'<[a-zA-Z]*:?collection\s*/?>');
      for (final m in respRegex.allMatches(body)) {
        final block = m.group(1)!;
        final hrefM = hrefRegex.firstMatch(block);
        if (hrefM == null) continue;
        var href = Uri.decodeComponent(hrefM.group(1)!);
        // 去掉开头的主机路径，只保留相对当前目录的名字
        final name = href.split('/').where((s) => s.isNotEmpty).last;
        final currentName = d.split('/').where((s) => s.isNotEmpty).last;
        if (name == currentName) continue; // 跳过自身目录
        final isDir = dirRegex.hasMatch(block);
        entries.add(WebDavEntry(name, isDir, href));
      }
      return entries;
    } catch (e) {
      return [];
    }
  }

  /// 从指定目录下载文件
  Future<List<int>?> downloadFile(String dir, String fileName) async {
    try {
      if (_baseUrl == null) return null;
      var d = dir.trim();
      if (d.isNotEmpty && !d.endsWith('/')) d = '$d/';
      if (d.startsWith('/')) d = d.substring(1);
      final url = '$_baseUrl$d$fileName';
      final response = await _dio.get(url, options: Options(responseType: ResponseType.bytes));
      return response.data as List<int>;
    } catch (e) {
      return null;
    }
  }

  /// 上传书籍文件到远程书库（对齐 E `RemoteBookWebDav.upload`）：
  /// 目标为 `<baseUrl>/<bookDir>/<fileName>`，先 MKCOL 确保目录存在。
  /// 返回是否上传成功；调用方负责标记 book.origin（`webDav::<putUrl>`）。
  Future<bool> uploadBook(String localPath, {String bookDir = '书籍'}) async {
    try {
      if (_baseUrl == null) return false;
      final file = File(localPath);
      if (!await file.exists()) return false;
      var d = bookDir.trim();
      if (d.isEmpty) d = '书籍';
      if (!d.endsWith('/')) d = '$d/';
      if (d.startsWith('/')) d = d.substring(1);
      final name = file.uri.pathSegments.last;
      // 确保目录存在（已存在时服务端返回 405，忽略）
      try {
        await _dio.request('$_baseUrl$d', options: Options(method: 'MKCOL'));
      } catch (_) {}
      final response = await _dio.put('$_baseUrl$d$name', data: await file.readAsBytes());
      return response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  /// 组装远程书籍地址（E: `webDav::` + putUrl），用于标记书籍已上传。
  static String remoteBookUrl(String baseUrl, String bookDir, String fileName) {
    var root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    var d = bookDir.trim();
    if (d.isEmpty) d = '书籍';
    if (!d.endsWith('/')) d = '$d/';
    if (d.startsWith('/')) d = d.substring(1);
    return 'webDav::$root$d$fileName';
  }

  /// 上传阅读进度
  Future<bool> uploadReadingProgress(List<Map<String, dynamic>> progress) async {
    final data = jsonEncode({'progress': progress, 'time': DateTime.now().millisecondsSinceEpoch});
    return uploadBackup('reading_progress.json', utf8.encode(data));
  }

  /// 下载阅读进度
  Future<List<Map<String, dynamic>>?> downloadReadingProgress() async {
    final data = await downloadBackup('reading_progress.json');
    if (data == null) return null;
    final json = jsonDecode(utf8.decode(data));
    return (json['progress'] as List).cast<Map<String, dynamic>>();
  }

  /// 同步书籍
  Future<bool> syncBooks(List<Book> books) async {
    final data = jsonEncode({'books': books.map((b) => b.toMap()).toList(), 'time': DateTime.now().millisecondsSinceEpoch});
    return uploadBackup('books.json', utf8.encode(data));
  }

  /// 同步书源
  Future<bool> syncBookSources(List<BookSource> sources) async {
    final data = jsonEncode({'sources': sources.map((s) => s.toJson()).toList(), 'time': DateTime.now().millisecondsSinceEpoch});
    return uploadBackup('book_sources.json', utf8.encode(data));
  }

  /// 同步阅读记录
  Future<bool> syncReadRecords(List<ReadRecord> records) async {
    final data = jsonEncode({'records': records.map((r) => r.toMap()).toList(), 'time': DateTime.now().millisecondsSinceEpoch});
    return uploadBackup('read_records.json', utf8.encode(data));
  }
}

/// WebDAV 目录条目
class WebDavEntry {
  final String name;
  final bool isDir;
  final String href;
  WebDavEntry(this.name, this.isDir, this.href);
}
