import '../local/app_database.dart';
import '../model/replace_rule.dart';

class ReplaceRuleDao {
  final DatabaseService _db;
  ReplaceRuleDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<ReplaceRule>> getAll() => _db.getReplaceRules();
  Future<void> insert(ReplaceRule r) => _db.insertReplaceRule(r);
  Future<void> update(ReplaceRule r) => _db.updateReplaceRule(r);
  Future<void> delete(int id) => _db.deleteReplaceRule(id);
}
