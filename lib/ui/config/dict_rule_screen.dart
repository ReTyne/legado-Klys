import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:legado_md3/help/source/content_services.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/source/js_mini_eval.dart';
import 'package:legado_md3/help/storage/shibboleth.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

/// 字典 JS 求值回调（无头 / 测试环境可注入，返回 null 表示无可用运行时）。
typedef DictJsEvaluator = String? Function(String script, String result);

/// 字典三段规则：urlRule 生成查询 URL、showRule 提取展示内容、buttonClick 处理点击。
class DictRuleSegments {
  const DictRuleSegments({
    this.urlRule = '',
    this.showRule = '',
    this.buttonClick = '',
  });

  final String urlRule;
  final String showRule;
  final String buttonClick;

  bool get isEmpty =>
      urlRule.isEmpty && showRule.isEmpty && buttonClick.isEmpty;

  /// 编码为可存入 DictRule.rule 的 JSON 字符串。
  String encode() => jsonEncode({
        'urlRule': urlRule,
        'showRule': showRule,
        'buttonClick': buttonClick,
      });

  /// 解析三段规则：支持 JSON 对象、`|||` 分隔；旧版纯 JS 串视为 showRule。
  static DictRuleSegments parse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const DictRuleSegments();
    if (t.startsWith('{')) {
      try {
        final m = jsonDecode(t);
        if (m is Map) {
          return DictRuleSegments(
            urlRule: (m['urlRule'] ?? m['url'] ?? '').toString(),
            showRule: (m['showRule'] ?? m['show'] ?? '').toString(),
            buttonClick: (m['buttonClick'] ?? m['click'] ?? '').toString(),
          );
        }
      } catch (_) {}
    }
    if (t.contains('|||')) {
      final parts = t.split('|||');
      return DictRuleSegments(
        urlRule: parts.isNotEmpty ? parts[0].trim() : '',
        showRule: parts.length > 1 ? parts[1].trim() : '',
        buttonClick: parts.length > 2 ? parts[2].trim() : '',
      );
    }
    // 兼容旧版：整段当展示规则（JS）。
    return DictRuleSegments(showRule: t);
  }
}

/// 点击动作类型。
enum DictClickType { none, open, copy, share, js }

/// buttonClick 解析结果。
class DictClickAction {
  const DictClickAction(this.type, this.value);
  final DictClickType type;
  final String value;
}

/// 字典三段规则引擎：查询真正走规则，而非固定打开一个 WebView。
class DictRuleEngine {
  DictRuleEngine({DictJsEvaluator? jsEval}) : _jsEval = jsEval;

  final DictJsEvaluator? _jsEval;
  final RulePipeline _pipeline = RulePipeline();

  static DictRuleSegments segmentsOf(DictRule rule) =>
      DictRuleSegments.parse(rule.rule ?? '');

  String? _eval(String script, String result) {
    var code = script.trim();
    if (code.isEmpty) return null;
    if (_jsEval != null) return _jsEval(code, result);
    final hasAssign = RegExp(r'\bresult\s*=[^=]').hasMatch(code) ||
        code.contains('return') ||
        code.contains(';');
    if (!hasAssign) code = 'result = $code';
    return JsMiniEvaluator.eval(code, result: result);
  }

  static String _template(String t, String encoded) =>
      t.replaceAll('{word}', encoded).replaceAll('{{word}}', encoded);

  /// urlRule 生成查询 URL：{word} 模板 / @js: 求值；空则回退 DictRule.url 的 {word} 模板。
  String buildUrl(DictRule rule, String word) {
    final w = word.trim();
    final encoded = Uri.encodeComponent(w);
    final urlRule = segmentsOf(rule).urlRule.trim();
    if (urlRule.isNotEmpty) {
      if (urlRule.toLowerCase().startsWith('@js:')) {
        final out = _eval(urlRule.substring(4).trim(), w);
        if (out != null && out.trim().isNotEmpty) return out.trim();
      } else {
        return _template(urlRule, encoded);
      }
    }
    // 兜底：现有 {word} 模板
    return _template(rule.url, encoded);
  }

