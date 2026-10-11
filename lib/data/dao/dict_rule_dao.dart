import '../local/app_database.dart';
import '../model/dict_rule.dart';

class DictRuleDao {
  final DatabaseService _db;
  DictRuleDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<DictRule>> getAll() => _db.getDictRules();
  Future<void> insert(DictRule r) => _db.insertDictRule(r);
  Future<void> delete(int id) => _db.deleteDictRule(id);
}
