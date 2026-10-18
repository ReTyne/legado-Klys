import '../../../data/model/book_source.dart';
import '../../../data/repository/book_source_repository_impl.dart';
import '../../repository/book_source_repository.dart';

/// 书源业务用例：封装书源查询、启停、分组等业务规则
class SourceUseCase {
  final BookSourceRepository _repo;
  SourceUseCase([BookSourceRepository? repo]) : _repo = repo ?? BookSourceRepositoryImpl();

  Future<List<BookSource>> all({bool? enabled}) => _repo.getAllSources(enabled: enabled);

  Future<List<BookSource>> enabled() => _repo.getAllSources(enabled: true);

  Future<void> save(BookSource source) => _repo.insertSource(source);

  Future<void> delete(String url) => _repo.deleteSource(url);

  /// 批量启用/禁用
  Future<void> batchSetEnabled(List<String> urls, bool enabled) async {
    final all = await _repo.getAllSources();
    for (final s in all) {
      if (urls.contains(s.bookSourceUrl)) {
        s.enabled = enabled;
        await _repo.updateSource(s);
      }
    }
  }

  /// 全部启用/禁用
  Future<void> setAllEnabled(bool enabled) async {
    final all = await _repo.getAllSources();
    for (final s in all) {
      s.enabled = enabled;
      await _repo.updateSource(s);
    }
  }

  /// 调整排序（置顶 customOrder=0 / 置底 customOrder=max）
  Future<void> moveTo(BookSource target, bool toTop) async {
    final all = await _repo.getAllSources();
    if (toTop) {
      for (final s in all) {
        if (s.bookSourceUrl == target.bookSourceUrl) {
          s.customOrder = 0;
        } else {
          s.customOrder = (s.customOrder) + 1;
        }
        await _repo.updateSource(s);
      }
    } else {
      final maxOrder = all.isEmpty ? 0 : all.map((e) => e.customOrder).reduce((a, b) => a > b ? a : b) + 1;
      target.customOrder = maxOrder;
      await _repo.updateSource(target);
    }
  }
}
