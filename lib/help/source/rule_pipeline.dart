
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/help/source/js_mini_eval.dart';
import 'package:legado_md3/help/source/json_path.dart';
import 'package:legado_md3/help/source/xpath_selector.dart';
part 'css_selector.dart';
part 'regex_parser.dart';


/// 规则解析模式
enum RuleMode { auto, css, xpath, json, js, regex, defaultRule }

/// Legado 书源统一规则管线。
///
/// 把项目里已有的 [CssSelector]/[XpathSelector]/[JsonPath]/[RegexParser]/
/// [JsMiniEvaluator] 组合起来，对齐原版 AnalyzeRule 的常用语法：
///
/// * 组合：`||`(或，取第一个非空)、`&&`(链式)、`%%`(按位交叉)、`@@`(取全部并换行合并)
/// * 模式前缀：`@css:`、`@xpath:`、`@json:`、`@js:`、`$.`(JSON)、`//`(XPath)、`:`(正则)
/// * 取值后缀：`@text/@textNodes/@ownText/@html/@all/@href/@src/属性名`
/// * 后处理：`##正则##替换`（可多段；单独 `##正则` 为删除；`###正则` 为只取首个匹配）
/// * JS：结尾 `@js:脚本`、整段 `<js>脚本</js>`、模板内 `{{脚本}}`
/// * 变量：`@put:{key:rule}` 把 rule 的结果存入变量表、`@get:{key||default}`
///   取出（支持 `&&`/`||` 组合，如 `@put:{token:<js>…}</js>}&&@get:{token}`）
/// * 默认(JSoup)语法：`tag.div@class.box!0@text`、`children`、负索引/区间索引
class RulePipeline {
  RulePipeline({this.baseUrl = '', this.keyword, this.page});

  /// 当前书源地址，用于相对 URL 解析
  String baseUrl;
  String? keyword;
  int? page;

  // ============================== 变量（@put: / @get:） ==============================

  /// 变量表：`@put:{key:rule}` 存入、`@get:{key}` 取出，用于跨步骤传值
  /// （如登录后拿 token 再传给后续请求）。
  /// 作用域为「书源 + 当前书籍/请求」，由引擎在每次新的书籍操作开始时
  /// 调用 [clearVariables] 清理。
  final Map<String, String> variables = {};

  /// 清空变量表（引擎在 search / explore / getBookInfo 等入口调用）。
  void clearVariables() => variables.clear();

  /// 扫描规则中的顶层变量语法块（`@put:` / `@get:`，大小写不敏感），
  /// 返回 (起始位置, 结束位置, 花括号内部文本)。
  /// 花括号先按引号感知配对（`<js>{...}</js>` 嵌套），引号不配平时
  /// （如正则值 `:token="([^"]+)"`）回退为纯深度配对。
  List<(int, int, String)> scanVarBlocks(String rule, String tag) {
    final result = <(int, int, String)>[];
    final lower = rule.toLowerCase();
    final tagLower = tag.toLowerCase();
    var from = 0;
    while (true) {
      final start = lower.indexOf(tagLower, from);
      if (start < 0) break;
      var i = start + tagLower.length;
      // 标签后跳过空白，期待 '{'
      while (i < rule.length && _isSpace(rule[i])) {
        i++;
      }
      if (i >= rule.length || rule[i] != '{') {
        from = start + tagLower.length;
        continue;
      }
      final end = _matchBrace(rule, i, quoteAware: true) >= 0
          ? _matchBrace(rule, i, quoteAware: true)
          : _matchBrace(rule, i, quoteAware: false);
      if (end < 0) {
        from = start + tagLower.length;
        continue;
      }
      result.add((start, end + 1, rule.substring(i + 1, end)));
      from = end + 1;
    }
    return result;
  }

