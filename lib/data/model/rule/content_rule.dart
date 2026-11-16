// ignore_for_file: use_super_parameters

import 'rule_base.dart';

/// 正文规则。
class ContentRule extends RuleBase {
  final String content;
  final String subContent;
  final String title;
  final String nextContentUrl;
  final String webJs;
  final String sourceRegex;
  final String replaceRegex;
  final String imageStyle;
  final String imageDecode;
  final String payAction;
  final String callBackJs;

  ContentRule.fromRaw(Map<String, dynamic> raw)
      : content = RuleBase.str(raw, 'content'),
        subContent = RuleBase.str(raw, 'subContent'),
        title = RuleBase.str(raw, 'title'),
        nextContentUrl = RuleBase.str(raw, 'nextContentUrl'),
        webJs = RuleBase.str(raw, 'webJs'),
        sourceRegex = RuleBase.str(raw, 'sourceRegex'),
        replaceRegex = RuleBase.str(raw, 'replaceRegex'),
        imageStyle = RuleBase.str(raw, 'imageStyle'),
        imageDecode = RuleBase.str(raw, 'imageDecode'),
        payAction = RuleBase.str(raw, 'payAction'),
        callBackJs = RuleBase.str(raw, 'callBackJs'),
        super(raw);

  factory ContentRule.fromJson(dynamic source) =>
      ContentRule.fromRaw(RuleBase.asMap(source));

  @override
  Map<String, String> get fieldValues => <String, String>{
        'content': content,
        'subContent': subContent,
        'title': title,
        'nextContentUrl': nextContentUrl,
        'webJs': webJs,
        'sourceRegex': sourceRegex,
        'replaceRegex': replaceRegex,
        'imageStyle': imageStyle,
        'imageDecode': imageDecode,
        'payAction': payAction,
        'callBackJs': callBackJs,
      };
}
