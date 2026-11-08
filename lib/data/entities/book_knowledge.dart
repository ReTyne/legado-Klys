class BookKnowledge {
  int? id;
  String bookName;
  String author;
  String type; // character, event, location, item
  String name;
  String? content;
  String? cover;
  int? order;

  BookKnowledge({this.id, required this.bookName, required this.author, required this.type, required this.name, this.content, this.cover, this.order});

  Map<String, dynamic> toMap() => {
    'id': id, 'bookName': bookName, 'author': author, 'type': type,
    'name': name, 'content': content, 'cover': cover, 'order': order,
  };

  factory BookKnowledge.fromMap(Map<String, dynamic> map) => BookKnowledge(
    id: map['id'], bookName: map['bookName'] ?? '', author: map['author'] ?? '',
    type: map['type'] ?? 'character', name: map['name'] ?? '',
    content: map['content'], cover: map['cover'], order: map['order'],
  );
}
