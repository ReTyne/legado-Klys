import 'dart:async';
import 'dart:isolate';

import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/help/source/js_mini_eval.dart';
import 'package:legado_md3/utils/regex_timeout.dart';

/// `@js:` 替换的求值回调。
///
/// - [script]：`@js:` 之后的纯 JS 文本；
/// - [match]：本次命中的完整文本（第 0 组）；
/// - [groups]：捕获组列表，[groups[0]] 为完整命中，[groups[1]].. 为 $1..。
/// 返回 null 表示「当前没有可用的 JS 运行时」，调用方据此安全降级为原值。
typedef JsReplacementEvaluator = String? Function(
    String script, String match, List<String> groups);

/// 单条替换超出预算时抛出的内部信号（同步路径的协作式超时）。
class _ReplaceTimeout implements Exception {
  const _ReplaceTimeout();
}

/// 替换净化规则服务。
///
/// 在「按 order 依次应用」的基础上补齐：
/// - 正则替换的 `$1..$9` 分组展开；
/// - `@js:` 前缀的 JS 替换（无运行时安全降级 + 记日志）；
/// - 作用范围判定（书名 / 章节 / 目录 / 正文上下文 + `scope` / `excludeScope` / `group`）；
/// - `isRegex` / `isTitle` / `isContent` 三个开关生效；
/// - 超时保护（同步协作式看门狗 + 异步 isolate 超时，超时返回原文）。
class ReplaceRuleService {
  ReplaceRuleService([List<ReplaceRule>? rules])
      : _rules = <ReplaceRule>[...?rules];

  final List<ReplaceRule> _rules;

  List<ReplaceRule> get rules => List.unmodifiable(_rules);

  set rules(List<ReplaceRule> value) {
    _rules
      ..clear()
      ..addAll(value);
  }

  /// 可选日志回调；[debugLog] 会留存降级 / 超时记录，便于排查与验证。
  static void Function(String message)? logger;
  static final List<String> debugLog = <String>[];

  static void _log(String message) {
    debugLog.add(message);
    logger?.call(message);
  }

  static void clearDebugLog() => debugLog.clear();

  /// 应用本服务持有的全部规则。
  ///
  /// [scope] 为本次操作的上下文：既可以是书名 / 书源 origin，也可以是
  /// `content` / `title` / `toc` 等段落标识（决定走 isContent 还是 isTitle 通道）。
  /// [bookName] / [chapterName] / [group] 一并参与 scope / excludeScope 匹配。
  String apply(
    String text, {
    required String scope,
    String? bookName,
    String? chapterName,
    String? group,
    bool? isTitle,
    Duration? timeout,
    bool jsEnabled = true,
    JsReplacementEvaluator? jsEval,
  }) {
    return applyRules(
      text,
      _rules,
      scope: scope,
      bookName: bookName,
      chapterName: chapterName,
      group: group,
      isTitle: isTitle ?? _isTitleScope(scope),
      timeout: timeout,
      jsEnabled: jsEnabled,
      jsEval: jsEval,
    );
  }

