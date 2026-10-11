import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/model/rss_source.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/help/source/rule_auto_completer.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// RSS源编辑页面 —— 与书源编辑页同款 MD3 卡片式交互（4 分页）。
/// 字段以“卡片预览 + 点击弹出底部多行编辑器”呈现；顶栏提供 测试 / 保存 / 更多
/// （规则补全、复制、粘贴、分享）。列表规则由 RssService 实际生效。
class RssSourceEditScreen extends StatefulWidget {
  final RssSource? source;
  const RssSourceEditScreen({super.key, this.source});

  @override
  State<RssSourceEditScreen> createState() => _RssSourceEditScreenState();
}

class _F {
  final String key, label, hint;
  final bool mono;
  const _F(this.key, this.label, this.hint, {this.mono = true});
}

class _RssSourceEditScreenState extends State<RssSourceEditScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseService();
  final _rss = RssService();
  late TabController _tabController;
  final Map<String, TextEditingController> _c = {};
  bool _enabled = true;
  bool _dirty = false;

  static const List<String> _tabs = ['基本', '起始', '列表', 'WebView'];

  static const _quickTokens = [
    '@text', '@html', '@href', '@src', 'class.', 'id.', 'tag.', '\$.', '{{}}', '<js></js>', '@js:', '@Regex:',
  ];

  static const Map<String, List<_F>> _defs = {
    'base': [
      _F('sourceName', '源名称', '订阅源名称', mono: false),
      _F('sourceUrl', '源URL', 'RSS/Atom 地址或网页列表地址'),
      _F('sourceIcon', '源图标', '图标 URL'),
      _F('sourceGroup', '源分组', '多个分组用英文逗号分隔', mono: false),
      _F('sourceComment', '注释', '订阅源说明', mono: false),
      _F('searchUrl', '搜索URL', '支持 {{key}}/{{page}} 模板'),
      _F('sortUrl', '排序URL', '分类排序地址'),
      _F('loginUrl', '登录URL', '需要登录时填写'),
      _F('loginUi', '登录UI', '登录界面配置 JSON'),
      _F('loginCheckJs', '登录检测JS', '检测登录是否成功的脚本'),
      _F('coverDecodeJs', '封面解码JS', '封面地址解密脚本'),
      _F('header', 'HTTP请求头', 'JSON，例如 {"User-Agent":"..."}'),
      _F('concurrentRate', '并发率', '如 2000（毫秒）或 1/2000'),
      _F('variableComment', '变量注释', '变量说明', mono: false),
      _F('jsLib', 'JS 库', '可复用的 JS 函数库'),
    ],
    'start': [
      _F('startHtml', 'startHtml', '起始 URL/HTML 处理'),
      _F('startStyle', 'articleStyle', '列表样式（JSON 字段 articleStyle）'),
      _F('startJs', 'startJs', '起始 JS 脚本'),
      _F('preloadJs', 'preloadJs', '预加载 JS'),
    ],
    'list': [
      _F('ruleArticles', '文章列表', '定位每篇文章的列表项（CSS/XPath/JSONPath）'),
      _F('ruleNextPage', '下一页', '列表翻页规则'),
      _F('ruleTitle', '标题', '文章标题规则'),
      _F('rulePubDate', '发布日期', '发布时间规则'),
      _F('ruleDescription', '描述', '摘要/描述规则'),
      _F('ruleImage', '图片', '封面/缩略图规则'),
      _F('ruleLink', '链接', '文章链接规则'),
    ],
    'webview': [
      _F('ruleContent', '正文规则', 'WebView 正文获取规则'),
      _F('style', '样式', '注入 CSS'),
      _F('injectJs', '注入JS', '页面注入脚本'),
      _F('contentWhitelist', '内容白名单', '保留的元素/类名'),
      _F('contentBlacklist', '内容黑名单', '移除的元素/类名'),
      _F('shouldOverrideUrlLoading', 'URL跳转拦截JS', '拦截跳转脚本'),
    ],
  };

  TextEditingController _tc(String key, String init) =>
      _c.putIfAbsent(key, () => TextEditingController(text: init));

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _tabController = TabController(length: 4, vsync: this);
    _enabled = s?.enabled ?? true;
    String v(String? val) => val ?? '';
    _tc('sourceName', s?.sourceName ?? '');
    _tc('sourceUrl', s?.sourceUrl ?? '');
    for (final f in [
      ['sourceIcon', v(s?.sourceIcon)], ['sourceGroup', v(s?.sourceGroup)],
      ['sourceComment', v(s?.sourceComment)], ['searchUrl', v(s?.searchUrl)],
      ['sortUrl', v(s?.sortUrl)], ['loginUrl', v(s?.loginUrl)],
      ['loginUi', v(s?.loginUi)], ['loginCheckJs', v(s?.loginCheckJs)],
      ['coverDecodeJs', v(s?.coverDecodeJs)], ['header', v(s?.header)],
      ['concurrentRate', v(s?.concurrentRate)], ['variableComment', v(s?.variableComment)],
      ['jsLib', v(s?.jsLib)], ['startHtml', v(s?.startHtml)],
      ['startStyle', v(s?.startStyle)], ['startJs', v(s?.startJs)],
      ['preloadJs', v(s?.preloadJs)], ['ruleArticles', v(s?.ruleArticles)],
      ['ruleNextPage', v(s?.ruleNextPage)], ['ruleTitle', v(s?.ruleTitle)],
      ['rulePubDate', v(s?.rulePubDate)], ['ruleDescription', v(s?.ruleDescription)],
      ['ruleImage', v(s?.ruleImage)], ['ruleLink', v(s?.ruleLink)],
      ['ruleContent', v(s?.ruleContent)], ['style', v(s?.style)],
      ['injectJs', v(s?.injectJs)], ['contentWhitelist', v(s?.contentWhitelist)],
      ['contentBlacklist', v(s?.contentBlacklist)],
      ['shouldOverrideUrlLoading', v(s?.shouldOverrideUrlLoading)],
    ]) {
      _tc(f[0], f[1]);
    }
    for (final c in _c.values) {
      c.addListener(() => _dirty = true);
    }
    _dirty = false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trimmed(String k) {
    final t = _c[k]!.text.trim();
    return t.isEmpty ? null : t;
  }

  RssSource _collect() {
    String? opt(String k) => _trimmed(k);
    return RssSource(
      id: widget.source?.id,
      sourceName: _c['sourceName']!.text.trim(),
      sourceUrl: _c['sourceUrl']!.text.trim(),
      sourceIcon: opt('sourceIcon'),
      sourceGroup: opt('sourceGroup'),
      sourceComment: opt('sourceComment'),
      searchUrl: opt('searchUrl'),
      sortUrl: opt('sortUrl'),
      loginUrl: opt('loginUrl'),
      loginUi: opt('loginUi'),
      loginCheckJs: opt('loginCheckJs'),
      coverDecodeJs: opt('coverDecodeJs'),
      header: opt('header'),
      variableComment: opt('variableComment'),
      concurrentRate: opt('concurrentRate'),
      jsLib: opt('jsLib'),
      startHtml: opt('startHtml'),
      startStyle: opt('startStyle'),
      startJs: opt('startJs'),
      preloadJs: opt('preloadJs'),
      ruleArticles: opt('ruleArticles'),
      ruleNextPage: opt('ruleNextPage'),
      ruleTitle: opt('ruleTitle'),
      rulePubDate: opt('rulePubDate'),
      ruleDescription: opt('ruleDescription'),
      ruleImage: opt('ruleImage'),
      ruleLink: opt('ruleLink'),
      ruleContent: opt('ruleContent'),
      style: opt('style'),
      injectJs: opt('injectJs'),
      contentWhitelist: opt('contentWhitelist'),
      contentBlacklist: opt('contentBlacklist'),
      shouldOverrideUrlLoading: opt('shouldOverrideUrlLoading'),
      enabled: _enabled,
      customOrder: widget.source?.customOrder,
      lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
      unreadCount: widget.source?.unreadCount ?? 0,
    );
  }

  bool _validate() {
    if (_c['sourceName']!.text.trim().isEmpty) {
      _toast('源名称不能为空');
      _tabController.animateTo(0);
      return false;
    }
    if (_c['sourceUrl']!.text.trim().isEmpty) {
      _toast('源URL不能为空');
      _tabController.animateTo(0);
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final s = _collect();
    try {
      if (widget.source == null) {
        await _db.insertRssSource(s);
      } else {
        await _db.updateRssSource(s);
      }
      await JsRuntimeManager.instance.invalidate(s.sourceUrl);
      _dirty = false;
      if (mounted) {
        _toast('保存成功');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _toast('保存失败: $e');
    }
  }

  Future<void> _test() async {
    if (!_validate()) return;
    final s = _collect();
    _toast('正在测试…');
    final ok = await _rss.testSource(s);
    if (mounted) _toast(ok ? '测试通过：可获取文章' : '测试失败：未获取到文章');
  }

  /// 智能补全文章列表规则（抓取源 URL，识别重复文章块）
  Future<void> _autoComplete() async {
    final url = _c['sourceUrl']!.text.trim();
    if (url.isEmpty) {
      _toast('请先填写源URL');
      _tabController.animateTo(0);
      return;
    }
    final log = ValueNotifier<String>('抓取页面…');
    var dismissed = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder<String>(
            valueListenable: log,
            builder: (_, v, __) => Text(v, maxLines: 2, overflow: TextOverflow.ellipsis),
          )),
        ]),
      ),
    ).then((_) => dismissed = true);

    try {
      final s = _collect();
      final html = await _rss.fetchRaw(url, header: s.header);
      if (html.trim().isEmpty) throw '页面抓取为空（可能需要登录或为动态渲染）';
      log.value = '识别重复文章块…';
      final res = RuleAutoCompleter.inferList(html, baseUrl: url);
      if (res.isEmpty) throw '未能识别出重复文章列表';
      final mapping = {
        'ruleArticles': res.listRule,
        'ruleTitle': res.fields['name'] ?? '',
        'ruleLink': res.fields['bookUrl'] ?? '',
        'ruleDescription': res.fields['intro'] ?? '',
        'ruleImage': res.fields['coverUrl'] ?? '',
      };
      var n = 0;
      mapping.forEach((k, rule) {
        if (rule.trim().isNotEmpty && _c[k]!.text.trim().isEmpty) {
          _c[k]!.text = rule;
          n++;
        }
      });
      if (mounted && !dismissed) Navigator.of(context).pop();
      setState(() {});
      _toast(n > 0 ? '智能补全完成，新增 $n 条列表规则' : '规则均已填写，无需补全');
    } catch (e) {
      if (mounted && !dismissed) Navigator.of(context).pop();
      _toast('智能补全失败：$e');
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: jsonEncode(_collect().toJson())));
    _toast('RSS源 JSON 已复制');
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('剪贴板为空');
      return;
    }
    try {
      final dynamic j = jsonDecode(text);
      final obj = (j is List && j.isNotEmpty) ? j.first : j;
      final s = RssSource.fromJson(obj as Map<String, dynamic>);
      setState(() {
        _c['sourceName']!.text = s.sourceName;
        _c['sourceUrl']!.text = s.sourceUrl;
        for (final pair in {
          'sourceIcon': s.sourceIcon, 'sourceGroup': s.sourceGroup,
          'sourceComment': s.sourceComment, 'searchUrl': s.searchUrl,
          'sortUrl': s.sortUrl, 'loginUrl': s.loginUrl, 'loginUi': s.loginUi,
          'loginCheckJs': s.loginCheckJs, 'coverDecodeJs': s.coverDecodeJs,
          'header': s.header, 'variableComment': s.variableComment,
          'concurrentRate': s.concurrentRate, 'jsLib': s.jsLib,
          'startStyle': s.startStyle, 'ruleArticles': s.ruleArticles,
          'ruleNextPage': s.ruleNextPage, 'ruleTitle': s.ruleTitle,
          'rulePubDate': s.rulePubDate, 'ruleDescription': s.ruleDescription,
          'ruleImage': s.ruleImage, 'ruleLink': s.ruleLink,
          'ruleContent': s.ruleContent, 'style': s.style, 'injectJs': s.injectJs,
          'contentWhitelist': s.contentWhitelist, 'contentBlacklist': s.contentBlacklist,
          'shouldOverrideUrlLoading': s.shouldOverrideUrlLoading,
        }.entries) {
          if (pair.value != null) _c[pair.key]!.text = pair.value!;
        }
        _enabled = s.enabled ?? true;
        _dirty = true;
      });
      _toast('已粘贴 RSS 源');
    } catch (_) {
      _toast('粘贴失败：剪贴板不是合法 RSS 源 JSON');
    }
  }

  void _share() {
    Share.share(jsonEncode(_collect().toJson()));
  }

  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _menuTile(Icons.auto_fix_high, '规则补全', () {
            Navigator.pop(ctx);
            _tabController.animateTo(2);
            _autoComplete();
          }),
          _menuTile(Icons.copy, '复制RSS源', () { Navigator.pop(ctx); _copy(); }),
          _menuTile(Icons.paste, '粘贴RSS源', () { Navigator.pop(ctx); _paste(); }),
          _menuTile(Icons.ios_share, '分享RSS源', () { Navigator.pop(ctx); _share(); }),
        ]),
      ),
    );
  }

  Widget _menuTile(IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: onTap,
      );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ===================== 卡片 / 编辑器 =====================

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            )),
      );

  Widget _fieldCard(_F f) {
    final c = _c[f.key]!;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        dense: true,
        title: Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: AnimatedBuilder(
          animation: c,
          builder: (_, __) => Text(
            c.text.trim().isEmpty ? f.hint : c.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: f.mono ? 'monospace' : null,
              color: c.text.trim().isEmpty
                  ? Theme.of(context).colorScheme.outline
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () => _openEditor(c, f.label, f.hint, mono: f.mono),
      ),
    );
  }

  Future<void> _openEditor(TextEditingController controller, String label, String hint,
      {bool mono = true}) async {
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
            maxChildSize: 0.94,
            builder: (_, scrollCtrl) => Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(label, style: Theme.of(ctx).textTheme.titleMedium)),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, editCtrl.text),
                    child: const Text('确定'),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final t in _quickTokens)
                    ActionChip(
                      label: Text(t, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _insertAtCursor(editCtrl, t),
                    ),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: editCtrl,
                    scrollController: scrollCtrl,
                    maxLines: null,
                    expands: true,
                    autofocus: true,
                    style: TextStyle(fontFamily: mono ? 'monospace' : null, fontSize: 13.5),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      hintText: hint,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
    editCtrl.dispose();
    if (result != null) {
      controller.text = result;
      setState(() {});
    }
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

  Future<void> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('当前 RSS 源尚未保存，返回将丢失修改。'),
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

  Widget _tabBody(String group) => ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (group == 'base') ...[
            _sectionTitle('基本信息'),
            SwitchListTile(
              secondary: const Icon(Icons.rss_feed),
              title: const Text('启用该源'),
              value: _enabled,
              onChanged: (v) => setState(() {
                _enabled = v;
                _dirty = true;
              }),
            ),
          ],
          _sectionTitle(group == 'base'
              ? '请求与高级'
              : group == 'list'
                  ? '列表规则'
                  : group == 'start'
                      ? '起始规则'
                      : 'WebView 规则'),
          for (final f in _defs[group]!) _fieldCard(f),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.source == null ? '新建RSS源' : '编辑RSS源'),
          actions: [
            IconButton(icon: const Icon(Icons.wifi_tethering), tooltip: '测试', onPressed: _test),
            IconButton(icon: const Icon(Icons.save), tooltip: '保存', onPressed: _save),
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
          children: [_tabBody('base'), _tabBody('start'), _tabBody('list'), _tabBody('webview')],
        ),
      ),
    );
  }
}
