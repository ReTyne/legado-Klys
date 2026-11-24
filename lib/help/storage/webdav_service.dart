import 'dart:async';
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
  /// 备份子目录：由设置页 webdav_dir 配置，上传/下载/列举/删除统一使用，
  /// 默认保留历史值 legado_backup 以兼容既有远端备份。
  String _backupDir = 'legado_backup';

  /// PROPFIND 请求体：显式声明所需属性，避免严格服务端拒绝无正文的 PROPFIND。
  static const String propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:getcontentlength/><d:getlastmodified/><d:resourcetype/>'
      '</d:prop></d:propfind>';

  /// 归一化 baseUrl：davs:// → https://，dav:// → http://（大小写不敏感）。
  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    final m = RegExp(r'^(davs?):\/\/', caseSensitive: false).firstMatch(u);
    if (m != null) {
      final scheme = m.group(1)!.toLowerCase() == 'davs' ? 'https' : 'http';
      u = '$scheme://${u.substring(m.group(0)!.length)}';
    }
    return u.endsWith('/') ? u : '$u/';
  }

  /// 配置WebDAV
  void configure({
    required String baseUrl,
    String? username,
    String? password,
    String? dir,
  }) {
    _baseUrl = normalizeBaseUrl(baseUrl);
    if (dir != null && dir.trim().isNotEmpty) _backupDir = dir.trim();
    _dio.options.headers = {
      if (username != null && password != null)
        'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
    };
  }

  /// 归一化备份目录：去掉首尾斜杠并补尾斜杠，供 URL 拼接。
  String get _backupDirPath => _normalizeDir(_backupDir);

  static String _normalizeDir(String dir) {
    var d = dir.trim();
    if (d.isEmpty) d = 'legado_backup';
    if (d.startsWith('/')) d = d.substring(1);
    return d.endsWith('/') ? d : '$d/';
  }

  /// 带指数退避的请求包装：网络异常或 5xx 时最多重试 [retries] 次。
  Future<Response<dynamic>> _requestWithRetry(
    String url, {
    required String method,
    Map<String, String>? headers,
    dynamic data,
    ResponseType? responseType,
    int retries = 2,
  }) async {
    final options =
        Options(method: method, headers: headers, responseType: responseType);
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await _dio.request(url, data: data, options: options);
        final code = response.statusCode ?? 0;
        if (code >= 500 && attempt < retries) {
          lastError = StateError('HTTP $code');
        } else {
          return response;
        }
      } catch (e) {
        lastError = e;
      }
      if (attempt < retries) {
        await Future<void>.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      }
    }
    throw lastError ?? StateError('请求失败');
  }

  /// PROPFIND 统一入口：携带 XML 请求体与 Depth 头。
  Future<Response<dynamic>> _propfind(String url, String depth) =>
      _requestWithRetry(
        url,
        method: 'PROPFIND',
        headers: <String, String>{
          'Depth': depth,
          'Content-Type': 'application/xml; charset=utf-8',
        },
        data: propfindBody,
      );

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      if (_baseUrl == null) return false;
      final response = await _propfind(_baseUrl!, '0');
      return response.statusCode == 207;
    } catch (e) {
      return false;
    }
  }

  /// 上传备份。[dir] 可指定远程子目录（默认 legado_backup），
 /// 每书进度复用本方法写入 `bookProgress/`。
  Future<bool> uploadBackup(
    String fileName,
    List<int> data, {
    String? dir,
  }) async {
    try {
      if (_baseUrl == null) return false;
      final d = (dir == null || dir.trim().isEmpty)
          ? _backupDirPath
          : _normalizeDir(dir);
      final url = '$_baseUrl$d$fileName';
      // 确保目录存在（已存在时服务端返回 405，忽略）
      try {
        await _dio.request('$_baseUrl$d', options: Options(method: 'MKCOL'));
      } catch (_) {}
      final response = await _requestWithRetry(url, method: 'PUT', data: data);
      return response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  /// 下载备份
  Future<List<int>?> downloadBackup(String fileName) async {
    try {
      if (_baseUrl == null) return null;
      final url = '$_baseUrl$_backupDirPath$fileName';
      final response = await _requestWithRetry(
        url,
        method: 'GET',
        responseType: ResponseType.bytes,
      );
      return response.data as List<int>;
    } catch (e) {
      return null;
    }
  }

  /// 列出备份文件
  Future<List<String>> listBackups() async {
    try {
      if (_baseUrl == null) return [];
      final url = '$_baseUrl$_backupDirPath';
      final response = await _propfind(url, '1');
      // 解析XML响应提取文件名
      final body = response.data.toString();
      final files = <String>[];
      final regex = RegExp(r'<[a-zA-Z]*:?href>([^<]+)</[a-zA-Z]*:?href>');
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

  /// 按修改时间选出指定目录中最新的备份文件名；无修改时间时取首个备份文件。
  Future<String?> latestBackup({String? dir}) async {
    final entries = await listDir(dir ?? _backupDir.trim());
    final files = entries
        .where((e) => !e.isDir &&
            (e.name.endsWith('.json') ||
                e.name.endsWith('.bak') ||
                e.name.endsWith('.zip')))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) {
      final at = a.lastModified?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastModified?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return files.first.name;
  }

  /// 删除备份
  Future<bool> deleteBackup(String fileName) async {
    try {
      if (_baseUrl == null) return false;
      final url = '$_baseUrl$_backupDirPath$fileName';
      final response =
          await _requestWithRetry(url, method: 'DELETE');
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
      final response = await _propfind(url, '1');
      final pathParts = d.split('/').where((s) => s.isNotEmpty).toList();
      final currentName = pathParts.isEmpty ? '' : pathParts.last;
      return parsePropfindResponse(response.data.toString(),
          currentDirName: currentName);
    } catch (e) {
      return [];
    }
  }

  /// 解析 PROPFIND 多状态响应为目录条目，宽松处理缺失属性与坏百分号编码。
  ///
  /// [currentDirName] 为当前目录名，命中时跳过自身条目。
  static List<WebDavEntry> parsePropfindResponse(
    String body, {
    String currentDirName = '',
  }) {
    final entries = <WebDavEntry>[];
    // 按 response 块解析，提取 href 与是否集合及可选属性
    final respRegex = RegExp(
        r'<[a-zA-Z]*:?response\b[^>]*>(.*?)</[a-zA-Z]*:?response\s*>',
        dotAll: true,
        caseSensitive: false);
    final hrefRegex =
        RegExp(r'<[a-zA-Z]*:?href[^>]*>([^<]+)</[a-zA-Z]*:?href\s*>',
            caseSensitive: false);
    final dirRegex = RegExp(r'<[a-zA-Z]*:?collection\b[^>]*\/?>',
        caseSensitive: false);
    final sizeRegex = RegExp(
        r'<[a-zA-Z]*:?getcontentlength[^>]*>([^<]*)</[a-zA-Z]*:?getcontentlength\s*>',
        caseSensitive: false);
    final modifiedRegex = RegExp(
        r'<[a-zA-Z]*:?getlastmodified[^>]*>([^<]*)</[a-zA-Z]*:?getlastmodified\s*>',
        caseSensitive: false);
    final displayRegex = RegExp(
        r'<[a-zA-Z]*:?displayname[^>]*>([^<]*)</[a-zA-Z]*:?displayname\s*>',
        caseSensitive: false);
    for (final m in respRegex.allMatches(body)) {
      final block = m.group(1)!;
      final hrefM = hrefRegex.firstMatch(block);
      if (hrefM == null) continue;
      String href = hrefM.group(1)!;
      try {
        href = Uri.decodeComponent(href);
      } catch (_) {
        // 非法百分号编码保持原样
      }
      // 去掉开头的主机路径，只保留相对当前目录的名字
      final parts = href.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) continue;
      final name = parts.last;
      if (name == currentDirName) continue; // 跳过自身目录
      final isDir = dirRegex.hasMatch(block);
      final size = int.tryParse(sizeRegex.firstMatch(block)?.group(1)?.trim() ?? '');
      final lastModified = _parseHttpDate(
          modifiedRegex.firstMatch(block)?.group(1) ?? '');
      final displayName = displayRegex.firstMatch(block)?.group(1)?.trim();
      entries.add(WebDavEntry(
        name,
        isDir,
        href,
        size: size,
        lastModified: lastModified,
        displayName: displayName,
      ));
    }
    return entries;
  }

  /// 从指定目录下载文件
  Future<List<int>?> downloadFile(String dir, String fileName) async {
    try {
      if (_baseUrl == null) return null;
      var d = dir.trim();
      if (d.isNotEmpty && !d.endsWith('/')) d = '$d/';
      if (d.startsWith('/')) d = d.substring(1);
      final url = '$_baseUrl$d$fileName';
      final response = await _requestWithRetry(
        url,
        method: 'GET',
        responseType: ResponseType.bytes,
      );
      return response.data as List<int>;
    } catch (e) {
      return null;
    }
  }

  /// 上传书籍文件到远程书库：
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
      final response = await _requestWithRetry('$_baseUrl$d$name',
          method: 'PUT', data: await file.readAsBytes());
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

 /// 单书进度文件名：
  /// `${name}_${author}` 先规范化文件名非法字符，再把 URL 保留字符百分号编码，
  /// 与 Kotlin `normalizeFileName()` + `UrlUtil.replaceReservedChar()` 同序。
  static String progressFileName(String name, String author) {
    final normalized =
        '${name}_$author'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    const reserved = <String, String>{
      '%': '%25',
      ' ': '%20',
      '"': '%22',
      '#': '%23',
      '&': '%26',
      '(': '%28',
      ')': '%29',
      '+': '%2B',
      ',': '%2C',
      '/': '%2F',
      ':': '%3A',
      ';': '%3B',
      '<': '%3C',
      '=': '%3D',
      '>': '%3E',
      '?': '%3F',
      '@': '%40',
      '\\': '%5C',
      '|': '%7C',
    };
    var out = normalized;
    // '%' 必须先替换，避免后续生成的百分号被二次编码
    reserved.forEach((k, v) => out = out.replaceAll(k, v));
    return '$out.json';
  }

  /// 上传单书进度到 `bookProgress/`（复用 uploadBackup 的 dir 参数）。
  /// [progress] 为进度字段（如 BookProgress.toMap() / book 的 durChapter* 字段），
  /// 会自动补上 name / author / time。
  Future<bool> uploadBookProgress(
    String name,
    String author,
    Map<String, dynamic> progress,
  ) async {
    final payload = <String, dynamic>{
      ...progress,
      'name': name,
      'author': author,
      'time': DateTime.now().millisecondsSinceEpoch,
    };
    return uploadBackup(
      progressFileName(name, author),
      utf8.encode(jsonEncode(payload)),
      dir: 'bookProgress',
    );
  }

  /// 下载单书进度（复用 downloadFile 读取 `bookProgress/` 目录）。
  Future<Map<String, dynamic>?> downloadBookProgress(
      String name, String author) async {
    final data =
        await downloadFile('bookProgress', progressFileName(name, author));
    if (data == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(data));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
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

/// 解析 WebDAV 的 getlastmodified：兼容 ISO 8601 与 HTTP-date（RFC 1123）。
DateTime? _parseHttpDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  try {
    return HttpDate.parse(s);
  } catch (_) {
    return null;
  }
}

/// WebDAV 目录条目
class WebDavEntry {
  final String name;
  final bool isDir;
  final String href;

  /// 可选元信息：由 PROPFIND 的 getcontentlength / getlastmodified / displayname 解析。
  final int? size;
  final DateTime? lastModified;
  final String? displayName;

  WebDavEntry(
    this.name,
    this.isDir,
    this.href, {
    this.size,
    this.lastModified,
    this.displayName,
  });
}
