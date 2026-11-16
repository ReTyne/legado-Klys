// ignore_for_file: use_super_parameters

import 'rule_base.dart';

/// 书籍列表规则（搜索 / 发现 / 榜单共用的基础字段集）。
class BookListRule extends RuleBase {
  final String bookList;
  final String name;
  final String author;
  final String intro;
  final String kind;
  final String lastChapter;
  final String updateTime;
  final String bookUrl;
  final String coverUrl;
  final String wordCount;

  BookListRule.fromRaw(Map<String, dynamic> raw)
      : bookList = RuleBase.str(raw, 'bookList'),
        name = RuleBase.str(raw, 'name'),
        author = RuleBase.str(raw, 'author'),
        intro = RuleBase.str(raw, 'intro'),
        kind = RuleBase.str(raw, 'kind'),
        lastChapter = RuleBase.str(raw, 'lastChapter'),
        updateTime = RuleBase.str(raw, 'updateTime'),
        bookUrl = RuleBase.str(raw, 'bookUrl'),
        coverUrl = RuleBase.str(raw, 'coverUrl'),
        wordCount = RuleBase.str(raw, 'wordCount'),
        super(raw);

  factory BookListRule.fromJson(dynamic source) =>
      BookListRule.fromRaw(RuleBase.asMap(source));

  @override
  Map<String, String> get fieldValues => <String, String>{
        'bookList': bookList,
        'name': name,
        'author': author,
        'intro': intro,
        'kind': kind,
        'lastChapter': lastChapter,
        'updateTime': updateTime,
        'bookUrl': bookUrl,
        'coverUrl': coverUrl,
        'wordCount': wordCount,
      };
}