  /// showRule 从结果提取展示内容：@js: / CSS / JSONPath / 正则，命中为空回退净化原文。
  String extractShow(String raw, DictRule rule) {
    final show = segmentsOf(rule).showRule.trim();
    if (show.isEmpty) return _cleanText(raw);
    if (show.toLowerCase().startsWith('@js:')) {
      return _eval(show.substring(4).trim(), raw) ?? _cleanText(raw);
    }
    try {
      _pipeline.baseUrl = '';
      final list = _pipeline.extractListFromRaw(raw, show);
      final joined =
          list.map((e) => e.trim()).where((e) => e.isNotEmpty).join('\n');
      if (joined.isNotEmpty) return joined;
    } catch (_) {}
    return _cleanText(raw);
  }

  /// buttonClick 处理点击动作：解析为 open / copy / share / js / none。
  DictClickAction clickAction(DictRule rule, String word) {
    final c = segmentsOf(rule).buttonClick.trim();
    if (c.isEmpty) return const DictClickAction(DictClickType.none, '');
    if (c.toLowerCase().startsWith('@js:')) {
      return DictClickAction(DictClickType.js, c.substring(4).trim());
    }
    final low = c.toLowerCase();
    if (low == 'copy' || c == '复制') {
      return const DictClickAction(DictClickType.copy, '');
    }
    if (low == 'share' || c == '分享') {
      return const DictClickAction(DictClickType.share, '');
    }
    return DictClickAction(
      DictClickType.open,
      _template(c, Uri.encodeComponent(word.trim())),
    );
  }

  static String _cleanText(String raw) => raw
      .replaceAll(
          RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
}

/// 字典面板：两个 Tab 分别管理两套不同语义的「字典规则」。
///
/// 历史问题：两套规则曾经共用一个界面名，但数据源与消费方完全不同，
/// 导致「在词典规则里加的规则阅读页查不到」。现在拆清楚：
///
///  - 词语替换：`rule|||replacement` 存 SharedPreferences `dict_rules`，
///    由 [ContentDictService] 应用到正文（把错别字/自定义写法批量替换）。
///  - 词典规则：存数据库 `dict_rules` 表，由阅读页「划词 → 查词」调用，
///    `url` 中 `{word}` 为被查询词占位符。
class DictRuleScreen extends StatefulWidget {
  const DictRuleScreen({super.key});

  @override
  State<DictRuleScreen> createState() => _DictRuleScreenState();
}

class _DictRuleScreenState extends State<DictRuleScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('字典规则'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '词语替换'),
              Tab(text: '词典查询'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ReplaceTab(),
            _DictSourceTab(),
          ],
        ),
      ),
    );
  }
}

/* ===================== Tab 1：正文词语替换 ===================== */

class _ReplaceTab extends StatefulWidget {
  const _ReplaceTab();

  @override
  State<_ReplaceTab> createState() => _ReplaceTabState();
}

