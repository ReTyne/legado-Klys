import 'dart:convert';

/// 页脚槽位内容枚举（对齐 legado-E 阅读器页脚三槽位能力）
enum FooterSlot {
  none,           // 空白
  chapterTitle,   // 章节名
  bookName,       // 书名
  pageNumber,     // 页码（章内）
  totalPages,     // 总页数（章内）
  progress,       // 进度%（全书：当前章+当前页/全书）
  time,           // 时间
  battery,        // 电量（图标；无真实读数时降级为静态图标）
  batteryPercent, // 电量%（无真实读数时降级为图标）
}

/// 页脚槽位枚举的中文标签（供设置界面选择）
const Map<FooterSlot, String> footerSlotLabels = {
  FooterSlot.none: '空白',
  FooterSlot.chapterTitle: '章节名',
  FooterSlot.bookName: '书名',
  FooterSlot.pageNumber: '页码',
  FooterSlot.totalPages: '总页数',
  FooterSlot.progress: '进度%',
  FooterSlot.time: '时间',
  FooterSlot.battery: '电量',
  FooterSlot.batteryPercent: '电量%',
};

/// 页脚三槽位默认配置：左-时间 / 中-页码 / 右-电量（与旧版页脚视觉一致）
const List<FooterSlot> defaultFooterSlots = [
  FooterSlot.time,
  FooterSlot.pageNumber,
  FooterSlot.battery,
];

/// 阅读配置
class ReadConfig {
  // 文字
  int textSize;
  int textColor;
  String? fontFamily;
  int fontWeight;
  bool boldText;
  int textAlign; // 0:左对齐 1:居中 2:两端对齐
  int textIndent;
  int lineSpacing;
  int paragraphSpacing;
  double letterSpacing;
  double wordSpacing;

  // 背景
  int bgColor;
  String? bgImage;
  int shadowLevel; // 0-3
  int underlineType; // 0:无 1:实线 2:虚线 3:波浪线 4:双线

  // 翻页
  int pageAnim; // 0:覆盖 1:仿真 2:滑动 3:滚动 4:无动画 5:上下
  bool invertPage;
  int clickAreaNext;
  int clickAreaPrev;
  bool clickTurnPage;
  bool volumeKeyPage;
  bool volumeKeyReverse;
  bool autoNextPage;
  int autoNextPageSpeed;
  bool simulatedReading;

  // 显示
  bool statusBarVisibility;
  bool titleVisibility;
  bool timeVisibility;
  bool batteryVisibility;
  bool pageNumberVisibility;
  bool showProgress;
  bool immersiveMode;
  bool fullScreen;
  int screenOrientation; // 0:自动 1:竖屏 2:横屏
  bool eyeProtection;
  int eyeProtectionLevel;

  // 布局
  int verticalLayout; // 0:横屏 1:竖屏
  int paddingLeft;
  int paddingRight;
  int paddingTop;
  int paddingBottom;
  int headerHeight;
  int footerHeight;
  String? headerString;
  String? footerString;
  // 页脚三槽位内容（依次为 左/中/右 槽位），null 时回退旧版单行页脚逻辑
  List<FooterSlot>? footerSlots;
  int headerSize;
  int footerSize;
  bool headerBold;
  bool footerBold;
  bool headerAlignCenter;
  int headerColor;
  bool footerAlignCenter;
  int footerColor;

  // 其他
  bool keepScreenOn;
  bool showMenuOnTap;
  bool longPressSelect;
  String? charset;
  int chineseConverter; // 0:不转换 1:转简体 2:转繁体
  int preDownloadCount;
  bool showTimeBattery;
  bool customHeaderEnabled;
  bool customFooterEnabled;

  /* ===== 对照 legado-E ReadBookConfig.kt / pref_config_read.xml 补齐 ===== */
  // 标题与阅读栏
  bool showReadTitleAddition;    // 标题附加信息（章节名后附加书名等）
  bool readBarStyleFollowPage;   // 阅读栏样式跟随页面背景
  // 换源
  bool autoChangeSource;         // 正文失效时自动换源
  // 图片
  int clickImgWay;               // 图片点击方式：0 无 1 预览 2 浏览器
  // 渲染与排版
  bool optimizeRender;           // 渲染优化
  bool adaptSpecialStyle;        // 特殊样式适配
  bool readBodyToLh;             // 正文带到行高
  // 翻页
  int doubleHorizontalPage;      // 双水平页：0 单页 1 双水平页 2 横屏双页
  bool noAnimScrollPage;         // 滚动模式无动画
  bool volumeKeyPageOnPlay;      // 朗读播放时音量键翻页
  bool keyPageOnLongPress;       // 长按音量键翻页
  bool disableReturnKey;         // 禁用返回键
  int pageTouchSlop;             // 滑动灵敏度（0 默认，越大越迟钝）
  String? customPageKey;         // 自定义按键 JSON
  // 显示
  bool paddingDisplayCutouts;    // 刘海屏 padding
  // 朗读
  bool readAloudByPage;                  // 按页朗读
  bool pauseReadAloudWhilePhoneCalls;    // 来电暂停朗读
  bool mediaButtonPerNext;               // 媒体键下一章
  bool streamReadAloudAudio;             // 流式朗读音频
  bool sysTtsConfig;                     // 系统 TTS 跟随系统语速
  bool ttsFlowSys;                       // 朗读语速跟随系统

