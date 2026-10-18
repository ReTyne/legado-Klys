import '../../data/model/book.dart';
import '../../data/model/book_chapter.dart';
import '../../data/model/book_group.dart';

/// 书籍仓库接口（领域层契约）
abstract class BookRepository {
  Future<List<Book>> getAllBooks();
  Future<Book?> getBook(String name, String author);
  Future<void> insertBook(Book book);
  Future<void> updateBook(Book book);
  Future<void> deleteBook(String name, String author);

  Future<List<BookChapter>> getChapters(String bookName, String bookAuthor);
  Future<void> saveChapters(String bookName, String bookAuthor, List<BookChapter> chapters);
  Future<void> updateChapterContent(String bookName, String author, int chapterIndex, String content);
  Future<void> deleteChapters(String bookName, String bookAuthor);

  Future<List<BookGroup>> getBookGroups();
  Future<void> insertBookGroup(BookGroup group);
  Future<void> deleteBookGroup(int id);

  Future<void> updateReadPosition(String bookName, String author, int chapterIndex, int pagePos, int time);
  Future<void> clearChapterContent();
}
