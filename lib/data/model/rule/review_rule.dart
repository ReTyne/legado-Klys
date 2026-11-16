// ignore_for_file: use_super_parameters

import 'rule_base.dart';

/// 段评 / 书评规则。
class ReviewRule extends RuleBase {
  final String reviewUrl;
  final String avatarRule;
  final String contentRule;
  final String postTimeRule;
  final String reviewQuoteUrl;
  final String voteUpUrl;
  final String voteDownUrl;
  final String postReviewUrl;
  final String postQuoteUrl;
  final String deleteUrl;

  ReviewRule.fromRaw(Map<String, dynamic> raw)
      : reviewUrl = RuleBase.str(raw, 'reviewUrl'),
        avatarRule = RuleBase.str(raw, 'avatarRule'),
        contentRule = RuleBase.str(raw, 'contentRule'),
        postTimeRule = RuleBase.str(raw, 'postTimeRule'),
        reviewQuoteUrl = RuleBase.str(raw, 'reviewQuoteUrl'),
        voteUpUrl = RuleBase.str(raw, 'voteUpUrl'),
        voteDownUrl = RuleBase.str(raw, 'voteDownUrl'),
        postReviewUrl = RuleBase.str(raw, 'postReviewUrl'),
        postQuoteUrl = RuleBase.str(raw, 'postQuoteUrl'),
        deleteUrl = RuleBase.str(raw, 'deleteUrl'),
        super(raw);

  factory ReviewRule.fromJson(dynamic source) =>
      ReviewRule.fromRaw(RuleBase.asMap(source));

  @override
  Map<String, String> get fieldValues => <String, String>{
        'reviewUrl': reviewUrl,
        'avatarRule': avatarRule,
        'contentRule': contentRule,
        'postTimeRule': postTimeRule,
        'reviewQuoteUrl': reviewQuoteUrl,
        'voteUpUrl': voteUpUrl,
        'voteDownUrl': voteDownUrl,
        'postReviewUrl': postReviewUrl,
        'postQuoteUrl': postQuoteUrl,
        'deleteUrl': deleteUrl,
      };
}