  ReadConfig({
    this.textSize = 20,
    this.textColor = 0xFF333333,
    this.fontFamily,
    this.fontWeight = 400,
    this.boldText = false,
    this.textAlign = 2,
    this.textIndent = 2,
    this.lineSpacing = 2,
    this.paragraphSpacing = 1,
    this.letterSpacing = 0,
    this.wordSpacing = 0,
    this.bgColor = 0xFFFFF8E1,
    this.bgImage,
    this.shadowLevel = 0,
    this.underlineType = 0,
    this.pageAnim = 0,
    this.invertPage = false,
    this.clickAreaNext = 1,
    this.clickAreaPrev = 1,
    this.clickTurnPage = true,
    this.volumeKeyPage = false,
    this.volumeKeyReverse = false,
    this.autoNextPage = false,
    this.autoNextPageSpeed = 5,
    this.simulatedReading = false,
    this.statusBarVisibility = true,
    this.titleVisibility = true,
    this.timeVisibility = true,
    this.batteryVisibility = true,
    this.pageNumberVisibility = true,
    this.showProgress = true,
    this.immersiveMode = false,
    this.fullScreen = false,
    this.screenOrientation = 0,
    this.eyeProtection = false,
    this.eyeProtectionLevel = 50,
    this.verticalLayout = 0,
    this.paddingLeft = 16,
    this.paddingRight = 16,
    this.paddingTop = 8,
    this.paddingBottom = 8,
    this.headerHeight = 32,
    this.footerHeight = 32,
    this.headerString,
    this.footerString,
    this.footerSlots = defaultFooterSlots,
    this.headerSize = 12,
    this.footerSize = 12,
    this.headerBold = false,
    this.footerBold = false,
    this.headerAlignCenter = true,
    this.headerColor = 0xFF6B6B6B,
    this.footerAlignCenter = false,
    this.footerColor = 0xFF6B6B6B,
    this.keepScreenOn = false,
    this.showMenuOnTap = true,
    this.longPressSelect = true,
    this.charset,
    this.chineseConverter = 0,
    this.preDownloadCount = 0,
    this.showTimeBattery = true,
    this.customHeaderEnabled = false,
    this.customFooterEnabled = false,
    // ===== 补齐字段默认值（对齐 legado-E）=====
    this.showReadTitleAddition = true,
    this.readBarStyleFollowPage = false,
    this.autoChangeSource = true,
    this.clickImgWay = 0,
    this.optimizeRender = false,
    this.adaptSpecialStyle = true,
    this.readBodyToLh = true,
    this.doubleHorizontalPage = 0,
    this.paddingDisplayCutouts = false,
    this.noAnimScrollPage = false,
    this.volumeKeyPageOnPlay = false,
    this.pageTouchSlop = 0,
    this.disableReturnKey = false,
    this.keyPageOnLongPress = false,
    this.customPageKey,
    this.readAloudByPage = false,
    this.pauseReadAloudWhilePhoneCalls = false,
    this.mediaButtonPerNext = false,
    this.streamReadAloudAudio = false,
    this.sysTtsConfig = false,
    this.ttsFlowSys = true,
  });