  /// 批量按 `order` 升序应用规则（保持既有公开签名，新增参数均为可选）。
  String applyRules(
    String text,
    List<ReplaceRule> rules, {
    String? scope,
    String? name,
    bool isTitle = false,
    String? bookName,
    String? chapterName,
    String? group,
    Duration? timeout,
    bool jsEnabled = true,
    JsReplacementEvaluator? jsEval,
  }) {
    if (rules.isEmpty) return text;
    final context = _context(scope, name, bookName, chapterName, group);
    final list = <ReplaceRule>[...rules]
      ..sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));
    var result = text;
    for (final rule in list) {
      if (!_isApplicable(rule, context, isTitle)) continue;
      result = _runReplace(
        result,
        rule,
        timeout: timeout,
        jsEnabled: jsEnabled,
        jsEval: jsEval,
      );
    }
    return result;
  }

  /// 异步版：把正则替换放进独立 isolate 并加超时，真正阻断灾难性回溯。
  /// 复用 `regex_timeout.dart` 的 `validTimeoutMillisecond` 与
  /// `replaceRegexWithTimeout`；超时或异常时该规则返回原文、继续下一条。
  Future<String> applyRulesAsync(
    String text,
    List<ReplaceRule> rules, {
    String? scope,
    String? name,
    bool isTitle = false,
    String? bookName,
    String? chapterName,
    String? group,
    int timeoutMillisecond = 3000,
    bool jsEnabled = true,
  }) async {
    if (rules.isEmpty) return text;
    final context = _context(scope, name, bookName, chapterName, group);
    final list = <ReplaceRule>[...rules]
      ..sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));
    final ms = validTimeoutMillisecond(timeoutMillisecond);
    var result = text;
    for (final rule in list) {
      if (!_isApplicable(rule, context, isTitle)) continue;
      final plainRegex = rule.isRegex &&
          !rule.replacement.contains(r'$') &&
          !_isJs(rule.replacement);
      try {
        if (plainRegex) {
          result = await replaceRegexWithTimeout(
            input: result,
            pattern: rule.replaceRule,
            replacement: rule.replacement,
            isRegex: true,
            timeoutMillisecond: ms,
            ruleName: rule.replaceSummary,
          );
        } else {
          // 含分组 / @js: 的动态替换也放进 isolate，避免阻塞主 isolate。
          final ruleCopy = rule;
          final input = result;
          result = await Isolate.run<String>(() {
            return ReplaceRuleService([])._runReplace(
              input,
              ruleCopy,
              timeout: Duration(milliseconds: ms),
              jsEnabled: jsEnabled,
            );
          }).timeout(Duration(milliseconds: ms + 500));
        }
      } on TimeoutException {
        _log('替换超时(${ms}ms)，返回原文：${rule.replaceSummary}');
      } catch (e) {
        _log('替换异常，保留原文：${rule.replaceSummary} / $e');
      }
    }
    return result;
  }

  // ============================ 作用范围 ============================

  static List<String> _context(
    String? scope,
    String? name,
    String? bookName,
    String? chapterName,
    String? group,
  ) {
    return <String?>[scope, name, bookName, chapterName, group]
        .where((e) => e != null && e.trim().isNotEmpty)
        .map((e) => e!.trim())
        .toSet()
        .toList();
  }

  /// 段落标识 → 是否走 isTitle 通道。
  static bool _isTitleScope(String scope) {
    const titleScopes = <String>{
      'title',
      'toc',
      'toc_title',
      'chapter',
      'chaptertitle',
      '目录',
      '章节',
      '标题',
    };
    return titleScopes.contains(scope.trim().toLowerCase());
  }

  bool _isApplicable(ReplaceRule rule, List<String> context, bool isTitle) {
    if (rule.enable != true) return false;
    if (!rule.isValid()) return false;
    // isTitle / isContent 分通道
    if (isTitle ? !rule.isTitle : !rule.isContent) return false;
    // excludeScope 命中任一上下文即排除
    if (_anyMatch(rule.excludeScope, context)) return false;
    final scopeText = rule.scope?.trim() ?? '';
    if (scopeText.isEmpty || scopeText == 'all') return true;
    // scope 或 group 任一命中上下文即生效（两个方向都接受，兼容历史规则）。
    return _anyMatch(rule.scope, context) || _anyMatch(rule.group, context);
  }

  /// 两个方向都接受：规则串含上下文，或上下文含规则串。
  static bool _anyMatch(String? pattern, List<String> context) {
    if (pattern == null) return false;
    final p = pattern.trim();
    if (p.isEmpty) return false;
    for (final c in context) {
      if (p.contains(c) || c.contains(p)) return true;
    }
    return false;
  }

  // ============================ 替换执行 ============================

  /// 单条规则替换，含 `$1..$9` 展开、`@js:` 求值、超时看门狗。
  /// 任何异常都返回 [text]，保证净化链路不被单条坏规则打断。
  String _runReplace(
    String text,
    ReplaceRule rule, {
    Duration? timeout,
    required bool jsEnabled,
    JsReplacementEvaluator? jsEval,
  }) {
    if (rule.replaceRule.isEmpty) return text;
    final ms = timeout != null
        ? timeout.inMilliseconds
        : validTimeoutMillisecond(rule.validTimeoutMillisecond);
    if (ms <= 0) {
      _log('替换超时(${ms}ms)，返回原文：${rule.replaceSummary}');
      return text;
    }
    RegExp re;
    try {
      re = rule.isRegex
          ? RegExp(rule.replaceRule)
          : RegExp(RegExp.escape(rule.replaceRule));
    } catch (_) {
      return text;
    }
    final sw = Stopwatch()..start();
    String produce(Match m) {
      if (sw.elapsedMilliseconds > ms) throw const _ReplaceTimeout();
      return _replacementFor(rule, m, jsEnabled, jsEval);
    }

    try {
      return text.replaceAllMapped(re, produce);
    } on _ReplaceTimeout {
      _log('替换超时(${ms}ms)，返回原文：${rule.replaceSummary}');
      return text;
    } catch (_) {
      return text;
    }
  }

  String _replacementFor(
    ReplaceRule rule,
    Match m,
    bool jsEnabled,
    JsReplacementEvaluator? jsEval,
  ) {
    final repl = rule.replacement;
    if (_isJs(repl)) {
      final script = repl.trim().substring(4).trim();
      final full = m.group(0) ?? '';
      final groups = <String>[
        for (var i = 0; i <= m.groupCount; i++) m.group(i) ?? '',
      ];
      String? out;
      if (jsEval != null) {
        out = jsEval(script, full, groups);
      } else if (jsEnabled) {
        out = _defaultJsEval(script, full);
      }
      if (out == null) {
        _log('@js: 替换无可用 JS 运行时，降级保留原值：$full');
        return full;
      }
      return out;
    }
    return _expandGroups(repl, m);
  }

  /// `$1..$9`（以及 `$0` 完整命中）分组捕获展开。
  static String _expandGroups(String template, Match m) {
    if (!template.contains(r'$')) return template;
    return template.replaceAllMapped(RegExp(r'\$(\d)'), (g) {
      final idx = int.parse(g.group(1)!);
      if (idx == 0) return m.group(0) ?? '';
      if (idx <= m.groupCount) return m.group(idx) ?? '';
      // 越界的 $N 保留字面量，避免误清空。
      return g.group(0)!;
    });
  }

  static bool _isJs(String repl) =>
      repl.trim().toLowerCase().startsWith('@js:');

  /// 默认 JS 求值：走项目内置的轻量 JS 子集求值器。
  /// 简单表达式（`result.replace(...)` / `result + 'x'`）自动赋值到 result；
  /// 求值器无法覆盖时返回 null，由调用方降级为原值。
  static String? _defaultJsEval(String script, String result) {
    var code = script.trim();
    if (code.isEmpty) return null;
    final hasAssignment = RegExp(r'\bresult\s*=[^=]').hasMatch(code) ||
        code.contains('return') ||
        code.contains(';');
    if (!hasAssignment) code = 'result = $code';
    return JsMiniEvaluator.eval(code, result: result);
  }

  // ============================ 单规则测试 ============================

  /// 测试单条规则（同步，不做超时）。
  String testRule(String text, ReplaceRule rule) {
    if (!rule.isValid()) {
      return '规则无效：匹配内容为空、正则语法错误或以未转义的 | 结尾';
    }
    return _runReplace(
      text,
      rule,
      timeout: const Duration(days: 1),
      jsEnabled: true,
    );
  }

  /// 把替换放进独立 isolate 并按规则超时保护，防止劣质正则卡死主 isolate。
  Future<String> testRuleWithTimeout(String text, ReplaceRule rule) async {
    if (!rule.isValid()) return testRule(text, rule);
    final ms = rule.validTimeoutMillisecond;
    final ruleCopy = rule;
    try {
      return await Isolate.run<String>(() {
        return ReplaceRuleService([])._runReplace(
          text,
          ruleCopy,
          timeout: Duration(milliseconds: ms),
          jsEnabled: true,
        );
      }).timeout(Duration(milliseconds: ms));
    } on TimeoutException {
      return '替换超时（${ms}ms），请检查正则表达式';
    } catch (e) {
      return '替换失败: $e';
    }
  }

  // ============================ 跨端 JSON ============================

  /// 从 JSON 导入规则，兼容字段名与本项目历史字段名，不丢字段。
  static List<ReplaceRule> fromJson(List<dynamic> jsonList) => jsonList
      .map((json) => json is Map
          ? ReplaceRule.fromMap(Map<String, dynamic>.from(json))
          : null)
      .whereType<ReplaceRule>()
      .toList();

  /// 导出为跨端兼容 JSON（保留 group / excludeScope / timeoutMillisecond）。
  static List<Map<String, dynamic>> toJson(List<ReplaceRule> rules) =>
      rules.map((r) => r.toLegadoJson()).toList();
}
