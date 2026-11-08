/// 跨源换源检索缓存（对齐 Sigma SearchBook + SearchBookDao）
class SearchBookTable {
  String bookUrl;
  String name;
  String author;
  String origin;
  String? originName;
  int type;
  String? coverUrl;
  String? intro;
  String? latestChapterTitle;
  String tocUrl;
  int time;
  int originOrder;
  String? chapterWordCountText;
  int chapterWordCount;
  int respondTime;

  SearchBookTable({
    required this.bookUrl,
    this.name = '',
    this.author = '',
    required this.origin,
    this.originName,
    this.type = 8,
    this.coverUrl,
    this.intro,
    this.latestChapterTitle,
    this.tocUrl = '',
    int? time,
    this.originOrder = 0,
    this.chapterWordCountText,
    this.chapterWordCount = -1,
    this.respondTime = -1,
  }) : time = time ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'bookUrl': bookUrl,
        'name': name,
        'author': author,
        'origin': origin,
        'originName': originName,
        'type': type,
        'coverUrl': coverUrl,
        'intro': intro,
        'latestChapterTitle': latestChapterTitle,
        'tocUrl': tocUrl,
        'time': time,
        'originOrder': originOrder,
        'chapterWordCountText': chapterWordCountText,
        'chapterWordCount': chapterWordCount,
        'respondTime': respondTime,
      };

  factory SearchBookTable.fromMap(Map<String, dynamic> m) => SearchBookTable(
        bookUrl: m['bookUrl'] ?? '',
        name: m['name'] ?? '',
        author: m['author'] ?? '',
        origin: m['origin'] ?? '',
        originName: m['originName'],
        type: m['type'] ?? 8,
        coverUrl: m['coverUrl'],
        intro: m['intro'],
        latestChapterTitle: m['latestChapterTitle'],
        tocUrl: m['tocUrl'] ?? '',
        time: m['time'],
        originOrder: m['originOrder'] ?? 0,
        chapterWordCountText: m['chapterWordCountText'],
        chapterWordCount: m['chapterWordCount'] ?? -1,
        respondTime: m['respondTime'] ?? -1,
      );
}