class _ReplaceTabState extends State<_ReplaceTab> {
  final _ruleCtl = TextEditingController();
  final _replacementCtl = TextEditingController();
  List<Map<String, String>> _rules = [];
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await ContentDictService.loadRules();
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _enabled = p.getBool('dict_rule_enabled') ?? true;
    });
  }

  Future<void> _save() async {
    await ContentDictService.saveRules(_enabled, _rules);
    await ContentDictService.reload();
    await _load();
  }

  Future<void> _importNetwork() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('网络导入替换规则'),
        content: TextField(
            controller: ctl,
            decoration: const InputDecoration(hintText: '规则 URL（JSON 数组）')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctl.text.trim()),
              child: const Text('导入')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      final res = await Dio(BaseOptions(responseType: ResponseType.plain))
          .get<String>(url);
      final data = jsonDecode(res.data ?? '[]');
      final list = data is List ? data : [data];
      var added = 0;
      for (final m in list) {
        if (m is! Map) continue;
        final rule =
            (m['rule'] ?? m['showRule'] ?? m['pattern'] ?? '').toString();
        if (rule.isEmpty) continue;
        _rules.add({
          'rule': rule,
          'replacement':
              (m['replacement'] ?? m['name'] ?? m['replace'] ?? '').toString(),
        });
        added++;
      }
      await _save();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入 $added 条')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('启用词语替换'),
          subtitle: const Text('替换会作用在阅读正文上'),
          value: _enabled,
          onChanged: (v) async {
            setState(() => _enabled = v);
            await _save();
          },
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            children: [
              TextField(
                controller: _ruleCtl,
                decoration: const InputDecoration(
                    labelText: '查找内容(正则)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: AppSpacing.s),
              TextField(
                controller: _replacementCtl,
                decoration: const InputDecoration(
                    labelText: '替换为', border: OutlineInputBorder()),
              ),
              const SizedBox(height: AppSpacing.s),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('添加规则'),
                  onPressed: () async {
                    if (_ruleCtl.text.trim().isEmpty) return;
                    setState(() {
                      _rules.add({
                        'rule': _ruleCtl.text.trim(),
                        'replacement': _replacementCtl.text.trim(),
                      });
                      _ruleCtl.clear();
                      _replacementCtl.clear();
                    });
                    await _save();
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _importNetwork,
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('网络导入'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _rules.isEmpty
              ? const AppEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: '暂无词典规则',
                  message: '可网络导入或新增词典规则',
                )
              : ListView.builder(
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final r = _rules[index];
                    return ListTile(
                      title: Text(r['rule']!,
                          style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text('→ ${r['replacement']}',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: Icon(Icons.delete,
                            color: Theme.of(context).colorScheme.error),
                        onPressed: () async {
                          setState(() => _rules.removeAt(index));
                          await _save();
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/* ===================== Tab 2：词典查询规则 ===================== */

class _DictSourceTab extends StatefulWidget {
  const _DictSourceTab();

  @override
  State<_DictSourceTab> createState() => _DictSourceTabState();
}

class _DictSourceTabState extends State<_DictSourceTab> {
  final _db = DatabaseService();
  List<DictRule> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _db.getDictRules();
    if (!mounted) return;
    setState(() {
      _rules = list;
      _loading = false;
    });
  }

  Future<void> _save(DictRule rule) async {
    await _db.updateDictRule(rule);
    await _load();
  }

  Future<void> _delete(DictRule rule) async {
    if (rule.id == null) return;
    await _db.deleteDictRule(rule.id!);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已删除')));
  }

  /// 把词典规则的查询地址混淆成分享口令，复制到剪贴板。
  Future<void> _shareShibboleth(DictRule rule) async {
    final url = rule.url.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该词典规则未配置查询地址')),
      );
      return;
    }
    final code = generateShareCode(url, ShareType.dictRule);
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('词典规则分享口令已复制')),
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _rules.removeAt(oldIndex);
    _rules.insert(newIndex, item);
    setState(() {});
    for (var i = 0; i < _rules.length; i++) {
      if (_rules[i].order != i) {
        await _db.updateDictRule(_rules[i].copyWith(order: i));
      }
    }
  }

  Future<void> _importNetwork() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('网络导入词典规则'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(hintText: '规则 URL（返回 JSON 数组）'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctl.text.trim()),
              child: const Text('导入')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      final res = await Dio(BaseOptions(responseType: ResponseType.plain))
          .get<String>(url);
      final data = jsonDecode(res.data ?? '[]');
      final list = data is List ? data : [data];
      var added = 0;
      for (final m in list) {
        if (m is! Map) continue;
        final name = (m['name'] ?? m['title'] ?? '').toString();
        final dictUrl = (m['url'] ?? m['link'] ?? '').toString();
        if (name.isEmpty || dictUrl.isEmpty) continue;
        added++;
        await _db.insertDictRule(DictRule(
          name: name,
          summary: (m['summary'] ?? m['desc'] ?? '').toString(),
          url: dictUrl,
          rule: (m['rule'] ?? m['js'] ?? '').toString(),
          order: _rules.length + added,
        ));
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入 $added 条')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('失败: $e')));
    }
  }

  void _editRule([DictRule? rule]) {
    showDialog<void>(
      context: context,
      builder: (_) => _DictRuleEditDialog(
        rule: rule,
        onSave: (r) async {
          await _save(rule == null ? r.copyWith(order: _rules.length) : r);
        },
      ),
    );
  }

  /// 用三段规则引擎真实跑一次查询（生成 URL → 抓取 → 提取展示 → 处理点击）。
  void _testRule(DictRule rule) {
    showDialog<void>(
      context: context,
      builder: (_) => _DictRuleTestDialog(rule: rule),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text('阅读页选中文字后点「查词」即可调用',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              TextButton.icon(
                onPressed: _importNetwork,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('网络导入'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // 三态统一收敛到 AppAsyncState，保留 ReorderableListView 拖拽能力。
          child: AppAsyncState(
            loading: _loading,
            isEmpty: _rules.isEmpty,
            emptyIcon: Icons.menu_book_outlined,
            emptyTitle: '暂无词典规则',
            emptyAction: FilledButton.icon(
              onPressed: _editRule,
              icon: const Icon(Icons.add),
              label: const Text('新增规则'),
            ),
            child: ReorderableListView.builder(
              onReorder: _reorder,
              itemCount: _rules.length,
              itemBuilder: (context, index) {
                final r = _rules[index];
                return ListTile(
                  key: ValueKey('dict_${r.id ?? index}'),
                  leading: Icon(
                    r.enabled == 1
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: r.enabled == 1
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(r.name),
                  subtitle: Text(
                    r.url.isEmpty ? r.summary : r.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '测试查询',
                        icon: const Icon(Icons.search, size: 18),
                        onPressed: () => _testRule(r),
                      ),
                      Switch(
                        value: r.enabled == 1,
                        onChanged: (v) => _save(r.copyWith(enabled: v ? 1 : 0)),
                      ),
                      IconButton(
                        tooltip: '生成分享口令',
                        icon: const Icon(Icons.key_outlined, size: 18),
                        onPressed: () => _shareShibboleth(r),
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error),
                        onPressed: () => _delete(r),
                      ),
                      ReorderableDragStartListener(
                          index: index, child: const Icon(Icons.drag_handle)),
                    ],
                  ),
                  onTap: () => _editRule(r),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 新增 / 编辑词典规则对话框
class _DictRuleEditDialog extends StatefulWidget {
  final DictRule? rule;
  final ValueChanged<DictRule> onSave;
  const _DictRuleEditDialog({this.rule, required this.onSave});

  @override
  State<_DictRuleEditDialog> createState() => _DictRuleEditDialogState();
}

class _DictRuleEditDialogState extends State<_DictRuleEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _summary;
  late final TextEditingController _urlRule;
  late final TextEditingController _showRule;
  late final TextEditingController _click;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    final seg = DictRuleSegments.parse(r?.rule ?? '');
    _name = TextEditingController(text: r?.name ?? '');
    _url = TextEditingController(text: r?.url ?? '');
    _summary = TextEditingController(text: r?.summary ?? '');
    _urlRule = TextEditingController(text: seg.urlRule);
    _showRule = TextEditingController(text: seg.showRule);
    _click = TextEditingController(text: seg.buttonClick);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _summary.dispose();
    _urlRule.dispose();
    _showRule.dispose();
    _click.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? '新增词典规则' : '编辑词典规则'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: '名称', hintText: '例如：汉语词典'),
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: '查询地址',
                hintText: 'https://www.zdic.net/hans/?q={word}',
                helperText: '用 {word} 作为被查询词占位符',
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _summary,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _urlRule,
              decoration: const InputDecoration(
                labelText: 'urlRule 生成查询地址',
                hintText: 'https://dict.com/hans/{word} 或 @js:…',
                helperText: '留空则回退上方「查询地址」的 {word} 模板',
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _showRule,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'showRule 提取展示内容',
                hintText: r'@css:.content / $.data.explain / @js:…',
                helperText: '从返回内容里提取释义，留空则净化原文',
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _click,
              decoration: const InputDecoration(
                labelText: 'buttonClick 点击动作（可选）',
                hintText: 'copy / share / @js:… / https://…/{word}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final url = _url.text.trim();
            if (name.isEmpty || url.isEmpty) return;
            widget.onSave(DictRule(
              id: widget.rule?.id,
              name: name,
              url: url,
              summary: _summary.text.trim(),
              rule: DictRuleSegments(
                urlRule: _urlRule.text.trim(),
                showRule: _showRule.text.trim(),
                buttonClick: _click.text.trim(),
              ).encode(),
              enabled: widget.rule?.enabled ?? 1,
              order: widget.rule?.order ?? 0,
            ));
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 三段规则查询测试：真实走 urlRule → 抓取 → showRule → buttonClick。
class _DictRuleTestDialog extends StatefulWidget {
  const _DictRuleTestDialog({required this.rule});
  final DictRule rule;

  @override
  State<_DictRuleTestDialog> createState() => _DictRuleTestDialogState();
}

class _DictRuleTestDialogState extends State<_DictRuleTestDialog> {
  final _wordCtl = TextEditingController(text: '阅读');
  final DictRuleEngine _engine = DictRuleEngine();
  bool _loading = false;
  String _url = '';
  String _result = '';
  String? _error;

  @override
  void dispose() {
    _wordCtl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final word = _wordCtl.text.trim();
    if (word.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = '';
    });
    final url = _engine.buildUrl(widget.rule, word);
    if (!mounted) return;
    setState(() => _url = url);
    try {
      final resp = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
      )).get<String>(url);
      final show =
          _engine.extractShow(resp.data?.toString() ?? '', widget.rule);
      if (!mounted) return;
      setState(() {
        _result = show.isEmpty ? '（无内容）' : show;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '请求失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _applyClick() async {
    final action = _engine.clickAction(widget.rule, _wordCtl.text.trim());
    final mq = ScaffoldMessenger.of(context);
    switch (action.type) {
      case DictClickType.open:
        final uri = Uri.tryParse(action.value.isEmpty ? _url : action.value);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case DictClickType.copy:
        await Clipboard.setData(ClipboardData(text: _url));
        mq.showSnackBar(const SnackBar(content: Text('查询地址已复制')));
        break;
      case DictClickType.share:
        await Share.share(_result.isEmpty ? _url : _result,
            subject: widget.rule.name);
        break;
      case DictClickType.js:
        final out = JsMiniEvaluator.eval(action.value,
            result: _result.isEmpty ? _url : _result);
        mq.showSnackBar(SnackBar(content: Text(out ?? '脚本无返回')));
        break;
      case DictClickType.none:
        mq.showSnackBar(const SnackBar(content: Text('该规则未配置点击动作')));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = _engine.clickAction(widget.rule, _wordCtl.text.trim());
    return AlertDialog(
      title: Text('测试：${widget.rule.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _wordCtl,
                decoration: const InputDecoration(
                  labelText: '查询词',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              FilledButton.icon(
                onPressed: _loading ? null : _run,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search, size: 18),
                label: const Text('按规则查询'),
              ),
              if (_url.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s),
                const Text('查询地址', style: TextStyle(fontSize: 11)),
                SelectableText(_url,
                    style:
                        const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s),
                  child: Text(_error!,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error)),
                ),
              if (_result.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s),
                const Text('展示内容（showRule 提取）', style: TextStyle(fontSize: 11)),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 260),
                  padding: const EdgeInsets.all(AppSpacing.s),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SingleChildScrollView(
                    child: SelectableText(_result,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (action.type != DictClickType.none)
          TextButton.icon(
            onPressed: _applyClick,
            icon: const Icon(Icons.touch_app_outlined, size: 16),
            label: Text(_clickLabel(action.type)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }

  String _clickLabel(DictClickType t) {
    switch (t) {
      case DictClickType.open:
        return '打开链接';
      case DictClickType.copy:
        return '复制地址';
      case DictClickType.share:
        return '分享结果';
      case DictClickType.js:
        return '执行动作';
      case DictClickType.none:
        return '';
    }
  }
}
