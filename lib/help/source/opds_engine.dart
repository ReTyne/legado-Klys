import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// OPDS 书源引擎：解析 OPDS (Atom/XML) 目录，支持浏览和搜索
/// OPDS 规范：https://specs.opds.io/
class OpdsEngine {
  final String baseUrl;
  final String? userAgent;
  final Dio _dio = Dio();

  OpdsEngine({required this.baseUrl, this.userAgent});

  Map<String, String> get _headers => {
        'User-Agent': userAgent ?? 'Mozilla/5.0 (Linux; Android 13) LegadoMD3',
        'Accept': 'application/atom+xml,application/xml',
      };

  /// 获取 OPDS 根目录/导航
  Future<List<OpdsEntry>> fetchCatalog({String? path}) async {
    final url = path != null ? _resolveUrl(path) : baseUrl;
    final resp = await _dio.get(url,
        options: Options(headers: _headers, responseType: ResponseType.plain));
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw Exception('OPDS 请求失败: ${resp.statusCode}');
    }
    return _parseAtom(resp.data.toString());
  }

  /// 搜索 OPDS 目录
  Future<List<OpdsEntry>> search(String keyword, {String? searchUrl}) async {
    String? url = searchUrl;
    if (url == null) {
      try {
        final catalog = await fetchCatalog();
        for (final entry in catalog) {
          for (final l in entry.links) {
            if (l.rel?.contains('search') ?? false) {
              url = l.href.replaceAll('{searchTerms}', Uri.encodeComponent(keyword));
              break;
            }
          }
          if (url != null) break;
        }
      } catch (_) {}
    }
    if (url == null) {
      url = '$baseUrl/search?q=${Uri.encodeComponent(keyword)}';
    }
    final resp = await _dio.get(url,
        options: Options(headers: _headers, responseType: ResponseType.plain));
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw Exception('OPDS 搜索失败: ${resp.statusCode}');
    }
    return _parseAtom(resp.data.toString());
  }

  /// 解析 Atom feed（使用 html 包的 XML 解析能力）
  List<OpdsEntry> _parseAtom(String xmlStr) {
    try {
      final doc = html_parser.parse(xmlStr);
      final entries = doc.getElementsByTagName('entry');
      return entries.map((e) => _parseEntry(e)).toList();
    } catch (_) {
      return [];
    }
  }

  OpdsEntry _parseEntry(dom.Element entry) {
    final title = _getText(entry, 'title');
    final id = _getText(entry, 'id');
    final updated = _getText(entry, 'updated');
    final summary = _getText(entry, 'summary') ?? _getText(entry, 'content');

    // 作者
    final authors = entry.getElementsByTagName('author').map((a) {
      return _getText(a, 'name') ?? '';
    }).where((s) => s.isNotEmpty).toList();

    // 链接
    final links = entry.getElementsByTagName('link').map((l) {
      return OpdsLink(
        href: l.attributes['href'] ?? '',
        rel: l.attributes['rel'],
        type: l.attributes['type'],
        title: l.attributes['title'],
      );
    }).toList();

    // 分类/标签
    final categories = entry.getElementsByTagName('category').map((c) {
      return c.attributes['label'] ?? c.attributes['term'] ?? '';
    }).where((s) => s.isNotEmpty).toList();

    // 封面图
    String? cover;
    for (final l in links) {
      if (l.rel == 'http://opds-spec.org/image' ||
          l.rel == 'http://opds-spec.org/image/thumbnail' ||
          (l.type?.startsWith('image/') ?? false)) {
        cover = _resolveUrl(l.href);
        break;
      }
    }

    // 下载链接
    String? downloadUrl;
    for (final l in links) {
      if (l.type == 'application/epub+zip' ||
          l.type == 'application/pdf' ||
          l.type == 'application/x-mobipocket-ebook' ||
          l.rel == 'http://opds-spec.org/acquisition') {
        downloadUrl = _resolveUrl(l.href);
        break;
      }
    }

    return OpdsEntry(
      id: id,
      title: title ?? '',
      author: authors.isNotEmpty ? authors.join(', ') : null,
      summary: summary,
      updated: updated,
      cover: cover,
      downloadUrl: downloadUrl,
      links: links,
      categories: categories,
    );
  }

  String? _getText(dom.Element parent, String name) {
    final elems = parent.getElementsByTagName(name);
    if (elems.isEmpty) return null;
    return elems.first.text.trim();
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  /// 下载书籍
  Future<List<int>?> downloadBook(OpdsEntry entry) async {
    if (entry.downloadUrl == null) return null;
    try {
      final resp = await _dio.get(entry.downloadUrl!,
          options: Options(headers: _headers, responseType: ResponseType.bytes));
      if (resp.statusCode != null && resp.statusCode! >= 400) return null;
      return resp.data as List<int>;
    } catch (_) {
      return null;
    }
  }
}

/// OPDS 条目
class OpdsEntry {
  final String? id;
  final String title;
  final String? author;
  final String? summary;
  final String? updated;
  final String? cover;
  final String? downloadUrl;
  final List<OpdsLink> links;
  final List<String> categories;

  OpdsEntry({
    this.id,
    required this.title,
    this.author,
    this.summary,
    this.updated,
    this.cover,
    this.downloadUrl,
    this.links = const [],
    this.categories = const [],
  });
}

/// OPDS 链接
class OpdsLink {
  final String href;
  final String? rel;
  final String? type;
  final String? title;
  OpdsLink({required this.href, this.rel, this.type, this.title});
}
