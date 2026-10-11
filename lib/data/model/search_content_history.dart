class SearchContentHistory {
  int? id;
  String content;
  int searchTime;

  SearchContentHistory({this.id, required this.content, required this.searchTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'content': content, 'searchTime': searchTime,
  };

  factory SearchContentHistory.fromMap(Map<String, dynamic> map) => SearchContentHistory(
    id: map['id'], content: map['content'] ?? '', searchTime: map['searchTime'] ?? 0,
  );
}
