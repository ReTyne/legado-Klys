import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/rule_auto_completer.dart';
import 'package:legado_md3/ui/book/source/source_debug_screen.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';
import 'package:legado_md3/ui/browser/browser_screen.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';

/// 书源编辑页 —— 对齐 legado-with-MD3：
/// 字段以“卡片预览 + 点击弹出底部多行编辑器”呈现，六个分页（基础/搜索/发现/详情/目录/正文），
/// 顶栏提供 调试 / 更多（登录、保存并搜索、清除 Cookie、规则补全、设置变量、复制、粘贴、分享、帮助）。
class SourceEditScreen extends StatefulWidget {
  final BookSource? source;
  const SourceEditScreen({super.key, this.source});

  @override
  State<SourceEditScreen> createState() => _SourceEditScreenState();
}

class _SourceEditScreenState extends State<SourceEditScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  late TabController _tabController;

  /// 标量字段控制器（key 与 BookSource 的 JSON 字段同名）
  final Map<String, TextEditingController> _c = {};
  /// 各规则组：组名 -> (子规则 key -> 控制器)
  final Map<String, Map<String, TextEditingController>> _rules = {};
  /// 各规则组原始内容（粘贴/载入时保留未知子字段，避免编辑后丢失）
  final Map<String, Map<String, dynamic>> _origRules = {};

  final Map<String, bool> _flags = {
    'enabled': true,
    'enabledExplore': false,
    'enabledCookieJar': false,
    'eventListener': false,
    'customButton': false,
  };
  int _sourceType = 0;
  bool _dirty = false;

  static const List<String> _tabs = ['基础', '搜索', '发现', '主页', '详情', '目录', '正文'];

  // 规则组子字段定义：key -> (中文标签, 提示)
  static const Map<String, List<_RuleField>> _ruleDefs = {
    'ruleSearch': [
      _RuleField('bookList', '书籍列表', '定位每一本书的列表项（CSS/XPath/JSONPath）'),
      _RuleField('name', '书名', '名称规则'),
      _RuleField('author', '作者', '作者规则'),
      _RuleField('intro', '简介', '简介规则'),
      _RuleField('kind', '分类', '分类规则'),
      _RuleField('lastChapter', '最新章节', '最新章节规则'),
      _RuleField('wordCount', '字数', '字数规则'),
      _RuleField('coverUrl', '封面URL', '封面规则'),
      _RuleField('bookUrl', '详情页URL', '详情链接规则'),
    ],
    'ruleExplore': [
      _RuleField('bookList', '书籍列表', '定位每一本书的列表项'),
      _RuleField('name', '书名', '名称规则'),
      _RuleField('author', '作者', '作者规则'),
      _RuleField('intro', '简介', '简介规则'),
      _RuleField('kind', '分类', '分类规则'),
      _RuleField('lastChapter', '最新章节', '最新章节规则'),
      _RuleField('wordCount', '字数', '字数规则'),
      _RuleField('coverUrl', '封面URL', '封面规则'),
      _RuleField('bookUrl', '详情页URL', '详情链接规则'),
    ],
    'ruleBookInfo': [
      _RuleField('init', '初始化', '页面初始化 JS'),
      _RuleField('name', '书名', '名称规则'),
      _RuleField('author', '作者', '作者规则'),
      _RuleField('intro', '简介', '简介规则'),
      _RuleField('kind', '分类', '分类规则'),
      _RuleField('lastChapter', '最新章节', '最新章节规则'),
      _RuleField('wordCount', '字数', '字数规则'),
      _RuleField('coverUrl', '封面URL', '封面规则'),
      _RuleField('tocUrl', '目录URL', '目录页链接规则'),
      _RuleField('canReName', '可改名', '是否允许改名'),
      _RuleField('downloadUrls', '下载URL', '下载链接规则'),
      _RuleField('relatedBooks', '相关书籍', '相关推荐规则'),
    ],
    'ruleToc': [
      _RuleField('preUpdateJs', '更新前JS', '目录更新前执行'),
      _RuleField('chapterList', '章节列表', '定位每一章的列表项'),
      _RuleField('chapterName', '章节名', '章节标题规则'),
      _RuleField('chapterUrl', '章节URL', '正文链接规则'),
      _RuleField('isVolume', '卷标识', '判断是否为卷'),
      _RuleField('isVip', 'VIP标识', '判断是否 VIP'),
      _RuleField('isPay', '付费标识', '判断是否付费'),
      _RuleField('updateTime', '更新时间', '更新时间规则'),
      _RuleField('formatJs', '格式化JS', '格式化脚本'),
      _RuleField('nextTocUrl', '下一页目录', '目录翻页规则'),
    ],
    'ruleContent': [
      _RuleField('content', '正文内容', '正文主体规则'),
      _RuleField('title', '标题', '正文内标题规则'),
      _RuleField('nextContentUrl', '下一页正文', '正文翻页规则'),
      _RuleField('webJs', 'WebJS', '注入 JS'),
      _RuleField('sourceRegex', '来源正则', '正文来源匹配'),
      _RuleField('replaceRegex', '替换正则', '正文替换规则'),
      _RuleField('imageStyle', '图片样式', '图片处理样式'),
      _RuleField('imageDecode', '图片解码', '图片解码 JS'),
      _RuleField('payAction', '付费操作', '付费处理规则'),
      _RuleField('subContent', '正文分块', '分块规则'),
      _RuleField('callBackJs', '回调JS', '回调脚本'),
    ],
  };

  // 规则编辑器快捷插入片段
  static const List<String> _quickTokens = [
    '@text', '@html', '@href', '@src', 'class.', 'id.', 'tag.', '\$.', '{{}}', '<js></js>', '@js:', '@Regex:',
  ];

  TextEditingController _tc(String key, [String init = '']) =>
      _c.putIfAbsent(key, () => TextEditingController(text: init));

  TextEditingController _ruleTc(String group, String key, [String init = '']) =>
      _rules.putIfAbsent(group, () => {}).putIfAbsent(key, () => TextEditingController(text: init));

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    // 先建立全部控制器
    for (final k in const [
      'bookSourceUrl', 'bookSourceName', 'bookSourceGroup', 'bookSourceComment', 'concurrentRate',
      'header', 'loginUrl', 'loginUi', 'loginCheckJs', 'bookUrlPattern', 'charset', 'coverDecodeJs',
      'homepageModules', 'jsLib', 'variable', 'variableComment', 'weight', 'customOrder',
      'searchUrl', 'checkKeyWord', 'exploreUrl', 'exploreScreen',
    ]) {
      _tc(k);
      _c[k]!.addListener(_markDirty);
    }
    for (final entry in _ruleDefs.entries) {
      for (final f in entry.value) {
        _ruleTc(entry.key, f.key);
        _rules[entry.key]![f.key]!.addListener(_markDirty);
      }
    }
    _loadFromSource(widget.source);
    _dirty = false;
  }

  void _markDirty() => _dirty = true;

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    for (final g in _rules.values) {
      for (final c in g.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String _rv(Map<String, dynamic>? rule, String key) => rule?[key]?.toString() ?? '';

  void _loadFromSource(BookSource? s) {
    if (s == null) return;
    void setC(String k, String v) => _c[k]!.text = v;
    setC('bookSourceUrl', s.bookSourceUrl);
    setC('bookSourceName', s.bookSourceName);
    setC('bookSourceGroup', s.bookSourceGroup ?? '');
    setC('bookSourceComment', s.bookSourceComment ?? '');
    setC('concurrentRate', s.concurrentRate ?? '');
    setC('header', s.header ?? '');
    setC('loginUrl', s.loginUrl ?? '');
    setC('loginUi', s.loginUi ?? '');
    setC('loginCheckJs', s.loginCheckJs ?? '');
    setC('bookUrlPattern', s.bookUrlPattern ?? '');
    setC('charset', s.charset ?? '');
    setC('coverDecodeJs', s.coverDecodeJs ?? '');
    setC('homepageModules', s.homepageModules ?? '');
    setC('jsLib', s.jsLib ?? '');
    setC('variable', s.variable ?? '');
    setC('variableComment', s.variableComment ?? '');
    setC('weight', s.weight.toString());
    setC('customOrder', s.customOrder.toString());
    setC('searchUrl', s.searchUrl ?? '');
    setC('checkKeyWord', s.checkKeyWord ?? '');
    setC('exploreUrl', s.exploreUrl ?? '');
    setC('exploreScreen', s.exploreScreen ?? '');

    _flags['enabled'] = s.enabled;
    _flags['enabledExplore'] = s.enabledExplore;
    _flags['enabledCookieJar'] = s.enabledCookieJar;
    _flags['eventListener'] = s.eventListener;
    _flags['customButton'] = s.customButton;
    _sourceType = s.bookSourceType;

    final groupMap = {
      'ruleSearch': s.ruleSearch,
      'ruleExplore': s.ruleExplore,
      'ruleBookInfo': s.ruleBookInfo,
      'ruleToc': s.ruleToc,
      'ruleContent': s.ruleContent,
    };
    groupMap.forEach((group, rule) {
      _origRules[group] = Map<String, dynamic>.from(rule ?? {});
      for (final f in _ruleDefs[group]!) {
        _rules[group]![f.key]!.text = _rv(rule, f.key);
      }
    });
    _origRules['ruleReview'] = Map<String, dynamic>.from(s.ruleReview ?? {});
    _origRules['ruleImage'] = Map<String, dynamic>.from(s.ruleImage ?? {});
  }

  String? _trimmed(String k) {
    final v = _c[k]!.text.trim();
    return v.isEmpty ? null : v;
  }

  int _intField(String k, int fallback) => int.tryParse(_c[k]!.text.trim()) ?? fallback;

  /// 收集某个规则组：保留原始未知键，覆盖已知键（空值移除）
  Map<String, dynamic>? _collectRule(String group) {
    final map = Map<String, dynamic>.from(_origRules[group] ?? {});
    for (final f in _ruleDefs[group] ?? const <_RuleField>[]) {
      final v = _rules[group]?[f.key]?.text.trim() ?? '';
      if (v.isEmpty) {
        map.remove(f.key);
      } else {
        map[f.key] = v;
      }
    }
    return map.isEmpty ? null : map;
  }

  /// 依据当前表单构造书源（不写库），供保存/调试/搜索/导出复用
  BookSource _collect() {
    final old = widget.source;
    return BookSource(
      bookSourceUrl: _c['bookSourceUrl']!.text.trim(),
      bookSourceName: _c['bookSourceName']!.text.trim(),
      bookSourceGroup: _trimmed('bookSourceGroup'),
      bookSourceType: _sourceType,
      bookSourceComment: _trimmed('bookSourceComment'),
      lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
      enabled: _flags['enabled']!,
      enabledExplore: _flags['enabledExplore']!,
      enabledCookieJar: _flags['enabledCookieJar']!,
      eventListener: _flags['eventListener']!,
      customButton: _flags['customButton']!,
      concurrentRate: _trimmed('concurrentRate'),
      customOrder: _intField('customOrder', old?.customOrder ?? 0),
      respondTime: old?.respondTime ?? 180000,
      weight: _intField('weight', old?.weight ?? 0),
      header: _trimmed('header'),
      loginUrl: _trimmed('loginUrl'),
      loginUi: _trimmed('loginUi'),
      loginCheckJs: _trimmed('loginCheckJs'),
      bookUrlPattern: _trimmed('bookUrlPattern'),
      charset: _trimmed('charset'),
      coverDecodeJs: _trimmed('coverDecodeJs'),
      homepageModules: _trimmed('homepageModules'),
      searchUrl: _trimmed('searchUrl'),
      checkKeyWord: _trimmed('checkKeyWord'),
      exploreUrl: _trimmed('exploreUrl'),
      exploreScreen: _trimmed('exploreScreen'),
      ruleSearch: _collectRule('ruleSearch'),
      ruleExplore: _collectRule('ruleExplore'),
      ruleBookInfo: _collectRule('ruleBookInfo'),
      ruleToc: _collectRule('ruleToc'),
      ruleContent: _collectRule('ruleContent'),
      ruleReview: _origRules['ruleReview']?.isNotEmpty == true ? _origRules['ruleReview'] : null,
      ruleImage: _origRules['ruleImage']?.isNotEmpty == true ? _origRules['ruleImage'] : null,
      variableComment: _trimmed('variableComment'),
      jsLib: _trimmed('jsLib'),
      variable: _trimmed('variable'),
    );
  }

  bool _validate() {
    if (_c['bookSourceUrl']!.text.trim().isEmpty) {
      _toast('书源URL不能为空');
      _tabController.animateTo(0);
      return false;
    }
    if (_c['bookSourceName']!.text.trim().isEmpty) {
      _toast('书源名称不能为空');
      _tabController.animateTo(0);
      return false;
    }
    return true;
  }

  Future<bool> _save({bool pop = true}) async {
    if (!_validate()) return false;
    final source = _collect();
    try {
      final existing = await _db.getSource(source.bookSourceUrl);
      if (existing != null) {
        await _db.updateSource(source);
      } else {
        await _db.insertSource(source);
      }
      // 书源脚本（jsLib/loginUrl/规则）变更后，丢弃缓存的 JS 运行时上下文
      await JsRuntimeManager.instance.invalidate(source.bookSourceUrl);
      _dirty = false;
      if (mounted) _toast('保存成功');
      if (pop && mounted) Navigator.pop(context, true);
      return true;
    } catch (e) {
      if (mounted) _toast('保存失败: $e');
      return false;
    }
  }

  // ===================== 菜单动作 =====================

  Future<void> _debug() async {
    if (!_validate()) return;
    final source = _collect();
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SourceDebugScreen(source: source)));
    }
  }

  Future<void> _login() async {
    final loginUi = _trimmed('loginUi');
    final loginUrl = _trimmed('loginUrl');
    if ((loginUi == null || loginUi.trim().isEmpty) &&
        (loginUrl == null || loginUrl.trim().isEmpty)) {
      _toast('该书源未配置登录信息（loginUi 或 loginUrl）');
      return;
    }
    final source = _collect();
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => SourceLoginScreen(source: source)));
  }

  Future<void> _saveAndSearch() async {
    final ok = await _save(pop: false);
    if (ok && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
    }
  }

  Future<void> _clearCookie() async {
    final url = _c['bookSourceUrl']!.text.trim();
    if (url.isEmpty) {
      _toast('书源URL为空');
      return;
    }
    try {
      String? host;
      try {
        host = Uri.parse(url).host;
      } catch (_) {}
      if (host != null && host.isNotEmpty) CookieManager().removeHost(host);
      await _db.deleteCookie(url);
      _toast('已清除该书源 Cookie');
    } catch (e) {
      _toast('清除失败: $e');
    }
  }

  final BookSourceEngine _engine = BookSourceEngine();

  /// 规则补全：联网抓取页面，智能识别重复结构并生成可被引擎消费的规则（对齐 legado autoComplete）。
  /// 仅填充当前为空的规则，用户已填写的规则不会被覆盖；断网/动态页时回退到本地占位补全。
  Future<void> _autoComplete() async {
    final tab = _tabController.index;
    if (tab == 0) {
      _toast('请切换到「搜索 / 发现 / 详情 / 目录 / 正文」分页后再补全规则');
      return;
    }
    final BookSource source = _collect();
    final log = ValueNotifier<String>('准备中…');
    var dismissed = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder<String>(
            valueListenable: log,
            builder: (_, v, __) => Text(v, maxLines: 2, overflow: TextOverflow.ellipsis),
          )),
        ]),
      ),
    ).then((_) => dismissed = true);

    try {
      var filled = 0;
      final notes = <String>[];
      if (tab == 1 || tab == 2) {
        final isSearch = tab == 1;
        log.value = isSearch ? '抓取搜索结果页…' : '抓取发现分类页…';
        String urlTpl;
        var keyword = '';
        if (isSearch) {
          if (source.searchUrl == null || source.searchUrl!.trim().isEmpty) {
            throw '请先在搜索分页填写「搜索URL」';
          }
          urlTpl = source.searchUrl!;
          keyword = source.checkKeyWord?.trim().isNotEmpty == true
              ? source.checkKeyWord!.trim()
              : '斗破苍穹';
        } else {
          if (source.exploreUrl == null || source.exploreUrl!.trim().isEmpty) {
            throw '请先在发现分页填写「发现URL」';
          }
          urlTpl = _engine.firstExploreUrlOf(source.exploreUrl!);
          if (urlTpl.trim().isEmpty) throw '发现URL 中未解析出有效分类地址';
        }
        final html = await _engine.editFetch(source, urlTpl, keyword: keyword, page: 1);
        log.value = '识别重复列表项与字段…';
        final res =
            RuleAutoCompleter.inferList(html, baseUrl: _originOf(urlTpl, source.bookSourceUrl));
        if (res.isEmpty) throw '未能识别出重复列表项（可能为动态渲染或需要登录）';
        filled = _applyInferred(isSearch ? 'ruleSearch' : 'ruleExplore',
            listKey: 'bookList', listRule: res.listRule, fields: res.fields);
        notes.addAll(res.notes);
      } else {
        // 详情/目录/正文：先拿到一个样本书，再逐级抓取推导
        log.value = '抓取列表页以获取样本书…';
        String? listHtml;
        String listTpl = '';
        if (source.searchUrl != null && source.searchUrl!.trim().isNotEmpty) {
          final kw = source.checkKeyWord?.trim().isNotEmpty == true
              ? source.checkKeyWord!.trim()
              : '斗破苍穹';
          listTpl = source.searchUrl!;
          listHtml = await _engine.editFetch(source, listTpl, keyword: kw, page: 1);
        } else if (source.exploreUrl != null && source.exploreUrl!.trim().isNotEmpty) {
          listTpl = _engine.firstExploreUrlOf(source.exploreUrl!);
          if (listTpl.isNotEmpty) listHtml = await _engine.editFetch(source, listTpl, page: 1);
        }
        if (listHtml == null) throw '需要先配置可用的搜索URL或发现URL作为样本来源';
        final listBase = _originOf(listTpl, source.bookSourceUrl);
        final listRes = RuleAutoCompleter.inferList(listHtml, baseUrl: listBase);
        var sampleUrl = listRes.sampleUrl;
        if (sampleUrl == null || sampleUrl.isEmpty) throw '列表页未解析出详情链接';

        log.value = '抓取详情页…';
        final detailHtml = await _engine.editFetch(source, sampleUrl);
        final info = RuleAutoCompleter.inferBookInfo(detailHtml, baseUrl: sampleUrl);
        if (tab >= 3) {
          filled += _applyInferred('ruleBookInfo', fields: info.fields);
        }
        if (tab == 3) {
          notes.add('详情规则推导完成');
        } else {
          var tocUrl = info.nextUrl;
          if (tocUrl == null || tocUrl.isEmpty) {
            tocUrl = _engine.resolveEditUrl(sampleUrl, source.bookSourceUrl);
          }
          log.value = '抓取目录页…';
          final tocHtml = await _engine.editFetch(source, tocUrl);
          final toc = RuleAutoCompleter.inferChapterList(tocHtml, baseUrl: tocUrl);
          if (toc.isEmpty) throw '目录页未识别出章节列表';
          if (tab >= 4) {
            filled += _applyInferred('ruleToc',
                listKey: 'chapterList', listRule: toc.listRule, fields: toc.fields);
          }
          if (tab == 4) {
            notes.add('目录规则推导完成');
          } else {
            final chapterUrl = toc.sampleUrl;
            if (chapterUrl == null || chapterUrl.isEmpty) throw '目录页未解析出正文链接';
            log.value = '抓取正文页…';
            final contentHtml = await _engine.editFetch(source, chapterUrl);
            final content =
                RuleAutoCompleter.inferContent(contentHtml, baseUrl: chapterUrl);
            if (content.fields.isEmpty) throw '正文页未识别出正文容器';
            filled += _applyInferred('ruleContent', fields: content.fields);
            notes.add('正文规则推导完成');
          }
        }
      }

      if (mounted && dismissed == false) Navigator.of(context).pop();
      setState(() {});
      _toast(filled > 0
          ? '智能补全完成，新增 $filled 条规则${notes.isNotEmpty ? '（${notes.join('；')}）' : ''}'
          : '已分析页面，但规则均已填写，无需补全');
    } catch (e) {
      if (mounted && dismissed == false) Navigator.of(context).pop();
      final n = _localComplete();
      _toast('智能补全失败：$e；已改用本地补全 $n 条占位规则');
    }
  }

  /// 由 URL 模板推导站点基址；失败时回退书源URL（去掉模板/查询参数）
  String _originOf(String urlTpl, String fallback) {
    if (fallback.trim().isNotEmpty) return fallback;
    try {
      final raw = urlTpl.split(',').first.trim();
      final uri = Uri.parse(raw);
      if (uri.scheme.startsWith('http') && uri.host.isNotEmpty) {
        final port = (uri.port == 80 || uri.port == 443 || uri.port == 0)
            ? ''
            : ':${uri.port}';
        return '${uri.scheme}://$uri.host$port';
      }
    } catch (_) {}
    return fallback;
  }

  /// 把推导结果写入对应规则组（仅填充空规则），返回新增条数
  int _applyInferred(String group,
      {String? listKey, String? listRule, Map<String, String> fields = const {}}) {
    final controllers = _rules[group];
    if (controllers == null) return 0;
    var n = 0;
    if (listKey != null && listRule != null) {
      final c = controllers[listKey];
      if (c != null && c.text.trim().isEmpty) {
        c.text = listRule;
        n++;
      }
    }
    fields.forEach((key, rule) {
      final c = controllers[key];
      if (c != null && c.text.trim().isEmpty && rule.trim().isNotEmpty) {
        c.text = rule;
        n++;
      }
    });
    return n;
  }

  /// 离线兜底：列表项已定位、叶子规则为空时，按字段类型补默认取值规则
  int _localComplete() {
    const textFields = {'name', 'author', 'intro', 'kind', 'lastChapter', 'wordCount', 'init', 'canReName', 'updateTime', 'chapterName', 'title'};
    const hrefFields = {'bookUrl', 'tocUrl', 'chapterUrl', 'nextTocUrl', 'nextContentUrl'};
    const srcFields = {'coverUrl', 'imageDecode'};
    var filled = 0;
    for (final group in ['ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent']) {
      final controllers = _rules[group];
      if (controllers == null) continue;
      controllers.forEach((key, c) {
        if (c.text.trim().isEmpty) {
          if (textFields.contains(key)) {
            c.text = '@text';
            filled++;
          } else if (hrefFields.contains(key)) {
            c.text = '@href';
            filled++;
          } else if (srcFields.contains(key)) {
            c.text = '@src';
            filled++;
          }
        }
      });
    }
    setState(() {});
    return filled;
  }

  Future<void> _setVariable() async {
    final ctrl = _c['variable']!;
    final res = await _openEditor(ctrl, '书源变量', mono: true, tokens: const []);
    if (res != null) setState(() {});
  }

  Future<void> _copySource() async {
    final source = _collect();
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(source.toJson())));
    if (mounted) _toast('书源 JSON 已复制');
  }

  Future<void> _pasteSource() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('剪贴板为空');
      return;
    }
    try {
      final dynamic json = jsonDecode(text);
      // 兼容单个对象与数组（取第一个）
      final Map<String, dynamic> map = json is List
          ? (json.first as Map<String, dynamic>)
          : json as Map<String, dynamic>;
      final source = BookSource.fromJson(map);
      _loadFromSource(source);
      setState(() {});
      _toast('已粘贴书源');
    } catch (e) {
      _toast('粘贴失败：剪贴板不是合法书源 JSON');
    }
  }

  void _shareSource() {
    final source = _collect();
    Share.share(jsonEncode(source.toJson()));
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuTile(Icons.login_outlined, '登录', _login),
            _menuTile(Icons.travel_explore, '保存并搜索', _saveAndSearch),
            _menuTile(Icons.cookie_outlined, '清除 Cookie', _clearCookie),
            _menuTile(Icons.auto_fix_high, '规则补全', () async {
              Navigator.pop(ctx);
              _autoComplete();
            }),
            _menuTile(Icons.code, '设置书源变量', () async {
              Navigator.pop(ctx);
              _setVariable();
            }),
            _menuTile(Icons.copy, '复制书源', () {
              Navigator.pop(ctx);
              _copySource();
            }),
            _menuTile(Icons.paste, '粘贴书源', () {
              Navigator.pop(ctx);
              _pasteSource();
            }),
            _menuTile(Icons.ios_share, '分享书源', () {
              Navigator.pop(ctx);
              _shareSource();
            }),
            _menuTile(Icons.help_outline, '规则帮助', () {
              Navigator.pop(ctx);
              _showHelp();
            }),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: onTap,
      );

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('书源规则帮助'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('CSS 选择器', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('class.xxx / id.xxx / tag.li，@text 取文本、@href 取链接、@src 取图片'),
              SizedBox(height: 8),
              Text('XPath', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('//div[@class="xxx"]/text()'),
              SizedBox(height: 8),
              Text('JSONPath', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(r'$.data.list[*].name'),
              SizedBox(height: 8),
              Text('正则', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('@Regex:正则表达式@@替换结果'),
              SizedBox(height: 8),
              Text('JS', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('<js>...</js> 或 @js: 结果为脚本返回值'),
              SizedBox(height: 8),
              Text('URL 模板', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('{{key}} 关键词  {{page}} 页码  {{(page-1)*20}} 计算'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ===================== 字段卡片 & 底部编辑器 =====================

  /// 底部弹出的全屏多行编辑器，返回新文本（取消返回 null）
  Future<String?> _openEditor(TextEditingController controller, String label,
      {bool mono = false, List<String> tokens = _quickTokens}) async {
    final editCtrl = TextEditingController(text: controller.text);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (ctx, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: Theme.of(ctx).textTheme.titleMedium)),
                      TextButton(onPressed: () => editCtrl.clear(), child: const Text('清空')),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, editCtrl.text),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ),
                if (tokens.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final t in tokens)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ActionChip(
                              label: Text(t),
                              onPressed: () => _insertAtCursor(editCtrl, t),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: TextField(
                      controller: editCtrl,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: mono ? const TextStyle(fontFamily: 'monospace', fontSize: 13) : null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        hintText: '在此输入，支持多行…',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    editCtrl.dispose();
    return result;
  }

  void _insertAtCursor(TextEditingController c, String token) {
    final sel = c.selection;
    final text = c.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final newText = text.replaceRange(start, end, token);
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  Widget _fieldCard(String key, String label, {String? hint, bool mono = true, List<String> tokens = _quickTokens}) {
    final controller = _c[key]!;
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) => _card(
        label,
        controller.text,
        hint: hint,
        mono: mono,
        onTap: () async {
          final res = await _openEditor(controller, label, mono: mono, tokens: tokens);
          if (res != null) setState(() => controller.text = res);
        },
      ),
    );
  }

  Widget _ruleCard(String group, _RuleField f) {
    final controller = _rules[group]![f.key]!;
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) => _card(
        f.label,
        controller.text,
        hint: f.hint,
        mono: true,
        onTap: () async {
          final res = await _openEditor(controller, f.label);
          if (res != null) setState(() => controller.text = res);
        },
      ),
    );
  }

  Widget _card(String label, String value, {String? hint, bool mono = false, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    final filled = value.trim().isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            if (filled)
              Icon(Icons.check_circle, size: 14, color: theme.colorScheme.primary)
            else
              Icon(Icons.radio_button_unchecked, size: 14, color: theme.colorScheme.outlineVariant),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            filled ? value.trim() : (hint ?? '未设置，点击编辑'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: mono
                ? TextStyle(fontFamily: 'monospace', fontSize: 12, color: filled ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.outline)
                : TextStyle(fontSize: 12, color: filled ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.outline),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Widget _flagTile(String key, String title, String? subtitle) => SwitchListTile(
        dense: true,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: _flags[key]!,
        onChanged: (v) => setState(() {
          _flags[key] = v;
          _dirty = true;
        }),
      );

  Widget _typeSelector() {
    const names = ['文本', '音频', '图片', '文件'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text('书源类型', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < names.length; i++)
                ChoiceChip(
                  label: Text(names[i]),
                  selected: _sourceType == i,
                  onSelected: (_) => setState(() {
                    _sourceType = i;
                    _dirty = true;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 规则组原始 JSON 编辑（ruleReview / ruleImage 等高级规则）
  Widget _rawJsonTile(String group, String label) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.data_object),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _editRawJson(group, label),
    );
  }

  Future<void> _editRawJson(String group, String label) async {
    final current = _origRules[group] ?? {};
    final ctrl = TextEditingController(
        text: current.isEmpty ? '' : const JsonEncoder.withIndent('  ').convert(current));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '{}'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('清空')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('保存')),
        ],
      ),
    );
    if (res == null) return;
    if (res.trim().isEmpty) {
      setState(() => _origRules[group] = {});
      return;
    }
    try {
      final decoded = jsonDecode(res);
      setState(() => _origRules[group] = decoded is Map ? Map<String, dynamic>.from(decoded) : {});
      _toast('已保存 $label');
    } catch (_) {
      _toast('JSON 格式有误，未保存');
    }
  }

  // ===================== 各分页 =====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.source == null ? '新建书源' : '编辑书源'),
          actions: [
            IconButton(icon: const Icon(Icons.bug_report_outlined), tooltip: '调试', onPressed: _debug),
            IconButton(icon: const Icon(Icons.save), tooltip: '保存', onPressed: () => _save()),
            IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _baseTab(),
            _ruleListTab('ruleSearch', top: [
              _fieldCard('searchUrl', '搜索URL', hint: 'https://host/search?q={{key}}&page={{page}}，支持 ,POST:body'),
              _fieldCard('checkKeyWord', '校验关键字', hint: '用于校验搜索结果是否有效', tokens: const ['{{key}}', '{{page}}']),
            ]),
            _ruleListTab('ruleExplore', top: [
              _fieldCard('exploreUrl', '发现URL', hint: '分类名::url，多个用换行分隔'),
              _fieldCard('exploreScreen', '发现分类', hint: '发现页分类展示配置'),
            ]),
            _homepageTab(),
            _ruleListTab('ruleBookInfo'),
            _ruleListTab('ruleToc'),
            _contentTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('当前书源尚未保存，返回将丢失修改。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续编辑')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('放弃')),
        ],
      ),
    );
    if (ok == true && mounted) {
      _dirty = false;
      Navigator.pop(context);
    }
  }

  Widget _baseTab() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _sectionTitle('基本信息'),
        _fieldCard('bookSourceUrl', '书源URL', hint: '书源唯一标识，例如 https://example.com', tokens: const []),
        _fieldCard('bookSourceName', '书源名称', hint: '便于识别的名称', mono: false, tokens: const []),
        _fieldCard('bookSourceGroup', '书源分组', hint: '多个分组用英文逗号分隔', mono: false, tokens: const []),
        _typeSelector(),
        _sectionTitle('开关'),
        _flagTile('enabled', '启用', '关闭后不参与搜索/发现'),
        _flagTile('enabledExplore', '启用发现', '在发现页展示该书源分类'),
        _flagTile('enabledCookieJar', '自动保存 Cookie', '持久化登录/会话 Cookie'),
        _flagTile('eventListener', '事件监听', '启用事件脚本监听'),
        _flagTile('customButton', '自定义按钮', '在详情/阅读页显示自定义按钮'),
        _sectionTitle('请求与登录'),
        _fieldCard('concurrentRate', '并发率', hint: '如 2000（请求间隔毫秒）或 1/2000', tokens: const []),
        _fieldCard('header', '请求头', hint: 'JSON，例如 {"User-Agent":"..."}'),
        _fieldCard('loginUrl', '登录地址', hint: '填写后可在更多菜单中打开登录', tokens: const []),
        _fieldCard('loginUi', '登录UI', hint: '登录界面配置 JSON'),
        _fieldCard('loginCheckJs', '登录检测JS', hint: '检测登录是否成功的脚本'),
        _fieldCard('bookUrlPattern', '详情URL正则', hint: '识别详情页链接的正则'),
        _fieldCard('charset', '编码', hint: 'utf-8 / gbk / gb18030，留空自动探测', tokens: const []),
        _fieldCard('coverDecodeJs', '封面解密JS', hint: '封面地址解密脚本'),
        _sectionTitle('高级'),
        _fieldCard('jsLib', 'JS 库', hint: '可被各规则复用的 JS 函数库'),
        _fieldCard('variable', '书源变量', hint: '书源内部变量，点此编辑'),
        _fieldCard('variableComment', '变量注释', hint: '变量说明', mono: false),
        _fieldCard('weight', '搜索权重', hint: '数字，越大越优先', tokens: const []),
        _fieldCard('customOrder', '排序编号', hint: '数字，手动排序', tokens: const []),
        _fieldCard('bookSourceComment', '备注', hint: '书源说明', mono: false, tokens: const []),
      ],
    );
  }

  Widget _ruleListTab(String group, {List<Widget> top = const []}) {
    final defs = _ruleDefs[group] ?? const [];
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        ...top,
        _sectionTitle('规则'),
        for (final f in defs) _ruleCard(group, f),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _contentTab() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _sectionTitle('正文规则'),
        for (final f in _ruleDefs['ruleContent']!) _ruleCard('ruleContent', f),
        const Divider(),
        _sectionTitle('高级规则（JSON）'),
        _rawJsonTile('ruleReview', '评论规则 ruleReview'),
        _rawJsonTile('ruleImage', '图片规则 ruleImage'),
      ],
    );
  }

  Widget _homepageTab() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _sectionTitle('首页模块'),
        _fieldCard('homepageModules', '首页模块 (JSON)',
            hint: 'JSON 数组，每项含 title/url/rule 等字段', mono: true),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            r'示例：' '\n'
            r'[' '\n'
            r'  {"title":"推荐","url":"/api/recommend","rule":{"bookList":"$.data","name":"$.name"}},' '\n'
            r'  {"title":"排行","url":"/api/rank","rule":{"bookList":"$.list","name":"$.title"}}' '\n'
            r']',
            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

/// 规则子字段描述
class _RuleField {
  final String key;
  final String label;
  final String hint;
  const _RuleField(this.key, this.label, this.hint);
}
