import '../../domain/repository/replace_rule_repository.dart';
import '../../data/model/replace_rule.dart';
import '../local/app_database.dart';

class ReplaceRuleRepositoryImpl implements ReplaceRuleRepository {
  final DatabaseService _db;
  ReplaceRuleRepositoryImpl([DatabaseService? db]) : _db = db ?? DatabaseService();

  @override
  Future<List<ReplaceRule>> getReplaceRules() => _db.getReplaceRules();
  @override
  Future<void> insertReplaceRule(ReplaceRule rule) => _db.insertReplaceRule(rule);
  @override
  Future<void> updateReplaceRule(ReplaceRule rule) => _db.updateReplaceRule(rule);
  @override
  Future<void> deleteReplaceRule(int id) => _db.deleteReplaceRule(id);
}