  /// 从 rule[open] 的 '{' 起找配对的 '}' 下标，找不到返回 -1。
  int _matchBrace(String rule, int open, {required bool quoteAware}) {
    var depth = 0;
    var quote = '';
    for (var j = open; j < rule.length; j++) {
      final c = rule[j];
      if (quoteAware) {
        if (quote.isNotEmpty) {
          if (c == quote) quote = '';
          continue;
        }
        if (c == "'" || c == '"') {
          quote = c;
          continue;
        }
      }
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return j;
      }
    }
    return -1;
  }

  /// 解析 `@put:` 花括号内部的条目。
  ///
  /// 对齐上游 `AnalyzeRule.splitPutRule`：先用 **标准 JSON** 解析
  /// `@put:{"k":"v","k2":"v2"}`（GSONStrict），失败再按宽松
  /// `key:rule,key2:rule2`（对应 GSON 对非标准 JSON 的兼容回退）按第一个
  /// `:` 切分，value 里的 `:`/`,` 不受影响。
  List<MapEntry<String, String>> parsePutEntries(String inner) {
    final jsonEntries = _parseJsonPut(inner);
    if (jsonEntries != null) return jsonEntries;
    final out = <MapEntry<String, String>>[];
    for (final part in _splitTop(inner, const [','])) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final idx = p.indexOf(':');
      if (idx <= 0) continue;
      final key = _unquote(p.substring(0, idx).trim());
      if (key.isEmpty) continue;
      out.add(MapEntry(key, p.substring(idx + 1).trim()));
    }
    return out;
  }

  /// 尝试把 `inner`（花括号内部文本，不含外层 `{}`）当作标准 JSON 对象。
  /// 上游 put 的 value 是规则字符串，因此只接受字符串/数值标量；含内嵌
  /// `<js>` / `@get:{...}` 等复杂规则时 JSON 解析会失败，自然回退到宽松格式。
  List<MapEntry<String, String>>? _parseJsonPut(String inner) {
    final t = inner.trim();
    if (t.isEmpty || !t.contains('"')) return null;
    try {
      final decoded = jsonDecode('{$t}');
      if (decoded is Map) {
        final out = <MapEntry<String, String>>[];
        for (final e in decoded.entries) {
          final key = e.key?.toString() ?? '';
          if (key.isEmpty || e.value == null) continue;
          // 复杂对象/数组不是 put 值（上游 Map<String,String> 会拒绝）
          if (e.value is Map || e.value is List) return null;
          out.add(MapEntry(key, e.value.toString()));
        }
        return out.isEmpty ? null : out;
      }
    } catch (_) {}
    return null;
  }

  /// 把规则中的 `@get:{key||default}` 替换为变量值（无匹配时原样返回）。
  String substituteGets(String rule) {
    final blocks = scanVarBlocks(rule, '@get:');
    if (blocks.isEmpty) return rule;
    var out = rule;
    for (final b in blocks.reversed) {
      out = out.substring(0, b.$1) + _readVariable(b.$3) + out.substring(b.$2);
    }
    return out;
  }

  /// 读取 `@get:{key||default}`：变量非空取值，否则取 `||` 后的默认值。
  String _readVariable(String inner) {
    final sep = inner.indexOf('||');
    final key = _unquote((sep < 0 ? inner : inner.substring(0, sep)).trim());
    final v = variables[key];
    if (v != null && v.isNotEmpty) return v;
    if (sep < 0) return '';
    return _unquote(inner.substring(sep + 2).trim());
  }

  /// put 值是否“像规则”（含选择器/JS/正则特征）。不像规则时按字面文本
  /// 处理——如 `@put:{x:@get:{a}_c}` / `@put:{u:@get:{host}/a.jpg}`
  /// 期望得到拼接字符串而非选择器。
  static bool looksLikeRule(String value) {
    final t = value.trim();
    if (t.isEmpty) return false;
    final low = t.toLowerCase();
    if (low.startsWith('@css:') ||
        low.startsWith('@xpath:') ||
        low.startsWith('@json:') ||
        low.startsWith('@js:')) {
      return true;
    }
    if (t.startsWith('<js>') || t.startsWith('@@')) return true;
    if (t.startsWith(r'$.') || t.startsWith(r'$[')) return true;
    if (t.startsWith('//')) return true; // XPath
    if (t.startsWith(':')) return true; // 正则
    if (t.startsWith('#') || t.startsWith('.') || t.startsWith('[')) return true;
    if (t.startsWith('-')) return true; // 目录倒序标记
    if (t.contains('##') || t.contains('{{')) return true;
    if (t.contains('@')) return true; // 取值后缀 / 残留 @get
    if (t.contains('/')) return false; // URL 等字面量
    // 其余含 CSS 结构字符（class./tag./后代/子组合）的视为规则
    if (RegExp(r'[.\[\]#>]').hasMatch(t)) return true;
    return false; // 裸词按字面量
  }

  /// 规则若是 `<js>字符串字面量</js>` 返回该字面量，否则 null。
  /// 迷你求值器「result 优先」会把纯字面量误返回成原始内容，故这里直取。
  static String? jsLiteralValue(String rule) {
    final m = RegExp(r'^<js>\s*([\s\S]*?)\s*</js>$').firstMatch(rule.trim());
    if (m == null) return null;
    final s = m.group(1)!.trim();
    if (s.length < 2) return null;
    final q = s[0];
    if (q != '"' && q != "'") return null;
    if (!s.endsWith(q)) return null;
    final body = s.substring(1, s.length - 1);
    final sb = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (c == r'\' && i + 1 < body.length) {
        final n = body[i + 1];
        switch (n) {
          case 'n':
            sb.write('\n');
            break;
          case 't':
            sb.write('\t');
            break;
          case 'r':
            sb.write('\r');
            break;
          default:
            sb.write(n);
        }
        i++;
      } else {
        sb.write(c);
      }
    }
    return sb.toString();
  }

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';

  static String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  // ============================== 文本级 ==============================

  /// 从一整段响应文本按规则取“字符串列表”
  ///
  /// 支持原版三种连接符（同种规则间使用，不含 js/正则）：
  /// * `||` 或：从左到右取第一个非空分支
  /// * `%%` 交叉：多个分支按位依次取数
  /// * `&&` 合并：多个分支结果拼接
  List<String> extractListFromRaw(String raw, String rule,
      {bool forceJson = false, dom.Element? scope}) {
    if (rule.trim().isEmpty) return raw.isEmpty ? [] : [raw];
    // @put: 变量语法：先执行所有 put（左→右，对当前内容求值）并从规则中
    // 移除，避免 put 段里的连接符/花括号干扰后续 ||/&&/%% 拆分
    var effective = rule;
    final puts = scanVarBlocks(rule, '@put:');
    if (puts.isNotEmpty) {
      var rest = rule;
      for (final b in puts.reversed) {
        rest = rest.substring(0, b.$1) + rest.substring(b.$2);
      }
      for (final b in puts) {
        for (final e in parsePutEntries(b.$3)) {
          variables[e.key] = _evalPutValue(raw, substituteGets(e.value), forceJson);
        }
      }
      effective = rest;
    }
    final alternatives = _splitByConnectors(effective, const ['||']);
    for (final alt in alternatives) {
      final values = _extractCombined(raw, alt.text.trim(), forceJson, scope: scope);
      if (values.isNotEmpty) {
        return values; // || 取第一个非空
      }
    }
    return [];
  }

  /// 求一个 put 值：`<js>` 字面量直取；不像规则的纯文本按字面处理；
  /// 否则按普通规则对 [raw] 求值（多个结果换行合并）。
  String _evalPutValue(String raw, String valueRule, bool forceJson) {
    final lit = jsLiteralValue(valueRule);
    if (lit != null) return lit;
    if (!looksLikeRule(valueRule)) return valueRule;
    final values = _extractSingleChain(raw, valueRule, forceJson);
    if (values.isEmpty) return '';
    return values.length == 1 ? values.first : values.join('\n');
  }

  /// 从一整段响应文本按规则取字符串。
  /// 多个命中按 legado `AnalyzeByJSoup.getString` 语义以换行拼接——
  /// 正文规则（如 `#honbun@p@html`）命中多段时返回全文而非仅第一段。
  String? extractStringFromRaw(String raw, String rule, {bool forceJson = false}) {
    final list = extractListFromRaw(raw, rule, forceJson: forceJson);
    if (list.isEmpty) return null;
    return list.length == 1 ? list.first : list.join('\n');
  }

  /// 处理不含连接符（`||` / `%%` / `&&`）的单条规则链（仍可能含 @@ / ## / js）
  List<String> _extractSingleChain(String raw, String rule, bool forceJson,
      {dom.Element? scope}) {
    final mode = _detectMode(rule, forceJson: forceJson);

    // 整段 <js>...</js>：把原始内容交给 JS
    final jsWrap = RegExp(r'^<js>([\s\S]*?)</js>$').firstMatch(rule.trim());
    if (jsWrap != null) {
      final r = JsMiniEvaluator.eval(jsWrap.group(1)!,
          result: raw, key: keyword, page: page, baseUrl: baseUrl);
      return _nullEmpty(r);
    }

    // @@ 前缀：保留全部匹配，最后用换行合并为“一个值”
    var core = rule;
    var joinAll = false;
    if (core.startsWith('@@')) {
      joinAll = true;
      core = core.substring(2);
    }

    // 分离 ## 后处理
    final parsed = _splitPostProcess(core);
    core = parsed.selector;

    List<String> values;
    switch (mode) {
      case RuleMode.js:
        final script = core.startsWith('@js:') ? core.substring(4) : core;
        final r = JsMiniEvaluator.eval(script,
            result: raw, key: keyword, page: page, baseUrl: baseUrl);
        values = _nullEmpty(r);
        break;
      case RuleMode.json:
        values = _jsonValues(raw, core, forceJson);
        break;
      case RuleMode.xpath:
        values = _xpathValues(raw, core);
        break;
      case RuleMode.regex:
        values = _regexValues(raw, core);
        break;
      case RuleMode.css:
        values = _cssValues(raw, core);
        break;
      case RuleMode.defaultRule:
        values = _defaultValues(raw, core, scope: scope);
        break;
      case RuleMode.auto:
        values = forceJson || _looksJson(raw)
            ? _jsonValues(raw, core, true)
            : _defaultValues(raw, core, scope: scope);
        break;
    }

    // 模板插值 {{...}}
    if (values.isNotEmpty) {
      values = values.map((v) => _interpolate(v, parsed.hasInterpolation ? core : null)).toList();
    }

    // ## 正则后处理
    if (values.isNotEmpty && parsed.ops.isNotEmpty) {
      values = values.map((v) => _applyPostOps(v, parsed.ops)).where((v) => v.isNotEmpty).toList();
    }

    // 结尾 @js: 清洗
    final tailJs = parsed.tailJs;
    if (tailJs != null && values.isNotEmpty) {
      values = values
          .map((v) => JsMiniEvaluator.eval(tailJs, result: v, key: keyword, page: page, baseUrl: baseUrl) ?? v)
          .toList();
    }

    if (joinAll && values.isNotEmpty) return [values.join('\n')];
    return values;
  }

  /// 处理 `%%`（按位交叉）与 `&&`（合并）组合，返回字符串列表。
  ///
  /// 语义对齐原版 AnalyzeUrl：
  /// * `%%`：各分支先分别取值，再按位依次取数（列表1[0]、列表2[0]…列表1[1]…）
  /// * `&&`：各分支取值后直接合并拼接
  List<String> _extractCombined(String raw, String rule, bool forceJson,
      {dom.Element? scope}) {
    final cross = _splitByConnectors(rule, const ['%%']);
    if (cross.length > 1) {
      final lists = cross
          .map((seg) => _extractMerged(raw, seg.text.trim(), forceJson, scope: scope))
          .toList();
      return _crossZip(lists);
    }
    return _extractMerged(raw, rule, forceJson, scope: scope);
  }

  /// 处理 `&&`（合并）组合。
  List<String> _extractMerged(String raw, String rule, bool forceJson,
      {dom.Element? scope}) {
    final merged = _splitByConnectors(rule, const ['&&']);
    if (merged.length <= 1) return _valuesFromChain(raw, rule, forceJson, scope: scope);
    final out = <String>[];
    for (final seg in merged) {
      if (seg.text.trim().isEmpty) continue;
      out.addAll(_valuesFromChain(raw, seg.text.trim(), forceJson, scope: scope));
    }
    return out;
  }

  /// 单个规则段（@put: 已在 [extractListFromRaw] 提取完毕）：
  /// 整段即单个 `@get:{...}` 时直接取变量值，否则替换 @get: 后走普通链。
  /// 例：`@put:{token:<js>…</js>}&&@get:{token}` 移除 put 后剩
  /// `&&@get:{token}`，切出 `@get:{token}` 段即命中本分支。
  List<String> _valuesFromChain(String raw, String rule, bool forceJson,
      {dom.Element? scope}) {
    final t = rule.trim();
    if (t.isEmpty) return [];
    final gets = scanVarBlocks(t, '@get:');
    if (gets.length == 1 && gets.single.$1 == 0 && gets.single.$2 == t.length) {
      final v = _readVariable(gets.single.$3);
      return v.isEmpty ? const [] : [v];
    }
    return _extractSingleChain(raw, substituteGets(t), forceJson, scope: scope);
  }

  /// `%%` 按位交叉：依次取每个列表对应位置的值。
  static List<String> _crossZip(List<List<String>> lists) {
    final out = <String>[];
    var maxLen = 0;
    for (final l in lists) {
      if (l.length > maxLen) maxLen = l.length;
    }
    for (var i = 0; i < maxLen; i++) {
      for (final l in lists) {
        if (i < l.length) out.add(l[i]);
      }
    }
    return out;
  }

  // ============================== 元素级（HTML 列表） ==============================

  /// 选取列表元素（搜索/发现/目录的列表规则）
  List<dom.Element> selectElements(dom.Node scope, String listRule) {
    var rule = listRule.trim();
    if (rule.isEmpty) return [];
    if (rule.startsWith('-')) rule = rule.substring(1).trim(); // 目录倒序标记
    // 列表规则一般不用 ||，但兼容
    final first = _splitTop(rule, ['||']).first.trim();
    final mode = _detectMode(first);
    final core = _splitPostProcess(first).selector;
    switch (mode) {
      case RuleMode.css:
        return CssSelector.selectAll(scope, _stripCssPrefix(core));
      case RuleMode.xpath:
        return XpathSelector.selectNodes(scope, _stripXPathPrefix(core))
            .whereType<dom.Element>()
            .toList();
      case RuleMode.defaultRule:
      case RuleMode.auto:
        return _defaultElements(scope, core);
      default:
        // JSON 不会走这里
        return _defaultElements(scope, core);
    }
  }

  /// 相对单个 HTML 元素取字段值。
  /// 多个命中按 legado `AnalyzeByJSoup.getString` 语义以换行拼接
  /// （如正文规则 `#honbun@p@html` 命中多段时返回全文，而非仅第一段）。
  String? fieldFromElement(dom.Element el, String rule) {
    if (rule.trim().isEmpty) return null;
    final list = extractListFromRaw(el.outerHtml, rule, scope: el);
    if (list.isEmpty) return null;
    return list.length == 1 ? list.first : list.join('\n');
  }

  // ============================== JSON 级 ==============================

  /// 选取 JSON 列表节点
  List<dynamic> selectJsonNodes(dynamic root, String listRule) {
    if (listRule.trim().isEmpty) return root is List ? root : [];
    final first = _splitTop(listRule.trim(), ['||']).first.trim();
    final core = _splitPostProcess(first).selector;
    final r = JsonPath.select(root, _stripJsonPrefix(core));
    // `$.data` 直接命中数组字段时，select 会把整个数组作为单个命中值返回；
    // 列表规则需要的是数组里的每个节点，故展开一层。
    if (r.length == 1 && r[0] is List) {
      return List<dynamic>.from(r[0] as List);
    }
    return r;
  }

  /// 相对一个 JSON item 取字段
  String? fieldFromJson(dynamic item, String rule) {
    if (rule.trim().isEmpty) return null;
    var r = rule.trim();
    // @put: 只存变量不产出字段值；@get: 替换为变量值
    final puts = scanVarBlocks(r, '@put:');
    if (puts.isNotEmpty) {
      var rest = r;
      for (final b in puts.reversed) {
        rest = rest.substring(0, b.$1) + rest.substring(b.$2);
      }
      for (final b in puts) {
        for (final e in parsePutEntries(b.$3)) {
          variables[e.key] = _putValueFromJson(item, substituteGets(e.value));
        }
      }
      r = rest.trim();
      // put 移除后可能残留前导连接符
      while (r.startsWith('&&') || r.startsWith('||') || r.startsWith('%%')) {
        r = r.substring(2).trim();
      }
    }
    if (r.isEmpty) return null;
    // 整段即单个 @get:{...}：直接返回变量值
    final gets = scanVarBlocks(r, '@get:');
    if (gets.length == 1 && gets.single.$1 == 0 && gets.single.$2 == r.length) {
      final v = _readVariable(gets.single.$3);
      return v.isEmpty ? null : v;
    }
    r = substituteGets(r);
    final mode = _detectMode(r);
    final parsed = _splitPostProcess(r);
    String? value;
    if (mode == RuleMode.js || parsed.tailJs != null || r.contains('{{')) {
      // 允许 JS 直接处理 item
      final script = r.startsWith('@js:') ? r.substring(4) : parsed.selector;
      value = JsMiniEvaluator.eval(script,
          result: item is String ? item : jsonEncode(item),
          key: keyword, page: page, baseUrl: baseUrl);
    } else if (parsed.selector.isEmpty) {
      value = item?.toString();
    } else {
      final v = JsonPath.selectFirst(item, _stripJsonPrefix(parsed.selector));
      // 选中对象/数组时输出合法 JSON，标量转字符串
      value = v == null
          ? null
          : (v is Map || v is List ? jsonEncode(v) : v.toString());
    }
    if (value == null) return null;
    value = _applyPostOps(value, parsed.ops);
    final tail = parsed.tailJs;
    if (tail != null) {
      value = JsMiniEvaluator.eval(tail, result: value, key: keyword, page: page, baseUrl: baseUrl) ?? value;
    }
    return value.isEmpty ? null : value;
  }

  /// put 值按 JSON 规则求值：`<js>` 字面量直取；不像规则的纯文本按字面
  /// 处理；否则递归 [fieldFromJson] 对当前 item 求值。
  String _putValueFromJson(dynamic item, String valueRule) {
    final lit = jsLiteralValue(valueRule);
    if (lit != null) return lit;
    if (!looksLikeRule(valueRule)) return valueRule;
    return fieldFromJson(item, valueRule) ?? '';
  }

  // ===================== 供异步 JS 引擎复用的公共解析能力 =====================

  /// 解析字段规则为：选择器 / 后处理操作 / 尾部 JS / 是否含 mustache。
  FieldRuleParts parseFieldParts(String rule) {
    final p = _splitPostProcess(rule.trim());
    final ops = <FieldOp>[];
    for (final op in p.ops) {
      switch (op.kind) {
        case _OpKind.remove:
          ops.add(FieldOp('remove', op.pattern, null));
          break;
        case _OpKind.replace:
          ops.add(FieldOp('replace', op.pattern, op.replacement));
          break;
        case _OpKind.replaceFirst:
          ops.add(FieldOp('replaceFirst', op.pattern, op.replacement));
          break;
        case _OpKind.match:
          ops.add(FieldOp('match', op.pattern, null));
          break;
      }
    }
    return FieldRuleParts(
      selector: p.selector,
      ops: ops,
      tailJs: p.tailJs,
      hasInterpolation: p.hasInterpolation,
    );
  }

  /// 对取到的原始值执行 ## 后处理操作。
  String applyFieldOps(String value, List<FieldOp> ops) {
    final internal = ops.map((o) {
      switch (o.kind) {
        case 'replace':
          return _PostOp.replace(o.pattern, o.replacement ?? '');
        case 'replaceFirst':
          return _PostOp.replaceFirst(o.pattern, o.replacement ?? '');
        case 'match':
          return _PostOp.match(o.pattern);
        default:
          return _PostOp.remove(o.pattern);
      }
    }).toList();
    return _applyPostOps(value, internal);
  }

  /// 纯 JSONPath 选择（不含 JS），供引擎在 JS 之外复用。
  dynamic jsonPathFirst(dynamic node, String selector) {
    final s = selector.trim();
    if (s.isEmpty) return node?.toString();
    final v = JsonPath.selectFirst(node, _stripJsonPrefix(s));
    if (v == null) return null;
    return (v is Map || v is List) ? jsonEncode(v) : v.toString();
  }

  // ============================== 各模式实现 ==============================

  List<String> _cssValues(String raw, String rule) {
    final doc = html_parser.parse(raw);
    final clean = _stripCssPrefix(rule);
    // 分离最后一个顶层 @ 取值后缀
    final at = _lastTopAt(clean);
    final selector = at < 0 ? clean : clean.substring(0, at);
    final getter = at < 0 ? 'text' : clean.substring(at + 1);
    final elements = selector.isEmpty
        ? doc.querySelectorAll('*').where((e) => e.children.isEmpty).toList()
        : CssSelector.selectAll(doc, selector);
    return elements.map((e) => _getByGetter(e, getter)).where((s) => s.isNotEmpty).toList();
  }

  List<String> _xpathValues(String raw, String rule) {
    final doc = html_parser.parse(raw);
    return XpathSelector.selectTextFromNode(doc, _stripXPathPrefix(rule));
  }

  List<String> _defaultValues(String raw, String rule, {dom.Element? scope}) {
    final doc = html_parser.parse(raw);
    final steps = _splitSteps(rule);
    if (steps.isEmpty) return [];
    List<dom.Node> current;
    if (steps.length == 1 && scope != null) {
      // 无 @ 的裸规则（如 chapterUrl 的 "href"）：对齐 legado 语义 ——
      // getResultLast(elements=[当前元素], rule)，即对元素自身按规则取值，
      // 而不是把 outerHtml 重新解析后从 Document 根取（那会什么都取不到）。
      current = [scope];
    } else {
      current = [doc];
      for (var i = 0; i < steps.length - 1; i++) {
        final next = <dom.Element>[];
        for (final el in current) {
          next.addAll(_elementsSingle(el, steps[i]));
        }
        current = next;
        if (current.isEmpty) return [];
      }
    }
    final getter = steps.last;
    return current.whereType<dom.Element>().map((e) => _getByGetter(e, getter)).where((s) => s.isNotEmpty).toList();
  }

  /// 默认(JSoup)模式选取元素（不包含取值步骤）
  List<dom.Element> _defaultElements(dom.Node scope, String rule) {
    final steps = _splitSteps(rule);
    if (steps.isEmpty) return [];
    // 对齐 legado getElements：列表规则的每个 @ 段都是元素选择器并逐级下钻
    // （如 "td@a" 先选 td 再在其内选 a，最终返回 a 元素列表）。
    // 注意不能把最后一段当 getter 剥掉——那正是 "td@a 只返回 td" 的根因。
    List<dom.Node> current = [scope];
    for (final step in steps) {
      final next = <dom.Element>[];
      for (final el in current) {
        next.addAll(_elementsSingle(el, step));
      }
      current = next;
      if (current.isEmpty) break;
    }
    return current.whereType<dom.Element>().toList();
  }

  /// 单步选择：class.x / tag.x / id.x / text.x / children / 原生 CSS，支持 .N !N [索引]
  List<dom.Element> _elementsSingle(dom.Node temp, String step) {
    var rule = step.trim();
    if (rule.isEmpty) return _childrenOf(temp);

    // 提取尾部索引：.N / !N / :N / [..]
    final indexes = <int>[];
    var exclude = false;
    var before = rule;

    final bracket = RegExp(r'\[([^\]]*)\]$').firstMatch(rule);
    if (bracket != null) {
      before = rule.substring(0, bracket.start);
      final inner = bracket.group(1)!;
      if (inner.startsWith('!')) exclude = true;
      for (final part in inner.replaceFirst('!', '').split(',')) {
        final p = part.trim();
        if (p.isEmpty) continue;
        if (p.contains(':')) {
          final seg = p.split(':');
          final s = int.tryParse(seg[0]) ?? 0;
          final e = int.tryParse(seg[1]) ?? -1;
          for (var i = s; i <= e; i++) {
            indexes.add(i);
          }
        } else {
          final i = int.tryParse(p);
          if (i != null) indexes.add(i);
        }
      }
    } else {
      final tailIdx = RegExp(r'([.!:])(-?\d+)$').firstMatch(rule);
      if (tailIdx != null) {
        before = rule.substring(0, tailIdx.start);
        exclude = tailIdx.group(1) == '!';
        indexes.add(int.parse(tailIdx.group(2)!));
      }
    }

    List<dom.Element> elements;
    final parts = before.split('.');
    if (before.isEmpty || before == 'children') {
      elements = _childrenOf(temp);
    } else if (parts.length >= 2) {
      switch (parts[0]) {
        case 'class':
          elements = _byClassName(temp, parts.sublist(1).join('.'));
          break;
        case 'tag':
          elements = _byTagName(temp, parts[1]);
          break;
        case 'id':
          final el = temp is dom.Document ? temp.getElementById(parts[1]) : _getById(temp as dom.Element, parts[1]);
          elements = el == null ? [] : [el];
          break;
        case 'text':
          elements = CssSelector.selectAll(temp, '*')
              .where((e) => e.text.contains(parts.sublist(1).join('.')))
              .toList();
          break;
        default:
          elements = CssSelector.selectAll(temp, before);
      }
    } else {
      // 单个词当作原生 CSS（如 div.booklist / a.title）
      elements = CssSelector.selectAll(temp, before);
    }

    if (indexes.isEmpty) return elements;
    final picked = <dom.Element>[];
    for (var i in indexes) {
      final real = i < 0 ? elements.length + i : i;
      if (real >= 0 && real < elements.length) picked.add(elements[real]);
    }
    if (exclude) {
      final remove = picked.toSet();
      return elements.where((e) => !remove.contains(e)).toList();
    }
    return picked;
  }

  dom.Element? _getById(dom.Element root, String id) {
    for (final e in root.querySelectorAll('*')) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<dom.Element> _childrenOf(dom.Node n) {
    if (n is dom.Document) return n.documentElement?.children ?? const [];
    if (n is dom.Element) return n.children;
    return const [];
  }

  List<dom.Element> _byClassName(dom.Node n, String cls) {
    if (n is dom.Document) return n.getElementsByClassName(cls);
    if (n is dom.Element) return n.getElementsByClassName(cls);
    return const [];
  }

  List<dom.Element> _byTagName(dom.Node n, String tag) {
    if (n is dom.Document) return n.getElementsByTagName(tag);
    if (n is dom.Element) return n.getElementsByTagName(tag);
    return const [];
  }

  /// 按 getter 从元素取值
  String _getByGetter(dom.Element el, String getter) {
    switch (getter) {
      case 'text':
        return el.text.trim();
      case 'textNodes':
        return el.nodes
            .where((n) => n.nodeType == dom.Node.TEXT_NODE)
            .map((n) => n.text?.trim() ?? '')
            .where((s) => s.isNotEmpty)
            .join('\n');
      case 'ownText':
        return el.nodes
            .where((n) => n.nodeType == dom.Node.TEXT_NODE)
            .map((n) => n.text?.trim() ?? '')
            .join('')
            .trim();
      case 'html':
        el.querySelectorAll('script,style').forEach((e) => e.remove());
        return el.innerHtml.trim();
      case 'all':
      case 'outerHtml':
        return el.outerHtml.trim();
      default:
        if (getter.startsWith('attr:')) return el.attributes[getter.substring(5)] ?? '';
        // 属性名
        return el.attributes[getter] ?? el.text.trim();
    }
  }

  List<String> _jsonValues(String raw, String rule, bool forceJson) {
    dynamic json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return [];
    }
    final values = JsonPath.select(json, _stripJsonPrefix(rule));
    return values.map((e) => e == null ? '' : e.toString()).where((s) => s.isNotEmpty).toList();
  }

  List<String> _regexValues(String raw, String rule) {
    var pattern = rule.startsWith(':') ? rule.substring(1) : rule;
    // :正则$group 或 :正则!!序号
    int group = 0;
    final gm = RegExp(r'^(.*?)(?:\$(\d+)|!!(\d+))$', dotAll: true).firstMatch(pattern);
    if (gm != null) {
      pattern = gm.group(1)!;
      group = int.tryParse(gm.group(2) ?? gm.group(3) ?? '0') ?? 0;
    }
    final matches = RegExp(pattern, multiLine: true, dotAll: true).allMatches(raw);
    final out = <String>[];
    for (final m in matches) {
      final g = group <= m.groupCount ? m.group(group) : m.group(0);
      if (g != null && g.isNotEmpty) out.add(g);
    }
    return out;
  }

  // ============================== 后处理 ==============================

  _ParsedRule _splitPostProcess(String rule) {
    final result = _ParsedRule();
    // 提取结尾 @js:
    final jsIdx = _findTop(rule, '@js:');
    var body = rule;
    if (jsIdx >= 0) {
      result.tailJs = rule.substring(jsIdx + 4);
      body = rule.substring(0, jsIdx);
    }
    // 提取 <js></js> 结尾
    final wrap = RegExp(r'<js>([\s\S]*?)</js>$').firstMatch(body);
    if (wrap != null) {
      result.tailJs = wrap.group(1);
      body = body.substring(0, wrap.start);
    }
    result.hasInterpolation = body.contains('{{');
    // 切 ## 链（顶层）
    final parts = _splitByHash(body);
    result.selector = parts.first;
    for (var i = 1; i < parts.length;) {
      final p = parts[i];
      // 上游 `##match##replace###`：split("##") 得到 4 段，第 4 段存在即
      // replaceFirst = true（取第一个匹配文本并替换）。_splitByHash 会把
      // 结尾 `###` 的第三个 '#' 保留为单独一段 "#"，这里据此识别。
      if (p == '#' && i == parts.length - 1 && result.ops.isNotEmpty &&
          result.ops.last.kind == _OpKind.replace) {
        final prev = result.ops.removeLast();
        result.ops.add(
            _PostOp.replaceFirst(prev.pattern, prev.replacement ?? ''));
        i += 1;
      } else if (p.startsWith('#')) {
        // ###regex：只保留首个匹配（2 段形式，项目既有语义）
        final regex = p.substring(1);
        // 空正则会 firstMatch 到空串并把结果清空，属于无效操作，跳过
        if (regex.isNotEmpty) result.ops.add(_PostOp.match(regex));
        i += 1;
      } else if (i + 1 < parts.length) {
        result.ops.add(_PostOp.replace(p, parts[i + 1]));
        i += 2;
      } else {
        result.ops.add(_PostOp.remove(p));
        i += 1;
      }
    }
    return result;
  }

  String _applyPostOps(String value, List<_PostOp> ops) {
    var v = value;
    for (final op in ops) {
      switch (op.kind) {
        case _OpKind.remove:
          v = v.replaceAll(RegExp(op.pattern, multiLine: true, dotAll: true), '');
          break;
        case _OpKind.replace:
          v = RegexParser.replace(v, op.pattern, op.replacement!);
          break;
        case _OpKind.replaceFirst:
          // 上游 `##match##replace###`：取第一个匹配文本，再用同一正则对该
          // 文本替换一次；无匹配返回空串。等价于对首个 match 展开 $N 模板。
          final m =
              RegExp(op.pattern, multiLine: true, dotAll: true).firstMatch(v);
          if (m == null) {
            v = '';
          } else {
            var out = op.replacement!;
            for (var g = m.groupCount; g >= 0; g--) {
              out = out.replaceAll('\$$g', m.group(g) ?? '');
            }
            v = out;
          }
          break;
        case _OpKind.match:
          final m = RegExp(op.pattern, multiLine: true, dotAll: true).firstMatch(v);
          v = m?.group(0) ?? '';
          break;
      }
    }
    return v.trim();
  }

  /// 模板插值：'前缀{{脚本}}后缀'
  String _interpolate(String value, String? template) {
    if (template == null || !template.contains('{{')) return value;
    return template.replaceAllMapped(RegExp(r'\{\{([\s\S]*?)\}\}'), (m) {
      final script = m.group(1)!;
      return JsMiniEvaluator.eval(script, result: value, key: keyword, page: page, baseUrl: baseUrl) ?? '';
    });
  }

  // ============================== 工具方法 ==============================

  /// 公开的规则模式判定（委托 [_detectMode]），供离线兼容测试/调试页复用。
  RuleMode modeOf(String rule, {bool forceJson = false}) =>
      _detectMode(rule, forceJson: forceJson);

  RuleMode _detectMode(String rule, {bool forceJson = false}) {
    final r = rule.trim();
    if (r.toLowerCase().startsWith('@css:')) return RuleMode.css;
    if (r.toLowerCase().startsWith('@xpath:')) return RuleMode.xpath;
    if (r.toLowerCase().startsWith('@json:')) return RuleMode.json;
    if (r.toLowerCase().startsWith('@js:') || RegExp(r'^<js>[\s\S]*</js>$').hasMatch(r)) return RuleMode.js;
    if (r.startsWith(r'$.') || r.startsWith(r'$[')) return RuleMode.json;
    if (r.startsWith('//') || r.startsWith('/')) return RuleMode.xpath;
    if (r.startsWith(':') && RegExp(r'^:.+[\+\*\[\]\(\)\^\$]').hasMatch(r)) return RuleMode.regex;
    if (forceJson) return RuleMode.json;
    return RuleMode.defaultRule;
  }

  String _stripCssPrefix(String r) => r.toLowerCase().startsWith('@css:') ? r.substring(5) : r;
  String _stripXPathPrefix(String r) => r.toLowerCase().startsWith('@xpath:') ? r.substring(7) : r;
  String _stripJsonPrefix(String r) {
    final low = r.toLowerCase();
    if (low.startsWith('@json:')) return r.substring(6);
    return r;
  }

  bool _looksJson(String raw) {
    final t = raw.trim();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// 按 @ 拆分默认规则步骤（忽略属性选择器 [] 与引号内的 @）
  List<String> _splitSteps(String rule) {
    final parts = <String>[];
    final sb = StringBuffer();
    var depth = 0;
    var quote = '';
    for (var i = 0; i < rule.length; i++) {
      final c = rule[i];
      if (quote.isNotEmpty) {
        sb.write(c);
        if (c == quote) quote = '';
        continue;
      }
      if (c == "'" || c == '"') { quote = c; sb.write(c); continue; }
      if (c == '[' || c == '(') depth++;
      if (c == ']' || c == ')') depth--;
      if (c == '@' && depth == 0) {
        if (sb.isNotEmpty) parts.add(sb.toString());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
    if (sb.isNotEmpty) parts.add(sb.toString());
    return parts.where((p) => p.isNotEmpty).toList();
  }

  /// 找最后一个顶层 @（用于 CSS 的 getter 分离）
  int _lastTopAt(String rule) {
    var depth = 0;
    var quote = '';
    var idx = -1;
    for (var i = 0; i < rule.length; i++) {
      final c = rule[i];
      if (quote.isNotEmpty) { if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; continue; }
      if (c == '[' || c == '(') depth++;
      if (c == ']' || c == ')') depth--;
      if (c == '@' && depth == 0) idx = i;
    }
    return idx;
  }

  /// 顶层分隔（忽略 [](){} 与引号内部），返回各段
  List<String> _splitTop(String input, List<String> seps) {
    final result = <String>[];
    final sb = StringBuffer();
    var depth = 0;
    var quote = '';
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quote.isNotEmpty) { sb.write(c); if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; sb.write(c); continue; }
      if (c == '[' || c == '(' || c == '{') depth++;
      if (c == ']' || c == ')' || c == '}') depth--;
      String? matched;
      if (depth == 0) {
        for (final s in seps) {
          if (i + s.length <= input.length && input.substring(i, i + s.length) == s) {
            matched = s; break;
          }
        }
      }
      if (matched != null) {
        result.add(sb.toString());
        sb.clear();
        i += matched.length - 1;
      } else {
        sb.write(c);
      }
    }
    if (sb.isNotEmpty) result.add(sb.toString());
    return result;
  }

  /// 顶层按连接符拆分（忽略 `[](){}` 与引号内部），并保留每个分段右侧的连接符。
  /// 用于区分 `||` / `%%` / `&&` 三种不同语义的连接。
  List<_ConnectorSegment> _splitByConnectors(String input, List<String> seps) {
    final result = <_ConnectorSegment>[];
    final sb = StringBuffer();
    var depth = 0;
    var quote = '';
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quote.isNotEmpty) { sb.write(c); if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; sb.write(c); continue; }
      if (c == '[' || c == '(' || c == '{') depth++;
      if (c == ']' || c == ')' || c == '}') depth--;
      String? matched;
      if (depth == 0) {
        for (final s in seps) {
          if (i + s.length <= input.length && input.substring(i, i + s.length) == s) {
            matched = s; break;
          }
        }
      }
      if (matched != null) {
        result.add(_ConnectorSegment(sb.toString(), matched));
        sb.clear();
        i += matched.length - 1;
      } else {
        sb.write(c);
      }
    }
    result.add(_ConnectorSegment(sb.toString(), null));
    return result;
  }

  int _findTop(String input, String token) {
    var depth = 0;
    var quote = '';
    for (var i = 0; i <= input.length - token.length; i++) {
      final c = input[i];
      if (quote.isNotEmpty) { if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; continue; }
      if (c == '[' || c == '(' || c == '{') depth++;
      if (c == ']' || c == ')' || c == '}') depth--;
      if (depth == 0 && input.substring(i, i + token.length) == token) return i;
    }
    return -1;
  }

  /// 按 ## 切分（顶层；不拆引号/括号内）
  List<String> _splitByHash(String input) {
    final result = <String>[];
    final sb = StringBuffer();
    var depth = 0;
    var quote = '';
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quote.isNotEmpty) { sb.write(c); if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; sb.write(c); continue; }
      if (c == '[' || c == '(' || c == '{') depth++;
      if (c == ']' || c == ')' || c == '}') depth--;
      if (depth == 0 && i + 1 < input.length && c == '#' && input[i + 1] == '#') {
        result.add(sb.toString());
        sb.clear();
        i++;
        // 三 #：###regex 保留一个前导 # 到下一段
        if (i + 1 < input.length && input[i + 1] == '#') {
          sb.write('#');
          i++;
        }
      } else {
        sb.write(c);
      }
    }
    result.add(sb.toString());
    return result;
  }

  List<String> _nullEmpty(String? s) => (s == null || s.isEmpty) ? [] : [s];
}

