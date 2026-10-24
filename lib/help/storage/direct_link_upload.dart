import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/js_mini_eval.dart';
import 'package:legado_md3/help/source/json_path.dart';

/// 直链上传规则（E: DirectLinkUpload.Rule）。
///
/// * [uploadUrl]：上传接口，支持 `url,{"method":"POST","body":{...},"type":"multipart/form-data"}`
///   形式（`,` 后为 JSON 选项，与 E 的 AnalyzeUrl 一致）；body 中值 `fileRequest`
///   为文件占位符，上传时替换为实际文件。
/// * [downloadUrlRule]：从上传响应提取下载地址的规则，如 `$.data@js:...`、`$.msg`。
/// * [compress]：上传前是否压缩为 zip。
/// * [expiryDate]：有效期（天，0 表示永久）。
class DirectLinkRule {
  const DirectLinkRule({
    required this.uploadUrl,
    required this.downloadUrlRule,
    required this.summary,
    this.compress = false,
    this.expiryDate = 0,
  });

  final String uploadUrl;
  final String downloadUrlRule;
  final String summary;
  final bool compress;
  final int expiryDate;

  Map<String, dynamic> toJson() => {
        'uploadUrl': uploadUrl,
        'downloadUrlRule': downloadUrlRule,
        'summary': summary,
        'compress': compress,
        'expiryDate': expiryDate,
      };

  static DirectLinkRule? fromJson(dynamic json) {
    if (json is! Map) return null;
    final uploadUrl = json['uploadUrl']?.toString() ?? '';
    final downloadUrlRule = json['downloadUrlRule']?.toString() ?? '';
    if (uploadUrl.isEmpty || downloadUrlRule.isEmpty) return null;
    return DirectLinkRule(
      uploadUrl: uploadUrl,
      downloadUrlRule: downloadUrlRule,
      summary: json['summary']?.toString() ?? '',
      compress: json['compress'] == true,
      expiryDate: (json['expiryDate'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => summary;
}

/// 直链上传服务（E: DirectLinkUpload）。
///
/// 把本地文件（书籍备份/导出、书源分享 JSON 等）上传到第三方网盘，
/// 按 [DirectLinkRule.downloadUrlRule] 从响应提取直链返回。
class DirectLinkUploadService {
  DirectLinkUploadService._();

  static const String ruleFileName = 'directLinkUploadRule.json';
  static const String _prefKey = 'directLinkUploadRule';

  /// 内置默认规则（E assets/defaultData/directLinkUpload.json）
  static final List<DirectLinkRule> defaultRules = [
    DirectLinkRule(
      uploadUrl:
          'https://sy.nyasama.net/shuyuan,{"method":"POST","body":{"file":"fileRequest"},"type":"multipart/form-data"}',
      downloadUrlRule:
          "\$.data@js:if (result == '') \n '' \n else \n 'https://shuyuan.nyasama.net/shuyuan/' + result",
      summary: '喵公子网盘①(有效期30天·香港G口)',
      compress: false,
      expiryDate: 30,
    ),
    DirectLinkRule(
      uploadUrl:
          'https://sy.mgz6.com/shuyuan,{"method":"POST","body":{"file":"fileRequest"},"type":"multipart/form-data"}',
      downloadUrlRule:
          "\$.data@js:if (result == '') \n '' \n else \n 'https://shuyuan.mgz6.com/shuyuan/' + result",
      summary: '喵公子网盘②(有效期7天)',
      compress: false,
      expiryDate: 7,
    ),
    DirectLinkRule(
      uploadUrl:
          'http://v2.jt12.eu/up-v2.php,{"method":"POST","body":{"file":"fileRequest"},"type":"multipart/form-data"}',
      downloadUrlRule: '\$.msg',
      summary: '橘涂书源网盘2.0 Beta(永久有效)',
      compress: false,
      expiryDate: 0,
    ),
  ];

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));

  // ============================ 规则持久化 ============================

  /// 当前生效规则：用户配置优先，否则取默认规则第一条（E: getRule）
  static Future<DirectLinkRule> getRule() async =>
      (await getConfig()) ?? defaultRules.first;

  static Future<DirectLinkRule?> getConfig() async {
    final p = await SharedPreferences.getInstance();
    final json = p.getString(_prefKey);
    if (json == null || json.trim().isEmpty) return null;
    try {
      return DirectLinkRule.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  static Future<void> putConfig(DirectLinkRule rule) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefKey, jsonEncode(rule.toJson()));
  }

  static Future<void> delConfig() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefKey);
  }

  // ============================ 上传 ============================

