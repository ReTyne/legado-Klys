/// PDF 大纲（对齐 Sigma PdfOutline / pdfx 大纲解析结果）
class PdfOutline {
  int? id;
  String bookName;
  String author;
  String title;
  int level;
  int page; // 0-based
  int order;

  PdfOutline({
    this.id,
    required this.bookName,
    this.author = '',
    required this.title,
    this.level = 0,
    this.page = 0,
    this.order = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookName': bookName,
        'author': author,
        'title': title,
        'level': level,
        'page': page,
        'sortOrder': order,
      };

  factory PdfOutline.fromMap(Map<String, dynamic> m) => PdfOutline(
        id: m['id'],
        bookName: m['bookName'] ?? '',
        author: m['author'] ?? '',
        title: m['title'] ?? '',
        level: m['level'] ?? 0,
        page: m['page'] ?? 0,
        order: m['sortOrder'] ?? m['order'] ?? 0,
      );
}
