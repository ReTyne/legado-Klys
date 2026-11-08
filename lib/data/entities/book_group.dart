class BookGroup {
  int? id;
  String name;
  int order;
  int show;
  String? cover;

  BookGroup({this.id, required this.name, this.order = 0, this.show = 1, this.cover});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'order': order, 'show': show, 'cover': cover,
  };

  factory BookGroup.fromMap(Map<String, dynamic> map) => BookGroup(
    id: map['id'], name: map['name'] ?? '', order: map['order'] ?? 0,
    show: map['show'] ?? 1, cover: map['cover'],
  );
}