class _ParsedRule {
  String selector = '';
  final List<_PostOp> ops = [];
  String? tailJs;
  bool hasInterpolation = false;
}

/// 连接符拆分结果：一段规则文本与其右侧紧随的连接符（`||` / `%%` / `&&`）。
class _ConnectorSegment {
  _ConnectorSegment(this.text, this.sep);
  final String text;
  final String? sep;
}

/// 字段规则拆解结果（供异步 JS 引擎使用）。
class FieldRuleParts {
  FieldRuleParts({
    required this.selector,
    required this.ops,
    this.tailJs,
    this.hasInterpolation = false,
  });
  String selector;
  final List<FieldOp> ops;
  String? tailJs;
  bool hasInterpolation;
}

class FieldOp {
  FieldOp(this.kind, this.pattern, this.replacement);
  final String kind; // remove / replace / match
  final String pattern;
  final String? replacement;
}

enum _OpKind { remove, replace, replaceFirst, match }

class _PostOp {
  final _OpKind kind;
  final String pattern;
  final String? replacement;
  _PostOp._(this.kind, this.pattern, this.replacement);
  factory _PostOp.remove(String p) => _PostOp._(_OpKind.remove, p, null);
  factory _PostOp.replace(String p, String r) => _PostOp._(_OpKind.replace, p, r);

  /// 上游 `##match##replace###`：第 4 段触发 replaceFirst。
  factory _PostOp.replaceFirst(String p, String r) =>
      _PostOp._(_OpKind.replaceFirst, p, r);

  factory _PostOp.match(String p) => _PostOp._(_OpKind.match, p, null);
}

