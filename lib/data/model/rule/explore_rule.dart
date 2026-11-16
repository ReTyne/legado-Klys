// ignore_for_file: use_super_parameters

import 'book_list_rule.dart';
import 'rule_base.dart';

/// 发现规则：字段集与书籍列表规则一致。
class ExploreRule extends BookListRule {
  ExploreRule.fromRaw(Map<String, dynamic> raw) : super.fromRaw(raw);

  factory ExploreRule.fromJson(dynamic source) =>
      ExploreRule.fromRaw(RuleBase.asMap(source));
}
