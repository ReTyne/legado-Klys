import 'dart:convert';
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
        if (href.endsWith('.json') || href.endsWith('.bak')) {
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
