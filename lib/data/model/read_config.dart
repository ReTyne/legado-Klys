import 'dart:convert';

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
  int preDownloadCount;
  bool showTimeBattery;
  bool customHeaderEnabled;
  bool customFooterEnabled;

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
    this.headerSize = 12,
    this.footerSize = 12,
    this.headerBold = false,
    this.footerBold = false,
    this.headerAlignCenter = true,
    this.headerColor = 0xFF999999,
    this.footerAlignCenter = false,
    this.footerColor = 0xFF999999,
    this.keepScreenOn = false,
    this.showMenuOnTap = true,
    this.longPressSelect = true,
    this.charset,
    this.preDownloadCount = 0,
    this.showTimeBattery = true,
    this.customHeaderEnabled = false,
    this.customFooterEnabled = false,
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
    'headerSize': headerSize, 'footerSize': footerSize,
    'headerBold': headerBold, 'footerBold': footerBold,
    'keepScreenOn': keepScreenOn, 'showMenuOnTap': showMenuOnTap, 'longPressSelect': longPressSelect,
    'charset': charset, 'preDownloadCount': preDownloadCount,
    'showTimeBattery': showTimeBattery,
    'customHeaderEnabled': customHeaderEnabled, 'customFooterEnabled': customFooterEnabled,
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
    preDownloadCount: json['preDownloadCount'] ?? 0,
    showTimeBattery: json['showTimeBattery'] ?? true,
    customHeaderEnabled: json['customHeaderEnabled'] ?? false,
    customFooterEnabled: json['customFooterEnabled'] ?? false,
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
