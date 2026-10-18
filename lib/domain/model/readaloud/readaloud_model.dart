/// 朗读领域模型，对齐原版朗读状态机
enum ReadAloudStatus { idle, play, pause, stop }

class ReadAloudState {
  ReadAloudStatus status;
  int chapterIndex;
  int paragraphIndex;
  double rate;
  double pitch;
  String? engineName;

  ReadAloudState({
    this.status = ReadAloudStatus.idle,
    this.chapterIndex = 0,
    this.paragraphIndex = 0,
    this.rate = 1.0,
    this.pitch = 1.0,
    this.engineName,
  });

  bool get isPlaying => status == ReadAloudStatus.play;
  bool get isPaused => status == ReadAloudStatus.pause;

  ReadAloudState copyWith({
    ReadAloudStatus? status,
    int? chapterIndex,
    int? paragraphIndex,
    double? rate,
    double? pitch,
    String? engineName,
  }) => ReadAloudState(
    status: status ?? this.status,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    paragraphIndex: paragraphIndex ?? this.paragraphIndex,
    rate: rate ?? this.rate,
    pitch: pitch ?? this.pitch,
    engineName: engineName ?? this.engineName,
  );
}
