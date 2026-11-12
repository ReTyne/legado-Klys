import 'package:legado_md3/data/model/book.dart';

class SearchBook extends Book {
  String? searchUrl;
  int? originOrder;
  bool? addToShelf;

  /// 同名同作者合并后的全部来源（origin 列表）
  final List<String> origins = [];

  SearchBook({
    required super.name,
    required super.author,
    super.coverUrl,
    super.intro,
    super.kind,
    super.lastChapter,
    super.origin,
    super.originName,
    super.noteUrl,
    super.bookUrl,
    super.wordCount,
    this.searchUrl,
    this.originOrder,
    this.addToShelf = false,
  });

  /// 合并另一来源的同名同作者书籍（对齐 SearchBook.addOrigin）
  void addOrigin(String origin) {
    if (origin.isEmpty) return;
    if (!origins.contains(origin)) origins.add(origin);
  }

  Book toBook() => Book(
    name: name,
    author: author,
    coverUrl: coverUrl,
    intro: intro,
    kind: kind,
    lastChapter: lastChapter,
    origin: origin,
    originName: originName,
    noteUrl: noteUrl,
    bookUrl: bookUrl,
    wordCount: wordCount,
  );
}
