import '../../data/model/replace_rule.dart';

/// 替换净化规则仓库接口
abstract class ReplaceRuleRepository {
  Future<List<ReplaceRule>> getReplaceRules();
  Future<void> insertReplaceRule(ReplaceRule rule);
  Future<void> updateReplaceRule(ReplaceRule rule);
  Future<void> deleteReplaceRule(int id);
}
