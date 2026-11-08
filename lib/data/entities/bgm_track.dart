/// BGM 背景音乐曲目（对齐 fork BGM 在线音乐库）
class BgmTrack {
  int? id;
  String title;
  String artist;
  String url;
  String? coverUrl;
  String source;
  int duration;
  int customOrder;

  BgmTrack({
    this.id,
    required this.title,
    this.artist = '',
    required this.url,
    this.coverUrl,
    this.source = 'local',
    this.duration = 0,
    this.customOrder = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'url': url,
        'coverUrl': coverUrl,
        'source': source,
        'duration': duration,
        'customOrder': customOrder,
      };

  factory BgmTrack.fromMap(Map<String, dynamic> m) => BgmTrack(
        id: m['id'],
        title: m['title'] ?? '',
        artist: m['artist'] ?? '',
        url: m['url'] ?? '',
        coverUrl: m['coverUrl'],
        source: m['source'] ?? 'local',
        duration: m['duration'] ?? 0,
        customOrder: m['customOrder'] ?? 0,
      );
}
