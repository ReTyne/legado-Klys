// ignore_for_file: use_super_parameters

import 'rule_base.dart';

/// 书籍详情规则。
class BookInfoRule extends RuleBase {
  final String init;
  final String name;
  final String author;
  final String intro;
  final String kind;
  final String lastChapter;
  final String updateTime;
  final String coverUrl;
  final String tocUrl;
  final String wordCount;
  final String canReName;
  final String downloadUrls;

  BookInfoRule.fromRaw(Map<String, dynamic> raw)
      : init = RuleBase.str(raw, 'init'),
        name = RuleBase.str(raw, 'name'),
        author = RuleBase.str(raw, 'author'),
        intro = RuleBase.str(raw, 'intro'),
        kind = RuleBase.str(raw, 'kind'),
        lastChapter = RuleBase.str(raw, 'lastChapter'),
        updateTime = RuleBase.str(raw, 'updateTime'),
        coverUrl = RuleBase.str(raw, 'coverUrl'),
        tocUrl = RuleBase.str(raw, 'tocUrl'),
        wordCount = RuleBase.str(raw, 'wordCount'),
        canReName = RuleBase.str(raw, 'canReName'),
        downloadUrls = RuleBase.str(raw, 'downloadUrls'),
        super(raw);

  factory BookInfoRule.fromJson(dynamic source) =>
      BookInfoRule.fromRaw(RuleBase.asMap(source));

  @override
  Map<String, String> get fieldValues => <String, String>{
        'init': init,
        'name': name,
        'author': author,
        'intro': intro,
        'kind': kind,
        'lastChapter': lastChapter,
        'updateTime': updateTime,
        'coverUrl': coverUrl,
        'tocUrl': tocUrl,
        'wordCount': wordCount,
        'canReName': canReName,
        'downloadUrls': downloadUrls,
      };
}
