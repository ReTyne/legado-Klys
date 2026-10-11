import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

/// 列表类规则智能推导结果（搜索 / 发现 / RSS 文章 / 目录）
class AutoListResult {
  /// 是否为 JSON 接口
  final bool isJson;

  /// 列表定位规则（bookList / ruleArticles / chapterList）
  final String listRule;

  /// 字段规则：字段名 -> 规则串
  final Map<String, String> fields;

  /// 第一条详情链接（绝对地址），供继续推导详情/目录/正文
  final String? sampleUrl;

  final List<String> notes;

  AutoListResult({
    required this.isJson,
    required this.listRule,
    required this.fields,
    this.sampleUrl,
    this.notes = const [],
  });

  bool get isEmpty => listRule.isEmpty;
}

/// 单页规则推导结果（详情 / 正文）
class AutoPageResult {
  final Map<String, String> fields;

  /// 推导出的下一跳绝对地址（详情页->目录页；正文页未用）
  final String? nextUrl;

  final List<String> notes;

  AutoPageResult({this.fields = const {}, this.nextUrl, this.notes = const []});
}

/// 规则智能推导（对齐 legado 的 autoComplete）：
/// 抓取页面后识别“重复结构块”，生成可被 [RulePipeline] 直接消费的 CSS / JSONPath 规则。
///
/// 全部为纯函数（不发网络请求），便于单测；网络编排由编辑页配合 BookSourceEngine 完成。
class RuleAutoCompleter {
  static final RegExp _ws = RegExp(r'\s+');
  static final RegExp _clsOk = RegExp(r'^[a-zA-Z一-龥][\w\-]{1,24}$');
  static final RegExp _hexish = RegExp(r'^[a-f0-9]{6,}$', caseSensitive: false);

  /// 通用工具类名（出现这些不代表有辨识度）
  static const _genericClasses = {
    'clearfix', 'container', 'wrapper', 'wrap', 'box', 'item', 'list',
    'fl', 'fr', 'clr', 'clear', 'active', 'current', 'on', 'off', 'more',
    'text', 'txt', 'inner', 'outer', 'main', 'bd', 'hd', 'ft', 'col',
  };

  static String _norm(String? s) => (s ?? '').replaceAll(_ws, ' ').trim();

  static List<String> _stableClasses(dom.Element e) {
    return e.classes
        .where((c) =>
            _clsOk.hasMatch(c) &&
            !_hexish.hasMatch(c) &&
            !RegExp(r'^\d+$').hasMatch(c))
        .toList();
  }

  static bool _stableId(String? id) =>
      id != null && _clsOk.hasMatch(id) && !_hexish.hasMatch(id);

  /// 元素自身的最短 CSS 片段：tag#id 或 tag.cls（单个最具辨识度的类）
  static String? _ownPart(dom.Element e, {List<String>? preferClasses}) {
    final tag = e.localName?.toLowerCase() ?? '';
    if (tag.isEmpty) return null;
    if (_stableId(e.id)) return '$tag#${e.id}';
    final cls = preferClasses ?? _stableClasses(e);
    final scored = cls.isNotEmpty ? _pickClass(cls) : null;
    return scored == null ? tag : '$tag.$scored';
  }

  static String? _pickClass(List<String> classes) {
    if (classes.isEmpty) return null;
    final sorted = [...classes]..sort((a, b) {
        int score(String c) {
          var s = c.length;
          if (!_genericClasses.contains(c.toLowerCase())) s += 8;
          if (RegExp(r'[a-z]', ).hasMatch(c) && RegExp(r'\d').hasMatch(c)) s -= 2;
          return s;
        }
        return score(b).compareTo(score(a));
      });
    return sorted.first;
  }

  static bool _realHref(String? h) {
    if (h == null) return false;
    final t = h.trim();
    if (t.isEmpty || t == '#') return false;
    final low = t.toLowerCase();
    if (low.startsWith('javascript:') ||
        low.startsWith('mailto:') ||
        low.startsWith('tel:') ||
        low.startsWith('data:') ||
        low.startsWith('void')) {
      return false;
    }
    return true;
  }

  static String? _firstHref(dom.Element e) {
    for (final a in e.querySelectorAll('a')) {
      final h = a.attributes['href'];
      if (_realHref(h)) return h!.trim();
    }
    return null;
  }

