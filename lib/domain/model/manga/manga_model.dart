/// 漫画阅读领域模型与枚举，对齐原版 ReadMangaConfig
enum MangaScrollMode { vertical, horizontal, webtoon }

class MangaConfig {
  bool showMangaUi;
  bool disableScale;
  bool disableScrollAnim;
  bool disableCrossFade;
  MangaScrollMode scrollMode;
  int preDownloadNum;
  int autoPageSpeed;
  bool disableClickScroll;
  bool hideTitle;
  bool enableGray;
  bool enableEInk;
  double sidePadding;
  bool volumeKey;

  MangaConfig({
    this.showMangaUi = true,
    this.disableScale = false,
    this.disableScrollAnim = false,
    this.disableCrossFade = false,
    this.scrollMode = MangaScrollMode.vertical,
    this.preDownloadNum = 3,
    this.autoPageSpeed = 3,
    this.disableClickScroll = false,
    this.hideTitle = false,
    this.enableGray = false,
    this.enableEInk = false,
    this.sidePadding = 0,
    this.volumeKey = false,
  });

  static MangaConfig get defaultConfig => MangaConfig();
}

/// 单张漫画图片
class MangaPage {
  final String url;
  final int index;
  const MangaPage(this.index, this.url);
}
