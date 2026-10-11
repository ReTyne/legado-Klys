import '../data/local/app_database.dart';
import '../data/repository/book_repository_impl.dart';
import '../data/repository/book_source_repository_impl.dart';
import '../data/repository/chapter_repository_impl.dart';
import '../data/repository/bookmark_repository_impl.dart';
import '../data/repository/replace_rule_repository_impl.dart';
import '../data/repository/rss_repository_impl.dart';
import '../domain/usecase/book/book_usecase.dart';
import '../domain/usecase/source/source_usecase.dart';
import '../domain/usecase/read/read_usecase.dart';
import '../domain/usecase/readRecord/readRecord_usecase.dart';

/// 依赖注入容器：集中提供数据库、仓库、用例单例
class AppModule {
  AppModule._();

  static final DatabaseService database = DatabaseService();

  // repositories
  static final BookRepositoryImpl bookRepository = BookRepositoryImpl(database);
  static final BookSourceRepositoryImpl sourceRepository = BookSourceRepositoryImpl(database);
  static final ChapterRepositoryImpl chapterRepository = ChapterRepositoryImpl(database);
  static final BookmarkRepositoryImpl bookmarkRepository = BookmarkRepositoryImpl(database);
  static final ReplaceRuleRepositoryImpl replaceRuleRepository = ReplaceRuleRepositoryImpl(database);
  static final RssRepositoryImpl rssRepository = RssRepositoryImpl(database);

  // use cases
  static final BookUseCase bookUseCase = BookUseCase(bookRepository);
  static final SourceUseCase sourceUseCase = SourceUseCase(sourceRepository);
  static final ReadUseCase readUseCase = ReadUseCase(chapterRepository);
  static final ReadRecordUseCase readRecordUseCase = ReadRecordUseCase(database);
}
