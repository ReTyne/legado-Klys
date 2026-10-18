class TranslationCache {
  int? id;
  String source;
  String target;
  String original;
  String translated;
  int saveTime;

  TranslationCache({this.id, required this.source, required this.target, required this.original, required this.translated, required this.saveTime});

  Map<String, dynamic> toMap() => {
    'id': id, 'source': source, 'target': target,
    'original': original, 'translated': translated, 'saveTime': saveTime,
  };

  factory TranslationCache.fromMap(Map<String, dynamic> map) => TranslationCache(
    id: map['id'], source: map['source'] ?? '', target: map['target'] ?? '',
    original: map['original'] ?? '', translated: map['translated'] ?? '',
    saveTime: map['saveTime'] ?? 0,
  );
}
