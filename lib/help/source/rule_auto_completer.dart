import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

part 'parts/auto_page_result.dart';
part 'parts/rule_auto_completer.dart';
part 'parts/block.dart';
part 'parts/first_or_null.dart';


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