  /// 上传文件并返回下载直链。
  ///
  /// [file] 支持 [Uint8List]（字节）、[String]（文本）或 [Map]/[List]（JSON 序列化）。
  /// [contentType] 为文件 MIME（如 `text/plain`、`application/json`）。
  /// 失败抛异常（信息对齐 E：上传url未配置/下载地址规则未配置/上传失败,<响应>）。
  static Future<String> upLoad(
    String fileName,
    dynamic file,
    String contentType, {
    DirectLinkRule? rule,
  }) async {
    final r = rule ?? await getRule();
    if (r.uploadUrl.trim().isEmpty) throw '上传url未配置';
    if (r.downloadUrlRule.trim().isEmpty) throw '下载地址规则未配置';

    var mFileName = fileName;
    var mContentType = contentType;
    var bytes = _toBytes(file);

    // 压缩（E: ZipUtils，非 zip 内容才压）
    if (r.compress && contentType != 'application/zip') {
      mFileName = '$fileName.zip';
      mContentType = 'application/zip';
      bytes = _zipBytes(bytes, fileName);
    }

    // 解析 `url,{options}`
    final comma = r.uploadUrl.indexOf(',{');
    final url = (comma > 0 ? r.uploadUrl.substring(0, comma) : r.uploadUrl).trim();
    Map<String, dynamic> options = const {};
    if (comma > 0) {
      final raw = r.uploadUrl.substring(comma + 1).trim();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) options = decoded.map((k, v) => MapEntry('$k', v));
      }
    }
    final method = (options['method'] as String? ?? 'POST').toUpperCase();
    final bodyMap = options['body'] is Map
        ? (options['body'] as Map).map((k, v) => MapEntry('$k', v))
        : const <String, dynamic>{};

    // 组装 multipart：fileRequest 占位符替换为实际文件
    final formMap = <String, dynamic>{};
    bodyMap.forEach((k, v) {
      if (v.toString() == 'fileRequest') {
        formMap[k] = MultipartFile.fromBytes(
          bytes,
          filename: mFileName,
          contentType: DioMediaType.parse(mContentType),
        );
      } else {
        formMap[k] = (v is Map || v is List) ? jsonEncode(v) : v.toString();
      }
    });
    if (formMap.isEmpty) {
      // 无 body 配置时按 E 的 fileRequest 语义直接上传文件
      formMap['file'] = MultipartFile.fromBytes(
        bytes,
        filename: mFileName,
        contentType: DioMediaType.parse(mContentType),
      );
    }

    Response<String> resp;
    try {
      resp = await _dio.request<String>(
        url,
        data: FormData.fromMap(formMap),
        options: Options(
          method: method,
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
    } on DioException catch (e) {
      final body = e.response?.data?.toString() ?? '';
      throw '上传失败${body.isNotEmpty ? ',$body' : ''}';
    }

    final body = resp.data ?? '';
    dynamic root;
    try {
      root = body.trim().isEmpty ? '' : jsonDecode(body);
    } catch (_) {
      root = body;
    }
    final downloadUrl = await _extractDownloadUrl(root, r.downloadUrlRule);
    if (downloadUrl.trim().isEmpty) throw '上传失败,$body';
    return downloadUrl;
  }

  /// 按 downloadUrlRule 从上传响应提取下载地址：
  /// JsonPath 取值 →（可选）`@js:` 后处理（真引擎优先，迷你求值兜底）。
  static Future<String> _extractDownloadUrl(
      dynamic root, String downloadUrlRule) async {
    final rule = downloadUrlRule.trim();
    if (rule.isEmpty) return '';
    final jsIdx = rule.indexOf('@js:');
    final pathPart = (jsIdx >= 0 ? rule.substring(0, jsIdx) : rule).trim();
    final jsPart = jsIdx >= 0 ? rule.substring(jsIdx + 4).trim() : null;

    String value;
    if (pathPart.isEmpty) {
      value = root is String ? root : jsonEncode(root);
    } else {
      final v = JsonPath.selectFirst(root, pathPart);
      value = v == null ? '' : (v is Map || v is List ? jsonEncode(v) : v.toString());
    }

    if (jsPart != null && jsPart.isNotEmpty) {
      final jsResult = await _evalJs(jsPart, value);
      if (jsResult != null && jsResult.isNotEmpty) value = jsResult;
    }
    return value;
  }

  /// `@js:` 片段求值：先迷你求值器（覆盖 if/else、replace、concat 等高频写法），
  /// 失败回退无头 WebView 真引擎（仅移动端），再失败返回 null 由调用方用原值。
  static Future<String?> _evalJs(String script, String result) async {
    final mini = JsMiniEvaluator.eval(script, result: result);
    if (mini != null && mini.isNotEmpty) return mini;
    try {
      final rt = await JsRuntimeManager.instance
          .forSource(_DirectLinkJsSource.instance);
      final res = await rt.eval(JsEvalRequest(
        source: _DirectLinkJsSource.instance,
        script: script,
        result: result,
      ));
      final v = res.stringValue;
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return null;
  }

  // ============================ 工具 ============================

  static Uint8List _toBytes(dynamic file) {
    if (file is Uint8List) return file;
    if (file is List<int>) return Uint8List.fromList(file);
    if (file is String) return Uint8List.fromList(utf8.encode(file));
    return Uint8List.fromList(utf8.encode(jsonEncode(file)));
  }

  /// 把 data 打包为 zip（条目名为 [entryName]，对齐 E 的 ZipUtils.zipByteArray）
  static Uint8List _zipBytes(Uint8List data, String entryName) {
    final archive = Archive();
    archive.addFile(ArchiveFile(entryName, data.length, data));
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw StateError('zip 打包失败');
    return Uint8List.fromList(encoded);
  }
}

/// 直链上传的 JS 运行时载体（无头 WebView 需要 JsSource）。
class _DirectLinkJsSource implements JsSource {
  _DirectLinkJsSource._();
  static final _DirectLinkJsSource instance = _DirectLinkJsSource._();

  @override
  String get jsUrl => 'directLinkUpload://config';
  @override
  String get jsName => '直链上传';
  @override
  String get jsHttpUrl => '';
  @override
  String? variable;
  @override
  String? get variableComment => null;
  @override
  int? get lastUpdateTime => null;
  @override
  String? get jsLib => null;
  @override
  String? get loginUrl => null;
  @override
  String? get header => null;
  @override
  bool get enabledCookieJar => false;
  @override
  String get jsGroup => '';
  @override
  String get jsComment => '';
  @override
  int get jsType => 0;
  @override
  String get jsBookUrlPattern => '';
  @override
  int get jsConcurrentRate => 0;
  @override
  bool get jsEnabledExplore => false;
  @override
  String get jsExploreUrl => '';
  @override
  String get jsSearchUrl => '';
  @override
  String get jsTocUrl => '';
  @override
  String get jsRuleBookUrlPattern => '';
}
