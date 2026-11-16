// ignore_for_file: use_super_parameters

import 'rule_base.dart';

/// 目录规则。
class TocRule extends RuleBase {
  final String preUpdateJs;
  final String chapterList;
  final String chapterName;
  final String chapterUrl;
  final String formatJs;
  final String isVolume;
  final String isVip;
  final String isPay;
  final String updateTime;
  final String nextTocUrl;

  TocRule.fromRaw(Map<String, dynamic> raw)
      : preUpdateJs = RuleBase.str(raw, 'preUpdateJs'),
        chapterList = RuleBase.str(raw, 'chapterList'),
        chapterName = RuleBase.str(raw, 'chapterName'),
        chapterUrl = RuleBase.str(raw, 'chapterUrl'),
        formatJs = RuleBase.str(raw, 'formatJs'),
        isVolume = RuleBase.str(raw, 'isVolume'),
        isVip = RuleBase.str(raw, 'isVip'),
        isPay = RuleBase.str(raw, 'isPay'),
        updateTime = RuleBase.str(raw, 'updateTime'),
        nextTocUrl = RuleBase.str(raw, 'nextTocUrl'),
        super(raw);

  factory TocRule.fromJson(dynamic source) =>
      TocRule.fromRaw(RuleBase.asMap(source));

  @override
  Map<String, String> get fieldValues => <String, String>{
        'preUpdateJs': preUpdateJs,
        'chapterList': chapterList,
        'chapterName': chapterName,
        'chapterUrl': chapterUrl,
        'formatJs': formatJs,
        'isVolume': isVolume,
        'isVip': isVip,
        'isPay': isPay,
        'updateTime': updateTime,
        'nextTocUrl': nextTocUrl,
      };
}
