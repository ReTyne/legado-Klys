import '../../data/model/book_source.dart';

/// 书源仓库接口
abstract class BookSourceRepository {
  Future<List<BookSource>> getAllSources({bool? enabled});
  Future<BookSource?> getSource(String url);
  Future<void> insertSource(BookSource source);
  Future<void> updateSource(BookSource source);
  Future<void> deleteSource(String url);
  Future<List<String>> getSourceGroups();
}