  Map<String, dynamic> toJson() => {
    'textSize': textSize, 'textColor': textColor, 'fontFamily': fontFamily,
    'fontWeight': fontWeight, 'boldText': boldText, 'textAlign': textAlign,
    'textIndent': textIndent, 'lineSpacing': lineSpacing, 'paragraphSpacing': paragraphSpacing,
    'letterSpacing': letterSpacing, 'wordSpacing': wordSpacing,
    'bgColor': bgColor, 'bgImage': bgImage, 'shadowLevel': shadowLevel, 'underlineType': underlineType,
    'pageAnim': pageAnim, 'invertPage': invertPage, 'clickAreaNext': clickAreaNext, 'clickAreaPrev': clickAreaPrev,
    'clickTurnPage': clickTurnPage, 'volumeKeyPage': volumeKeyPage, 'volumeKeyReverse': volumeKeyReverse,
    'autoNextPage': autoNextPage, 'autoNextPageSpeed': autoNextPageSpeed, 'simulatedReading': simulatedReading,
    'statusBarVisibility': statusBarVisibility, 'titleVisibility': titleVisibility, 'timeVisibility': timeVisibility,
    'batteryVisibility': batteryVisibility, 'pageNumberVisibility': pageNumberVisibility, 'showProgress': showProgress,
    'immersiveMode': immersiveMode, 'fullScreen': fullScreen, 'screenOrientation': screenOrientation,
    'eyeProtection': eyeProtection, 'eyeProtectionLevel': eyeProtectionLevel,
    'verticalLayout': verticalLayout, 'paddingLeft': paddingLeft, 'paddingRight': paddingRight,
    'paddingTop': paddingTop, 'paddingBottom': paddingBottom,
    'headerHeight': headerHeight, 'footerHeight': footerHeight,
    'headerString': headerString, 'footerString': footerString,
    // 槽位枚举按 index 持久化，保证跨版本兼容
    'footerSlots': footerSlots?.map((e) => e.index).toList(),
    'headerSize': headerSize, 'footerSize': footerSize,
    'headerBold': headerBold, 'footerBold': footerBold,
    'keepScreenOn': keepScreenOn, 'showMenuOnTap': showMenuOnTap, 'longPressSelect': longPressSelect,
    'charset': charset, 'chineseConverter': chineseConverter, 'preDownloadCount': preDownloadCount,
    'showTimeBattery': showTimeBattery,
    'customHeaderEnabled': customHeaderEnabled, 'customFooterEnabled': customFooterEnabled,
    // ===== 补齐字段序列化 =====
    'showReadTitleAddition': showReadTitleAddition,
    'readBarStyleFollowPage': readBarStyleFollowPage,
    'autoChangeSource': autoChangeSource,
    'clickImgWay': clickImgWay,
    'optimizeRender': optimizeRender,
    'adaptSpecialStyle': adaptSpecialStyle,
    'readBodyToLh': readBodyToLh,
    'doubleHorizontalPage': doubleHorizontalPage,
    'paddingDisplayCutouts': paddingDisplayCutouts,
    'noAnimScrollPage': noAnimScrollPage,
    'volumeKeyPageOnPlay': volumeKeyPageOnPlay,
    'pageTouchSlop': pageTouchSlop,
    'disableReturnKey': disableReturnKey,
    'keyPageOnLongPress': keyPageOnLongPress,
    'customPageKey': customPageKey,
    'readAloudByPage': readAloudByPage,
    'pauseReadAloudWhilePhoneCalls': pauseReadAloudWhilePhoneCalls,
    'mediaButtonPerNext': mediaButtonPerNext,
    'streamReadAloudAudio': streamReadAloudAudio,
    'sysTtsConfig': sysTtsConfig,
    'ttsFlowSys': ttsFlowSys,
  };

