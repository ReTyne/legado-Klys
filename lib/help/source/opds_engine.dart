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
        'User-Agent': userAgent ?? 'Mozilla/5.0 (Linux; Android 13) legado',
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
    return parseAtom(resp.data.toString());
  }

  /// 搜索 OPDS 目录：优先使用 OpenSearch 模板（feed 级 <link rel="search">），
  /// 兼容把搜索链接放在 entry 内的实现，最后回退到约定 /search?q=。
  Future<List<OpdsEntry>> search(String keyword, {String? searchUrl}) async {
    String? url = searchUrl;
    if (url == null) {
      try {
        final resp = await _dio.get(baseUrl,
            options: Options(headers: _headers, responseType: ResponseType.plain));
        url = parseSearchTemplate(resp.data.toString());
      } catch (_) {}
      if (url == null) {
        try {
          for (final entry in await fetchCatalog()) {
            url = entry.searchTemplate;
            if (url != null) break;
          }
        } catch (_) {}
      }
    }
    url ??= '$baseUrl/search?q={searchTerms}';
    final target = url.replaceAll('{searchTerms}', Uri.encodeComponent(keyword));
    final resp = await _dio.get(target,
        options: Options(headers: _headers, responseType: ResponseType.plain));
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      throw Exception('OPDS 搜索失败: ${resp.statusCode}');
    }
    return parseAtom(resp.data.toString());
  }

  /// 从 OPDS feed XML 提取 OpenSearch 模板（feed 级 <link rel="search" href="...{searchTerms}...">）。
  /// 公开便于离线测试；也修复了原先只遍历 entry.links 导致标准 OPDS 搜索模板找不到的缺陷。
  String? parseSearchTemplate(String xmlStr) {
    try {
      final doc = html_parser.parse(xmlStr);
      for (final l in doc.getElementsByTagName('link')) {
        if ((l.attributes['rel'] ?? '').contains('search')) {
          final href = l.attributes['href'] ?? '';
          if (href.isNotEmpty) return _resolveUrl(href);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 解析 Atom feed（使用 html 包的 XML 解析能力）。
  /// 公开给 UI 预览与离线单元测试复用，避免解析能力只能通过网络请求触达。
  List<OpdsEntry> parseAtom(String xmlStr) {
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

    // 链接（href 统一解析为绝对地址，与 cover/downloadUrl 一致，UI 可直接打开）
    final links = entry.getElementsByTagName('link').map((l) {
      final raw = l.attributes['href'] ?? '';
      return OpdsLink(
        href: raw.isEmpty ? '' : _resolveUrl(raw),
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
      // Uri.resolve 会把 {searchTerms} 等模板占位符转义成 %7B...，
      // 先用安全标记替换再还原，保证搜索模板仍可被 replaceAll 命中。
      const marker = '__LEGADO_SEARCH_TERM__';
      final safe = url.replaceAll('{searchTerms}', marker);
      return Uri.parse(baseUrl)
          .resolve(safe)
          .toString()
          .replaceAll(marker, '{searchTerms}');
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

  /// 下一级目录 feed 链接（OPDS 导航型条目：rel=subsection / type 含 kind=navigation）。
  /// 命中时 UI 应继续 fetchCatalog(path:) 下钻，而不是当作书籍条目下载。
  String? get navigationUrl {
    for (final l in links) {
      final rel = l.rel ?? '';
      final type = l.type ?? '';
      final isNav = rel.contains('subsection') ||
          rel == 'navigation' ||
          rel == 'start' ||
          type.contains('kind=navigation');
      if (isNav && l.href.isNotEmpty) return l.href;
    }
    return null;
  }

  /// 目录内声明的搜索模板（rel=search），供 UI 显示「可搜索」标记。
  String? get searchTemplate {
    for (final l in links) {
      if ((l.rel ?? '').contains('search') && l.href.isNotEmpty) return l.href;
    }
    return null;
  }
}

/// OPDS 链接
class OpdsLink {
  final String href;
  final String? rel;
  final String? type;
  final String? title;
  OpdsLink({required this.href, this.rel, this.type, this.title});
}
