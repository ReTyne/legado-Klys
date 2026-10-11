import 'package:legado_md3/data/model/book.dart';

class SearchBook extends Book {
  String? searchUrl;
  int? originOrder;
  bool? addToShelf;

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