  factory ReadConfig.fromJson(Map<String, dynamic> json) => ReadConfig(
    textSize: json['textSize'] ?? 20,
    textColor: json['textColor'] ?? 0xFF333333,
    fontFamily: json['fontFamily'],
    fontWeight: json['fontWeight'] ?? 400,
    boldText: json['boldText'] ?? false,
    textAlign: json['textAlign'] ?? 2,
    textIndent: json['textIndent'] ?? 2,
    lineSpacing: json['lineSpacing'] ?? 2,
    paragraphSpacing: json['paragraphSpacing'] ?? 1,
    letterSpacing: (json['letterSpacing'] ?? 0).toDouble(),
    wordSpacing: (json['wordSpacing'] ?? 0).toDouble(),
    bgColor: json['bgColor'] ?? 0xFFFFF8E1,
    bgImage: json['bgImage'],
    shadowLevel: json['shadowLevel'] ?? 0,
    underlineType: json['underlineType'] ?? 0,
    pageAnim: json['pageAnim'] ?? 0,
    invertPage: json['invertPage'] ?? false,
    clickAreaNext: json['clickAreaNext'] ?? 1,
    clickAreaPrev: json['clickAreaPrev'] ?? 1,
    clickTurnPage: json['clickTurnPage'] ?? true,
    volumeKeyPage: json['volumeKeyPage'] ?? false,
    volumeKeyReverse: json['volumeKeyReverse'] ?? false,
    autoNextPage: json['autoNextPage'] ?? false,
    autoNextPageSpeed: json['autoNextPageSpeed'] ?? 5,
    simulatedReading: json['simulatedReading'] ?? false,
    statusBarVisibility: json['statusBarVisibility'] ?? true,
    titleVisibility: json['titleVisibility'] ?? true,
    timeVisibility: json['timeVisibility'] ?? true,
    batteryVisibility: json['batteryVisibility'] ?? true,
    pageNumberVisibility: json['pageNumberVisibility'] ?? true,
    showProgress: json['showProgress'] ?? true,
    immersiveMode: json['immersiveMode'] ?? false,
    fullScreen: json['fullScreen'] ?? false,
    screenOrientation: json['screenOrientation'] ?? 0,
    eyeProtection: json['eyeProtection'] ?? false,
    eyeProtectionLevel: json['eyeProtectionLevel'] ?? 50,
    verticalLayout: json['verticalLayout'] ?? 0,
    paddingLeft: json['paddingLeft'] ?? 16,
    paddingRight: json['paddingRight'] ?? 16,
    paddingTop: json['paddingTop'] ?? 8,
    paddingBottom: json['paddingBottom'] ?? 8,
    headerHeight: json['headerHeight'] ?? 32,
    footerHeight: json['footerHeight'] ?? 32,
    headerString: json['headerString'],
    footerString: json['footerString'],
    // 兼容旧配置：无 footerSlots 字段时用默认三槽位
    footerSlots: (json['footerSlots'] as List<dynamic>?)
            ?.map((e) => FooterSlot.values[(e as num).toInt().clamp(0, FooterSlot.values.length - 1)])
            .toList() ??
        defaultFooterSlots,
    headerSize: json['headerSize'] ?? 12,
    footerSize: json['footerSize'] ?? 12,
    headerBold: json['headerBold'] ?? false,
    footerBold: json['footerBold'] ?? false,
    headerAlignCenter: json['headerAlignCenter'] ?? true,
    headerColor: json['headerColor'] ?? 0xFF999999,
    footerAlignCenter: json['footerAlignCenter'] ?? false,
    footerColor: json['footerColor'] ?? 0xFF999999,
    keepScreenOn: json['keepScreenOn'] ?? false,
    showMenuOnTap: json['showMenuOnTap'] ?? true,
    longPressSelect: json['longPressSelect'] ?? true,
    charset: json['charset'],
    chineseConverter: json['chineseConverter'] ?? 0,
    preDownloadCount: json['preDownloadCount'] ?? 0,
    showTimeBattery: json['showTimeBattery'] ?? true,
    customHeaderEnabled: json['customHeaderEnabled'] ?? false,
    customFooterEnabled: json['customFooterEnabled'] ?? false,
    // ===== 补齐字段反序列化（旧配置缺省时用默认值）=====
    showReadTitleAddition: json['showReadTitleAddition'] ?? true,
    readBarStyleFollowPage: json['readBarStyleFollowPage'] ?? false,
    autoChangeSource: json['autoChangeSource'] ?? true,
    clickImgWay: json['clickImgWay'] ?? 0,
    optimizeRender: json['optimizeRender'] ?? false,
    adaptSpecialStyle: json['adaptSpecialStyle'] ?? true,
    readBodyToLh: json['readBodyToLh'] ?? true,
    doubleHorizontalPage: json['doubleHorizontalPage'] ?? 0,
    paddingDisplayCutouts: json['paddingDisplayCutouts'] ?? false,
    noAnimScrollPage: json['noAnimScrollPage'] ?? false,
    volumeKeyPageOnPlay: json['volumeKeyPageOnPlay'] ?? false,
    pageTouchSlop: json['pageTouchSlop'] ?? 0,
    disableReturnKey: json['disableReturnKey'] ?? false,
    keyPageOnLongPress: json['keyPageOnLongPress'] ?? false,
    customPageKey: json['customPageKey'],
    readAloudByPage: json['readAloudByPage'] ?? false,
    pauseReadAloudWhilePhoneCalls: json['pauseReadAloudWhilePhoneCalls'] ?? false,
    mediaButtonPerNext: json['mediaButtonPerNext'] ?? false,
    streamReadAloudAudio: json['streamReadAloudAudio'] ?? false,
    sysTtsConfig: json['sysTtsConfig'] ?? false,
    ttsFlowSys: json['ttsFlowSys'] ?? true,
  );

  String toJsonString() => jsonEncode(toJson());
  factory ReadConfig.fromJsonString(String str) => ReadConfig.fromJson(jsonDecode(str));
  /// 预设阅读主题
  static const List<Map<String, dynamic>> presets = [
    {'name': '默认', 'bgColor': 0xFFFFF8E1, 'textColor': 0xFF333333},
    {'name': '护眼', 'bgColor': 0xFFCCE8CF, 'textColor': 0xFF333333},
    {'name': '夜间', 'bgColor': 0xFF1A1A2E, 'textColor': 0xFFE0E0E0},
    {'name': '羊皮纸', 'bgColor': 0xFFF5E6C8, 'textColor': 0xFF5D4E37},
    {'name': '绿色', 'bgColor': 0xFFC8E6C9, 'textColor': 0xFF1B5E20},
  ];

}
