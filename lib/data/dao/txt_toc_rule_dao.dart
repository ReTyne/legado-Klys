import '../local/app_database.dart';
import '../model/txt_toc_rule.dart';

class TxtTocRuleDao {
  final DatabaseService _db;
  TxtTocRuleDao([DatabaseService? db]) : _db = db ?? DatabaseService();

  Future<List<TxtTocRule>> getAll() => _db.getTxtTocRules();
  Future<void> insert(TxtTocRule r) => _db.insertTxtTocRule(r);
  Future<void> delete(int id) => _db.deleteTxtTocRule(id);
}
