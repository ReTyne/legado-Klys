// ignore_for_file: use_super_parameters

import 'book_list_rule.dart';
import 'rule_base.dart';

/// 搜索规则：在书籍列表规则基础上增加搜索关键字规则。
class SearchRule extends BookListRule {
  final String checkKeyWord;

  SearchRule.fromRaw(Map<String, dynamic> raw)
      : checkKeyWord = RuleBase.str(raw, 'checkKeyWord'),
        super.fromRaw(raw);

  factory SearchRule.fromJson(dynamic source) =>
      SearchRule.fromRaw(RuleBase.asMap(source));

  @override
  Map<String, String> get fieldValues => <String, String>{
        ...super.fieldValues,
        'checkKeyWord': checkKeyWord,
      };
}
