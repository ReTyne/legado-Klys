import 'dart:convert';

import 'package:legado_md3/help/source/rule_pipeline.dart';

/// 书源规则统一变量存储。
///
/// 读取按层级优先级 `chapter → book → ruleData → source` 依次查找，
/// 命中第一个非空值即返回；写入默认落到 `ruleData` 层。`ruleData` 层可
/// 通过 [bindVariableMap] 直接绑定到某个 [RulePipeline.variables]，从而
/// 让 `@put:`/`@get:` 规则变量与 JS 桥的 `java.get`/`java.put`、
/// `source.get`/`source.put` 读写同一份 Map。
///
/// 长度达到 [bigValueThreshold] 的值额外进入外置大变量存储，避免大文本
/// 混入常规变量导出。[variableMap] 合并所有层（高层覆盖低层）后可直接
/// 用 [variableMapJson] 导出为 JSON。
class RuleData {
  RuleData();

  /// 值达到该长度即视为「大变量」并写入外置存储。
  static const int bigValueThreshold = 10000;

  /// 可写入的层级名（读优先序即此顺序）。
  static const List<String> layerNames = <String>[
    'chapter',
    'book',
    'ruleData',
    'source',
  ];

  final Map<String, String> _chapter = <String, String>{};
  final Map<String, String> _book = <String, String>{};
  final Map<String, String> _ruleData = <String, String>{};
  final Map<String, String> _source = <String, String>{};
  final Map<String, String> _big = <String, String>{};

  Map<String, String>? _boundMap;

  /// 当前生效的 ruleData 层；绑定后即 [RulePipeline.variables] 本身。
  Map<String, String> get ruleDataLayer => _boundMap ?? _ruleData;

  /// 把 ruleData 层绑定到某份外部 Map（共享同一引用，而非拷贝）。
  void bindVariableMap(Map<String, String> map) => _boundMap = map;

  /// 解除绑定，恢复使用内部 ruleData 层。
  void unbind() => _boundMap = null;

  bool get isBound => _boundMap != null;

  Map<String, String> _layerMap(String layer) {
    switch (layer) {
      case 'chapter':
        return _chapter;
      case 'book':
        return _book;
      case 'source':
        return _source;
      case 'ruleData':
      default:
        return ruleDataLayer;
    }
  }

  /// 写入变量，默认写 ruleData 层。短值与超长值互斥存放：短值只写分层表并从
  /// 外置大变量存储移除，超长值只写外置存储并从所有分层移除。
  /// [value] 为 null 或空串时删除该 key。
  void putVariable(String key, String? value, {String layer = 'ruleData'}) {
    if (key.isEmpty) return;
    final allLayers = <Map<String, String>>[
      _chapter,
      _book,
      ruleDataLayer,
      _source,
    ];
    if (value == null) {
      // 删除：从外置存储与所有分层移除。
      _big.remove(key);
      for (final m in allLayers) {
        m.remove(key);
      }
      return;
    }
    if (value.isEmpty) {
      // 空值写入目标层；读取时按空跳过，实现向下一层回退。
      _big.remove(key);
      _layerMap(layer)[key] = '';
      return;
    }
    if (value.length >= bigValueThreshold) {
      // 长值：先从所有层移除，避免旧短值与新大值并存。
      for (final m in allLayers) {
        m.remove(key);
      }
      _big[key] = value;
    } else {
      // 短值：先清外置大变量，避免旧大值永久遮蔽新值。
      _big.remove(key);
      _layerMap(layer)[key] = value;
    }
  }

  /// 按 chapter → book → ruleData → source 读取，返回第一个非空值。
  String getVariable(String key) {
    final big = _big[key];
    if (big != null && big.isNotEmpty) return big;
    for (final m in <Map<String, String>>[
      _chapter,
      _book,
      ruleDataLayer,
      _source,
    ]) {
      final v = m[key];
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  /// 显式写入外置大变量存储。
  void putBigVariable(String key, String value) {
    if (key.isEmpty) return;
    _big[key] = value;
  }

  /// 读取外置大变量；缺失时回退到分层读取。
  String getBigVariable(String key) {
    final v = _big[key];
    return (v != null && v.isNotEmpty) ? v : getVariable(key);
  }

  /// 合并后的变量表（source → ruleData → book → chapter 依次覆盖，大变量最后覆盖）。
  Map<String, String> get variableMap {
    final merged = <String, String>{};
    for (final m in <Map<String, String>>[
      _source,
      ruleDataLayer,
      _book,
      _chapter,
    ]) {
      merged.addAll(m);
    }
    merged.addAll(_big);
    return merged;
  }

  /// 合并变量表导出为 JSON 字符串。
  String get variableMapJson => jsonEncode(variableMap);

  /// 面向 JS 桥的简化读（`java.get` / `source.get`）。
  String get(String key) => getVariable(key);

  /// 面向 JS 桥的简化写（`java.put` / `source.put`）。
  void put(String key, String value) => putVariable(key, value);

  /// 向指定层写入（供引擎按书籍/章节作用域预置变量）。
  void putInLayer(String layer, String key, String value) =>
      putVariable(key, value, layer: layer);

  /// 指定层的只读快照。
  Map<String, String> layerSnapshot(String layer) =>
      Map<String, String>.unmodifiable(_layerMap(layer));

  /// 清空所有层与外置大变量；绑定中的共享 Map 也一并清空。
  void clear() {
    _chapter.clear();
    _book.clear();
    _ruleData.clear();
    _source.clear();
    _big.clear();
    _boundMap?.clear();
  }

  // ==================== 供引擎 / JS 桥接线的静态接口 ====================

  /// 把当前会话存储与某个 [RulePipeline] 的变量表共享（同一 Map 引用）。
  /// 引擎在建立 pipeline 后调用一次即可。
  static void bindToPipeline(RulePipeline pipeline) {
    RuleDataScope.current.bindVariableMap(pipeline.variables);
  }

  /// JS 桥读取变量：优先分层存储，回退到 pipeline 变量表。
  static String readForJs(RulePipeline pipeline, String key) {
    final v = RuleDataScope.current.getVariable(key);
    if (v.isNotEmpty) return v;
    return pipeline.variables[key] ?? '';
  }

  /// JS 桥写入变量：写入分层存储并同步到 pipeline 变量表，保持共享。
  static void writeForJs(RulePipeline pipeline, String key, String value) {
    RuleDataScope.current.putVariable(key, value);
    pipeline.variables[key] = value;
  }

  /// 供 JS 桥直接读写同一份变量表；调用时顺便确保已与 pipeline 绑定。
  static Map<String, String> storageForJs(RulePipeline pipeline) {
    bindToPipeline(pipeline);
    return pipeline.variables;
  }
}

/// 当前会话作用域的 [RuleData] 管理。
///
/// 每次新的书籍/书源操作入口可调用 [begin] 开新会话；[current] 惰性创建
/// 默认会话，供未显式 begin 的场景使用。
class RuleDataScope {
  RuleDataScope._();

  static RuleData? _current;

  /// 当前会话的变量存储（惰性创建）。
  static RuleData get current => _current ??= RuleData();

  /// 开启一个新会话并返回其存储。
  static RuleData begin() {
    _current = RuleData();
    return _current!;
  }

  /// 用外部实例替换当前会话（测试或自定义作用域时使用）。
  static void attach(RuleData data) => _current = data;

  /// 丢弃当前会话（下次访问 [current] 会创建新的）。
  static void reset() => _current = null;
}