  static String _resolve(String url, String base) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (base.isEmpty) return url;
    try {
      return Uri.parse(base).resolve(url).toString();
    } catch (_) {
      if (url.startsWith('/')) {
        final u = Uri.parse(base);
        return '${u.scheme}://${u.host}$url';
      }
      return url;
    }
  }

  static int _depth(dom.Element e) {
    var d = 0;
    dom.Node? p = e.parent;
    while (p != null) {
      d++;
      p = p.parent;
    }
    return d;
  }

  // ============================ 列表（搜索/发现/RSS） ============================

  /// 推导书籍/文章列表规则。
  /// 字段集 [fieldKeys] 决定要推导哪些叶子字段（书源用书源字段，RSS 用 RSS 字段）。
  static AutoListResult inferList(
    String raw, {
    String baseUrl = '',
    List<String> fieldKeys = const [
      'name', 'author', 'intro', 'kind', 'lastChapter', 'wordCount',
      'coverUrl', 'bookUrl',
    ],
  }) {
    final t = raw.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) {
      final j = _inferJsonList(raw, baseUrl, fieldKeys);
      if (j != null) return j;
    }
    return _inferHtmlList(raw, baseUrl, fieldKeys, chapterMode: false);
  }

  /// 推导目录（章节列表）规则
  static AutoListResult inferChapterList(String raw, {String baseUrl = ''}) {
    final t = raw.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) {
      final j = _inferJsonList(raw, baseUrl, const ['chapterName', 'chapterUrl']);
      if (j != null) return j;
    }
    return _inferHtmlList(raw, baseUrl, const ['chapterName', 'chapterUrl'],
        chapterMode: true);
  }

  static AutoListResult _inferHtmlList(
    String raw,
    String baseUrl,
    List<String> fieldKeys, {
    required bool chapterMode,
  }) {
    final doc = html_parser.parse(raw);
    final body = doc.body;
    if (body == null) {
      return AutoListResult(isJson: false, listRule: '', fields: const {});
    }

    final block = chapterMode
        ? _findChapterBlock(body)
        : _findCardBlock(body);
    if (block == null) {
      return AutoListResult(isJson: false, listRule: '', fields: const {});
    }

    final items = block.items;
    final listSelector = _buildListSelector(block.container, items);
    final fields = chapterMode
        ? _chapterFields(items)
        : _cardFields(items, fieldKeys);

    String? sample;
    if (chapterMode) {
      sample = _firstHref(items.first);
      if (sample != null) sample = _resolve(sample, baseUrl);
    } else {
      final bu = fields['bookUrl'];
      if (bu != null) {
        final rel = _cssOf(bu);
        final getter = _getterOf(bu);
        final el = items.first.querySelectorAll(rel).firstOrNull;
        if (el != null) {
          sample = _resolve(_extract(el, getter) ?? '', baseUrl);
        }
      }
      sample ??= (_firstHref(items.first) == null
          ? null
          : _resolve(_firstHref(items.first)!, baseUrl));
    }

    if (chapterMode) {
      final next = _findLinkByText(doc.body!, RegExp(r'^(下一页|下页|»|next|more)$', caseSensitive: false));
      if (next != null) {
        final sel = _docSelector(next);
        final href = next.attributes['href'];
        if (sel != null && href != null && _realHref(href)) {
          fields['nextTocUrl'] = '@css:$sel@href';
        }
      }
    }

    return AutoListResult(
      isJson: false,
      listRule: '@css:$listSelector',
      fields: fields,
      sampleUrl: sample,
      notes: ['识别到 ${items.length} 个重复列表项'],
    );
  }

  // ---------- 重复块识别（书籍/文章卡片） ----------

  static _Block? _findCardBlock(dom.Element body) {
    _Block? best;
    double bestScore = -1;

    void scan(dom.Element container) {
      final byTag = <String, List<dom.Element>>{};
      for (final c in container.children) {
        final tag = c.localName?.toLowerCase() ?? '';
        if (tag.isEmpty) continue;
        byTag.putIfAbsent(tag, () => []).add(c);
      }
      for (final entry in byTag.entries) {
        final items = entry.value;
        if (items.length < 3) continue;
        final score = _cardBlockScore(items);
        if (score > bestScore) {
          bestScore = score;
          best = _Block(container, entry.key, items.where(_isCardLike).toList());
        }
      }
      for (final c in container.children) {
        scan(c);
      }
    }

    scan(body);
    return best;
  }

  static double _cardBlockScore(List<dom.Element> items) {
    final hrefs = <String>{};
    var valid = 0;
    var withImg = 0;
    var lenSum = 0;
    for (final it in items) {
      final text = _norm(it.text);
      final href = _firstHref(it);
      if (href != null) hrefs.add(href);
      if (_isCardLike(it)) {
        valid++;
        if (it.querySelector('img') != null) withImg++;
        lenSum += text.length;
      }
    }
    if (valid < 3) return -1;
    if (hrefs.length < 3) return -1;
    if (hrefs.length / items.length < 0.6) return -1;
    final median = lenSum / items.length;
    if (median > 1200) return -1; // 命中了过大的容器
    var score = valid * 10.0;
    score += (withImg / items.length) * 12;
    score += hrefs.length * 1.5;
    if (median >= 6 && median <= 240) score += 8;
    // 叶子偏好：条目内部不再含 3 个以上同构卡片
    final inner = _findCardBlock(items.first);
    if (inner != null && inner.items.length >= 3) score -= 25;
    score += _depth(items.first) * 0.05; // 同分取更深
    return score;
  }

  static bool _isCardLike(dom.Element it) {
    final text = _norm(it.text);
    if (text.length < 2 || text.length > 900) return false;
    final hasLink = _firstHref(it) != null;
    final hasImg = it.querySelector('img') != null;
    return hasLink || (hasImg && text.length >= 2);
  }

  // ---------- 重复块识别（章节目录） ----------

  static _Block? _findChapterBlock(dom.Element body) {
    _Block? best;
    double bestScore = -1;

    void scan(dom.Element container) {
      // 情况一：直接子元素就是一组 <a>
      final directAnchors =
          container.children.where((c) => c.localName?.toLowerCase() == 'a').toList();
      if (directAnchors.length >= 5) {
        final s = _chapterBlockScore(directAnchors, anchorIsItem: true);
        if (s > bestScore) {
          bestScore = s;
          best = _Block(container, 'a', directAnchors);
        }
      }
      // 情况二：直接子元素 dd/li/div/tr 内各含链接
      final byTag = <String, List<dom.Element>>{};
      for (final c in container.children) {
        final tag = c.localName?.toLowerCase() ?? '';
        byTag.putIfAbsent(tag, () => []).add(c);
      }
      for (final items in byTag.values) {
        if (items.length < 5) continue;
        final s = _chapterBlockScore(items, anchorIsItem: false);
        if (s > bestScore) {
          bestScore = s;
          best = _Block(container, items.first.localName!.toLowerCase(), items);
        }
      }
      for (final c in container.children) {
        scan(c);
      }
    }

    scan(body);
    return best;
  }

  static double _chapterBlockScore(List<dom.Element> items,
      {required bool anchorIsItem}) {
    final hrefs = <String>{};
    var titled = 0;
    var contentish = 0;
    for (final it in items) {
      final a = anchorIsItem ? it : it.querySelector('a');
      final href = anchorIsItem ? it.attributes['href'] : a?.attributes['href'];
      final text = _norm(anchorIsItem ? it.text : (a?.text ?? it.text));
      if (!_realHref(href)) continue;
      hrefs.add(href!.trim());
      if (text.isNotEmpty && text.length <= 40) titled++;
      final low = href.toLowerCase();
      if (RegExp(r'\d|chapter|read|content|\.s?html?|/b/|_\d+').hasMatch(low)) {
        contentish++;
      }
    }
    if (hrefs.length < 5) return -1;
    if (hrefs.length / items.length < 0.75) return -1;
    var score = hrefs.length * 10.0 + titled * 1.2 + contentish * 1.5;
    // 目录通常在列表/菜单容器里，更深者优先；排除导航（首页/上一页/下一页）
    if (hrefs.length > 80) score -= 15; // 可能是整站地图
    score += _depth(items.first) * 0.05;
    return score;
  }

  // ---------- 列表选择器构造 ----------

  static String _buildListSelector(dom.Element container, List<dom.Element> items) {
    final tag = items.first.localName!.toLowerCase();
    // 所有条目共有的稳定类，保证选择器能命中全部条目
    final shared = _sharedClasses(items);
    final sharedCls = shared.isEmpty ? null : _pickClass(shared);
    final itemCss = tag + (sharedCls != null ? '.$sharedCls' : '');

    // 向上找最多 2 层有辨识度的祖先（id 优先）
    final ctx = <String>[];
    dom.Element? p = container;
    var hops = 0;
    while (p != null && hops < 3) {
      final part = _ownPart(p);
      final tagP = p.localName?.toLowerCase() ?? '';
      final hasId = _stableId(p.id);
      final hasCls = _stableClasses(p).isNotEmpty;
      if (hasId || hasCls) {
        if (part != null && part != tagP) {
          ctx.add(part);
          if (hasId) break;
        }
      }
      p = p.parent;
      hops++;
      if (ctx.length >= (sharedCls != null ? 1 : 2)) break;
    }
    final chain = [...ctx.reversed, itemCss];
    return chain.join(' ');
  }

  static List<String> _sharedClasses(List<dom.Element> items) {
    Set<String>? acc;
    for (final it in items) {
      final s = _stableClasses(it).toSet();
      acc = acc == null ? s : acc.intersection(s);
      if (acc.isEmpty) break;
    }
    return (acc ?? <String>{}).toList();
  }

  /// 在条目内为目标元素生成相对 CSS（最多向上借 2 层带类/id 的祖先）
  static String? _relativeSelector(dom.Element item, dom.Element target) {
    final own = _ownPart(target);
    if (own == null) return null;
    final tag = target.localName!.toLowerCase();
    final hasDiscriminator = _stableId(target.id) ||
        _stableClasses(target).isNotEmpty;
    // 裸标签在条目内唯一时可直接用
    final sameTag = item.querySelectorAll(tag).length;
    if (hasDiscriminator) return own;
    if (sameTag == 1) return tag;
    // 向上借祖先
    dom.Element? p = target.parent;
    var hops = 0;
    while (p != null && hops < 3 && p != item.parent) {
      if (_stableId(p.id) || _stableClasses(p).isNotEmpty) {
        final pp = _ownPart(p);
        if (pp != null) {
          // 祖先 + 到目标的标签路径
          final down = <String>[];
          dom.Node? cur = target;
          while (cur != null && cur != p && cur is dom.Element) {
            final ce = cur;
            if (identical(ce, target)) {
              down.add(tag);
            } else {
              down.add(ce.localName!.toLowerCase());
            }
            cur = ce.parent;
          }
          final tail = down.reversed.join(' ');
          final sel = tail.startsWith(pp) ? tail : '$pp $tail';
          return sel;
        }
      }
      if (identical(p, item)) break;
      p = p.parent;
      hops++;
    }
    return tag; // 兜底
  }

  // ---------- 取值 ----------

  static String? _extract(dom.Element el, String getter) {
    switch (getter) {
      case 'text':
      case 'textContent':
        final t = _norm(el.text);
        return t.isEmpty ? null : t;
      case 'ownText':
        final t = _norm(el.nodes
            .where((n) => n.nodeType == dom.Node.TEXT_NODE)
            .map((n) => n.text ?? '')
            .join(' '));
        return t.isEmpty ? null : t;
      case 'html':
      case 'innerHTML':
        final c = el.clone(true);
        c.querySelectorAll('script,style').forEach((e) => e.remove());
        final t = c.innerHtml.trim();
        return t.isEmpty ? null : t;
      default:
        String? attr = getter;
        if (getter.startsWith('attr:')) attr = getter.substring(5);
        final v = el.attributes[attr];
        if (v != null && v.trim().isNotEmpty) return v.trim();
        final t = _norm(el.text);
        return t.isEmpty ? null : t;
    }
  }

  static String _cssOf(String rule) {
    var r = rule;
    if (r.toLowerCase().startsWith('@css:')) r = r.substring(5);
    final at = r.lastIndexOf('@');
    return at < 0 ? r : r.substring(0, at);
  }

  static String _getterOf(String rule) {
    final r = rule.toLowerCase().startsWith('@css:') ? rule.substring(5) : rule;
    final at = r.lastIndexOf('@');
    return at < 0 ? 'text' : r.substring(at + 1);
  }

  // ---------- 卡片字段推导 ----------

  static const _coverAttrs = [
    'data-original', 'data-src', 'data-lazy-src', 'lazy-src',
    'data-echo', 'data-img', 'src',
  ];

  static Map<String, String> _cardFields(List<dom.Element> items, List<String> keys) {
    final result = <String, String>{};
    final item = items.first;
    final n = items.length;

    // 先定位主链接与标题（二者通常同源）
    final anchors = item.querySelectorAll('a').where((a) => _realHref(a.attributes['href'])).toList();

    dom.Element? nameEl;
    String? nameRule;
    if (keys.contains('name')) {
      final cand = _bestElement(item, const ['h1', 'h2', 'h3', 'h4', 'a'],
          _nameKeywords, _nameNegative, (e) {
        final txt = _norm(e.text);
        if (txt.length < 2 || txt.length > 60) return false;
        if (RegExp(r'^(作者|作者：|简介|字数|分类|最新章节|更新时间)').hasMatch(txt)) return false;
        return true;
      });
      if (cand != null) {
        final rel = _relativeSelector(item, cand);
        if (rel != null && _support(items, rel, 'text') >= _need(n)) {
          nameEl = cand;
          nameRule = '@css:$rel@text';
        }
      }
      if (nameRule != null) result['name'] = nameRule;
    }

    if (keys.contains('bookUrl')) {
      dom.Element? best;
      int bestScore = -999;
      for (final a in anchors) {
        var s = 0;
        final href = a.attributes['href']!.toLowerCase();
        if (RegExp(r'book|novel|info|detail|read|/b/|/\d+|_\d+\.s?html?|\.s?html?|id=\d+').hasMatch(href)) s += 4;
        if (a.querySelector('img') != null) s += 2;
        if (nameEl != null && _norm(a.text) == _norm(nameEl.text)) s += 5;
        if (RegExp(r'page|next|prev|last|more|login|javascript').hasMatch(href)) s -= 6;
        if (s > bestScore) { bestScore = s; best = a; }
      }
      best ??= anchors.isNotEmpty ? anchors.first : null;
      if (best != null) {
        final rel = _relativeSelector(item, best);
        if (rel != null) result['bookUrl'] = '@css:$rel@href';
      }
    }

    if (keys.contains('coverUrl')) {
      final imgs = item.querySelectorAll('img');
      dom.Element? best;
      String? attr;
      int bestScore = -999;
      for (final im in imgs) {
        String? useAttr;
        for (final a in _coverAttrs) {
          final v = im.attributes[a];
          if (v != null && v.trim().isNotEmpty && !v.trim().startsWith('data:image')) { useAttr = a; break; }
        }
        if (useAttr == null) continue;
        var s = 0;
        final hay = '${im.className} ${im.id}'.toLowerCase();
        if (RegExp(r'cover|pic|img|thumb|photo|poster|fengmian').hasMatch(hay)) s += 4;
        if (RegExp(r'logo|icon|avatar|qrcode|ewm|ad-?').hasMatch(hay)) s -= 6;
        if (useAttr != 'src') s += 1; // 懒加载更可能是真实封面
        if (s > bestScore) { bestScore = s; best = im; attr = useAttr; }
      }
      if (best != null && attr != null) {
        final rel = _relativeSelector(item, best);
        if (rel != null && _supportAttr(items, rel, attr) >= _need(n)) {
          result['coverUrl'] = '@css:$rel@$attr';
        }
      }
    }

    String? simpleText(List<String> kws, List<String> neg, bool Function(String) shape,
        {List<String>? tags, String? labelPrefix, String? stripRegex}) {
      final cand = _bestElement(item, tags ?? const ['*'], kws, neg, (e) => shape(_norm(e.text)));
      if (cand == null) return null;
      final rel = _relativeSelector(item, cand);
      if (rel == null || _support(items, rel, 'text') < _need(n)) return null;
      final rule = '@css:$rel@text';
      return stripRegex == null ? rule : '$rule##$stripRegex##';
    }

    if (keys.contains('author')) {
      final r = simpleText(
        const ['author', 'writer', 'zuozhe', 'au_', '_au', 'artist'],
        const ['intro', 'desc', 'chapter', 'update', 'title', 'name'],
        (t) => t.isNotEmpty && t.length <= 30,
        labelPrefix: '作者',
      ) ?? _labelField(item, items, '作者', n);
      if (r != null) result['author'] = _stripLabel(items, r, '作者');
    }
    if (keys.contains('kind')) {
      final r = simpleText(
        const ['cate', 'kind', 'type', 'tag', 'label', 'fenlei', 'class'],
        const ['author', 'intro', 'chapter', 'update', 'word'],
        (t) => t.isNotEmpty && t.length <= 16,
        labelPrefix: '分类',
      ) ?? _labelField(item, items, '分类', n);
      if (r != null) result['kind'] = _stripLabel(items, r, '分类');
    }
    if (keys.contains('lastChapter')) {
      final r = simpleText(
        const ['chapter', 'last', 'new', 'update', 'jie', 'latest'],
        const ['author', 'intro', 'word', 'cate'],
        (t) => t.isNotEmpty && t.length <= 40,
      );
      if (r != null) {
        result['lastChapter'] = r;
      } else {
        // 含“章/节”的链接
        final a = anchors.where((a) {
          final t = _norm(a.text);
          return RegExp(r'[章节回卷]').hasMatch(t) && t.length <= 40 &&
              (nameEl == null || _norm(a.text) != _norm(nameEl.text));
        }).firstOrNull;
        if (a != null) {
          final rel = _relativeSelector(item, a);
          if (rel != null) result['lastChapter'] = '@css:$rel@text';
        }
      }
    }
    if (keys.contains('wordCount')) {
      final r = simpleText(
        const ['word', 'wordcount', 'zishu', 'count'],
        const ['chapter', 'intro'],
        (t) => RegExp(r'[\d.]+\s*万?\s*字').hasMatch(t) && t.length <= 30,
      );
      if (r != null) result['wordCount'] = r;
    }
    if (keys.contains('intro')) {
      final r = simpleText(
        const ['intro', 'desc', 'summary', 'abstract', 'brief', 'jianjie', 'content_s'],
        const ['title', 'name', 'author', 'chapter', 'cate'],
        (t) => t.length >= 12 && t.length <= 400,
      );
      if (r != null) {
        result['intro'] = r;
      } else {
        // 兜底：最长的说明性文本块
        dom.Element? longest;
        var maxLen = 0;
        for (final e in item.querySelectorAll('p, div, span')) {
          final t = _norm(e.text);
          if (t.length >= 20 && t.length <= 300 && t.length > maxLen) {
            // 排除包含标题整段的大容器（子元素过多）
            if (e.querySelectorAll('a').length > 3) continue;
            maxLen = t.length;
            longest = e;
          }
        }
        if (longest != null) {
          final rel = _relativeSelector(item, longest);
          if (rel != null && _support(items, rel, 'text') >= _need(n)) {
            result['intro'] = '@css:$rel@text';
          }
        }
      }
    }
    return result;
  }

  static const _nameKeywords = ['title', 'name', 'bookname', 'book-name', 'tit', 'ming'];
  static const _nameNegative = ['author', 'intro', 'desc', 'chapter', 'update', 'time', 'date', 'cate', 'word'];

  /// 在 scope 内按 class/id 关键字 + 文本约束挑选最可能的元素
  static dom.Element? _bestElement(
    dom.Element scope,
    List<String> tags,
    List<String> keywords,
    List<String> negative,
    bool Function(dom.Element) textOk,
  ) {
    dom.Element? best;
    int bestScore = -999;
    final candidates = tags.contains('*')
        ? scope.querySelectorAll('*')
        : scope.querySelectorAll(tags.join(','));
    for (final e in candidates) {
      final hay = '${e.className} ${e.id}'.toLowerCase();
      if (negative.any(hay.contains)) continue;
      if (!textOk(e)) continue;
      var score = 0;
      final tag = e.localName?.toLowerCase() ?? '';
      if (['h1', 'h2', 'h3', 'h4'].contains(tag)) score += 3;
      for (final k in keywords) {
        if (hay.contains(k)) { score += 5; break; }
      }
      // 越靠近叶子越好（文本占比高）
      final own = _norm(e.nodes
          .where((n) => n.nodeType == dom.Node.TEXT_NODE)
          .map((n) => n.text ?? '')
          .join(' '));
      if (own.isNotEmpty) score += 1;
      if (score > bestScore) { bestScore = score; best = e; }
    }
    return bestScore > 0 ? best : null;
  }

  /// 形如 “作者：某某” 的标签字段
  static String? _labelField(dom.Element item, List<dom.Element> items, String label, int n) {
    for (final e in item.querySelectorAll('*')) {
      final t = _norm(e.text);
      if (t.startsWith(label) && t.length > label.length && t.length <= 40) {
        final rel = _relativeSelector(item, e);
        if (rel != null && _support(items, rel, 'text') >= _need(n)) {
          return '@css:$rel@text##$label\\s*[:：]?\\s*##';
        }
      }
    }
    return null;
  }

  /// 若规则在首条样本上取到的值带“作者：/分类：”前缀，则追加去除前缀的正则后处理
  static String _stripLabel(List<dom.Element> items, String rule, String label) {
    try {
      final rel = _cssOf(rule);
      final getter = _getterOf(rule);
      final el = items.first.querySelectorAll(rel).firstOrNull;
      final val = el == null ? '' : (_extract(el, getter) ?? '');
      if (val.startsWith(label) && val.length > label.length) {
        return '$rule##$label\\s*[:：]?\\s*##';
      }
    } catch (_) {}
    return rule;
  }

  static int _need(int n) => n >= 3 ? 2 : 1;

  static int _support(List<dom.Element> items, String rel, String getter) {
    var c = 0;
    for (final it in items) {
      final el = it.querySelectorAll(rel).firstOrNull;
      if (el != null && _extract(el, getter) != null) c++;
    }
    return c;
  }

  static int _supportAttr(List<dom.Element> items, String rel, String attr) {
    var c = 0;
    for (final it in items) {
      final el = it.querySelectorAll(rel).firstOrNull;
      final v = el?.attributes[attr];
      if (v != null && v.trim().isNotEmpty) c++;
    }
    return c;
  }

  // ---------- 目录字段 ----------

  static Map<String, String> _chapterFields(List<dom.Element> items) {
    final first = items.first;
    final isAnchor = first.localName?.toLowerCase() == 'a';
    final hasInnerAnchor = !isAnchor && first.querySelector('a') != null;
    final fields = <String, String>{};
    if (isAnchor) {
      fields['chapterName'] = '@css:a@text';
      fields['chapterUrl'] = '@css:a@href';
    } else if (hasInnerAnchor) {
      // 定位条目内的链接
      final a = first.querySelector('a')!;
      final rel = _relativeSelector(first, a) ?? 'a';
      fields['chapterName'] = '@css:$rel@text';
      fields['chapterUrl'] = '@css:$rel@href';
    } else {
      fields['chapterName'] = '@text';
    }
    return fields;
  }

  // ============================ 详情页 ============================

  static AutoPageResult inferBookInfo(String raw, {String baseUrl = ''}) {
    final doc = html_parser.parse(raw);
    final body = doc.body;
    final fields = <String, String>{};
    String? tocAbs;

    if (body == null) return AutoPageResult(fields: fields);

    // 书名：h1 优先
    final h1 = body.querySelectorAll('h1').where((e) {
      final t = _norm(e.text);
      return t.length >= 2 && t.length <= 80;
    }).firstOrNull;
    if (h1 != null) {
      final sel = _docSelector(h1);
      if (sel != null) fields['name'] = '@css:$sel@text';
    } else {
      final el = _bestElement(body, const ['*'], _nameKeywords,
          const ['nav', 'menu', 'foot'], (e) {
        final t = _norm(e.text);
        return t.length >= 2 && t.length <= 60;
      });
      if (el != null) {
        final sel = _docSelector(el);
        if (sel != null) fields['name'] = '@css:$sel@text';
      }
    }

    String? docField(List<String> kws, List<String> neg, bool Function(String) shape,
        {List<String> tags = const ['*'], String? getter}) {
      final el = _bestElement(body, tags, kws, neg, (e) => shape(_norm(e.text)));
      if (el == null) return null;
      final sel = _docSelector(el);
      return sel == null ? null : '@css:$sel@${getter ?? 'text'}';
    }

    final author = docField(
        const ['author', 'writer', 'zuozhe', 'info'],
        const ['nav', 'menu', 'foot', 'list'], (t) => t.isNotEmpty && t.length <= 40);
    if (author != null) fields['author'] = author;

    final cover = _docCover(body);
    if (cover != null) fields['coverUrl'] = cover;

    final intro = docField(
        const ['intro', 'summary', 'desc', 'jianjie', 'abstract', 'book-intro'],
        const ['nav', 'menu', 'foot'], (t) => t.length >= 10 && t.length <= 2000,
        getter: 'html');
    if (intro != null) fields['intro'] = intro;

    final kind = docField(
        const ['cate', 'kind', 'tag', 'fenlei', 'label'],
        const ['author', 'intro'], (t) => t.isNotEmpty && t.length <= 30);
    if (kind != null) fields['kind'] = kind;

    final last = docField(
        const ['last', 'newchapter', 'latest', 'updatechapter', 'juan'],
        const ['author', 'intro', 'cate'], (t) => t.isNotEmpty && t.length <= 60);
    if (last != null) fields['lastChapter'] = last;

    // 目录链接
    var toc = _findLinkByText(body,
        RegExp(r'^(目录|章节|阅读目录|开始阅读|立即阅读|在线阅读|全文阅读|进入阅读|开始阅读全文)$'));
    toc ??= _findLinkByHref(body,
        RegExp(r'catalog|chapter|read|list|mulu|dir', caseSensitive: false));
    if (toc != null) {
      final sel = _docSelector(toc);
      final href = toc.attributes['href'];
      if (sel != null && href != null) {
        fields['tocUrl'] = '@css:$sel@href';
        tocAbs = _resolve(href, baseUrl);
      }
    }

    return AutoPageResult(fields: fields, nextUrl: tocAbs, notes: const []);
  }

  static String? _docCover(dom.Element body) {
    dom.Element? best;
    String? attr;
    int bestScore = -999;
    for (final im in body.querySelectorAll('img')) {
      String? useAttr;
      for (final a in _coverAttrs) {
        final v = im.attributes[a];
        if (v != null && v.trim().isNotEmpty && !v.trim().startsWith('data:image')) { useAttr = a; break; }
      }
      if (useAttr == null) continue;
      final hay = '${im.className} ${im.id} ${im.parent?.className ?? ''} ${im.parent?.id ?? ''}'.toLowerCase();
      var s = 0;
      if (RegExp(r'cover|fmimg|fengmian|pic|poster|thumb').hasMatch(hay)) s += 6;
      if (RegExp(r'logo|icon|avatar|qrcode|ewm|ad').hasMatch(hay)) s -= 8;
      if (s > bestScore) { bestScore = s; best = im; attr = useAttr; }
    }
    if (best != null && attr != null && bestScore > 0) {
      final sel = _docSelector(best);
      if (sel != null) return '@css:$sel@$attr';
    }
    return null;
  }

  /// 文档级选择器：向上最多 3 层取 id/类 形成上下文
  static String? _docSelector(dom.Element target) {
    final own = _ownPart(target);
    if (own == null) return null;
    if (_stableId(target.id) || _stableClasses(target).isNotEmpty) {
      // id 全局唯一，直接返回；类名借一层祖先更稳
      if (_stableId(target.id)) return own;
      final p = target.parent;
      if (p != null && (_stableId(p.id) || _stableClasses(p).isNotEmpty)) {
        final pp = _ownPart(p);
        if (pp != null && pp != (p.localName ?? '')) return '$pp $own';
      }
      return own;
    }
    // 目标无辨识度，向上借祖先
    dom.Element? p = target.parent;
    var hops = 0;
    while (p != null && hops < 4) {
      if (_stableId(p.id) || _stableClasses(p).isNotEmpty) {
        final pp = _ownPart(p);
        if (pp != null) {
          final down = <String>[];
          dom.Node? cur = target;
          while (cur != null && cur != p && cur is dom.Element) {
            down.add(cur.localName!.toLowerCase());
            cur = cur.parent;
          }
          final tail = down.reversed.join(' ');
          return '$pp $tail';
        }
      }
      p = p.parent;
      hops++;
    }
    return own;
  }

  static dom.Element? _findLinkByText(dom.Element body, RegExp textRe) {
    for (final a in body.querySelectorAll('a')) {
      if (!_realHref(a.attributes['href'])) continue;
      if (textRe.hasMatch(_norm(a.text))) return a;
    }
    return null;
  }

  static dom.Element? _findLinkByHref(dom.Element body, RegExp hrefRe) {
    for (final a in body.querySelectorAll('a')) {
      final h = a.attributes['href'];
      if (_realHref(h) && hrefRe.hasMatch(h!)) return a;
    }
    return null;
  }

  // ============================ 正文页 ============================

  static AutoPageResult inferContent(String raw, {String baseUrl = ''}) {
    final doc = html_parser.parse(raw);
    final body = doc.body;
    final fields = <String, String>{};
    if (body == null) return AutoPageResult(fields: fields);

    dom.Element? best;
    int bestScore = -1;
    for (final e in body.querySelectorAll('div,article,td,section')) {
      final hay = '${e.className} ${e.id}'.toLowerCase();
      if (RegExp(r'nav|menu|head|foot|comment|list|catalog|sidebar|copyright|login').hasMatch(hay)) {
        continue;
      }
      final hinted = RegExp(r'content|chapter|booktxt|read|txt|article|entry|text|bookcontent|htmlcontent')
          .hasMatch(hay);
      final text = _norm(e.text);
      if (text.length < (hinted ? 60 : 200)) continue;
      var score = text.length;
      if (hinted) score += 20000;
      final pCount = e.querySelectorAll('p').length;
      score += pCount * 200;
      // 父容器命中时子段落也会命中，偏好直接包裹段落的容器
      if (e.children.length > 0) {
        final pRatio = pCount / e.children.length;
        score += (pRatio * 3000).round();
      }
      if (score > bestScore) { bestScore = score; best = e; }
    }

    if (best != null) {
      final sel = _docSelector(best);
      if (sel != null) fields['content'] = '@css:$sel@html';
      final h1 = best.querySelector('h1') ??
          body.querySelectorAll('h1').where((e) => _norm(e.text).length <= 60).firstOrNull;
      if (h1 != null) {
        final ts = _docSelector(h1);
        if (ts != null) fields['title'] = '@css:$ts@text';
      }
    }

    final next = _findLinkByText(body, RegExp(r'^(下一页|下页|下一页»|»|next|Next)$', caseSensitive: false));
    if (next != null) {
      final sel = _docSelector(next);
      final href = next.attributes['href'];
      if (sel != null && href != null && _realHref(href)) {
        fields['nextContentUrl'] = '@css:$sel@href';
      }
    }

    return AutoPageResult(fields: fields);
  }

  // ============================ JSON 列表 ============================

  static AutoListResult? _inferJsonList(
      String raw, String baseUrl, List<String> fieldKeys) {
    dynamic json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    final path = <String>[];
    List? bestList;
    int bestScore = -1;

    void walk(dynamic node, List<String> p) {
      if (node is List) {
        if (node.isNotEmpty && node.every((e) => e is Map)) {
          final keys = (node.first as Map).keys.map((e) => e.toString()).toList();
          int score = node.length * 5;
          final joined = keys.join(',').toLowerCase();
          if (RegExp(r'name|title').hasMatch(joined)) score += 10;
          if (RegExp(r'url|link|href|id').hasMatch(joined)) score += 6;
          if (RegExp(r'img|cover|pic').hasMatch(joined)) score += 4;
          if (keys.length >= 3) score += keys.length;
          if (score > bestScore) { bestScore = score; bestList = node; path
            ..clear()
            ..addAll(p);
          }
        }
        for (var i = 0; i < node.length && i < 3; i++) {
          walk(node[i], [...p, '[$i]']);
        }
      } else if (node is Map) {
        for (final e in node.entries) {
          walk(e.value, [...p, e.key.toString()]);
        }
      }
    }

    walk(json, const []);
    final list = bestList;
    if (list == null || list.isEmpty) return null;

    final listPath = '\$.${path.where((s) => !s.startsWith('[')).join('.')}[*]';
    final first = list.first as Map;
    final fields = <String, String>{};
    String? sample;

    String? matchKey(List<String> aliases) {
      for (final k in first.keys) {
        final low = k.toString().toLowerCase();
        if (aliases.any(low.contains)) return k.toString();
      }
      return null;
    }

    void bind(String field, List<String> aliases) {
      final k = matchKey(aliases);
      if (k != null) fields[field] = '\$.$k';
    }

    if (fieldKeys.contains('name')) bind('name', const ['name', 'title', 'bookname']);
    if (fieldKeys.contains('author')) bind('author', const ['author', 'writer']);
    if (fieldKeys.contains('intro')) bind('intro', const ['intro', 'desc', 'summary', 'abstract']);
    if (fieldKeys.contains('kind')) bind('kind', const ['cate', 'kind', 'type', 'tag']);
    if (fieldKeys.contains('lastChapter')) bind('lastChapter', const ['lastchapter', 'newchapter', 'latest']);
    if (fieldKeys.contains('wordCount')) bind('wordCount', const ['wordcount', 'word', 'zishu']);
    if (fieldKeys.contains('coverUrl')) bind('coverUrl', const ['cover', 'img', 'pic', 'image', 'thumb']);
    if (fieldKeys.contains('bookUrl')) bind('bookUrl', const ['bookurl', 'url', 'link', 'href', 'id']);
    if (fieldKeys.contains('chapterName')) bind('chapterName', const ['title', 'name', 'chaptername']);
    if (fieldKeys.contains('chapterUrl')) bind('chapterUrl', const ['url', 'link', 'href', 'contenturl']);

    final urlKey = fields['bookUrl'] ?? fields['chapterUrl'];
    if (urlKey != null) {
      final v = first[urlKey.substring(2)]?.toString();
      if (v != null) sample = _resolve(v, baseUrl);
    }

    return AutoListResult(
      isJson: true,
      listRule: listPath,
      fields: fields,
      sampleUrl: sample,
      notes: ['识别为 JSON 接口，列表路径 $listPath'],
    );
  }
}

class _Block {
  final dom.Element container;
  final String itemTag;
  final List<dom.Element> items;
  _Block(this.container, this.itemTag, this.items);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
