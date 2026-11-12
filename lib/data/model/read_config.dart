import 'dart:convert';

/// 页脚槽位内容枚举
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
  // 排版数值换算：
  // 上游存「十分之一单位」整数，绘制前 `lineSpacingExtra / 10f`；字距为 em，
  // 缩进宽按 `'　' * N` 整串测量后除以字符数；滑杆显示带偏移（字号=进度+5、
  // 字距=(进度-50)/100）。Flutter 的 TextStyle.height 是行高倍数、letterSpacing
  // 是逻辑像素、缩进用全角空格串，属于不同的单位模型，强行套 /10 会造成
  // 首屏行距骤变（行为不等价）。此处保留 Flutter 自有换算单位，不伪造换算，
  // 换算对照见 lib/ui/book/read/read_detail_utils.dart 的说明。

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
  /// 屏幕超时档位：0 跟随系统 / 60 / 300 / 600 秒 / -1 常亮
  int keepLight;
  bool showMenuOnTap;
  bool longPressSelect;
  String? charset;
  int chineseConverter; // 0:不转换 1:转简体 2:转繁体
  int preDownloadCount;
  bool showTimeBattery;
  bool customHeaderEnabled;
  bool customFooterEnabled;

  /* ===== 阅读配置字段补齐 ===== */
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

  /* ===== 批次 3 · 日/夜/墨水屏三套独立配置 =====
      日/夜/墨水屏三套独立配置的默认值：
     白天 bgStr/#EEEEEE、textColor/#3E3D3B、textAccentColor/#E53935、
     darkStatusIcon=true、pageAnim=0；夜间 bgStrNight/#000000、
     textColorNight/#ADADAD、textAccentColorNight/#FE4D55、darkStatusIconNight=false；
     EInk bgStrEInk/#FFFFFF、textColorEInk/#000000、textAccentColorEInk/#000000、
     darkStatusIconEInk=true、pageAnimEInk=4（无动画）。
     「同一字段三份存储」：白天调的配色/动画不会覆盖夜间与墨水屏，切回各自还原。 */
  // 当前生效模式：0 日间 / 1 夜间 / 2 墨水屏（对齐 AppConfig.isNightTheme/isEInkMode）。
  int readThemeMode;
  int textAccentColor;              // 白天强调色
  bool darkStatusIcon;              // 白天状态栏暗色图标
  int bgColorNight;                 // 夜间背景
  int textColorNight;               // 夜间文字
  int textAccentColorNight;         // 夜间强调色
  bool darkStatusIconNight;         // 夜间状态栏暗色图标
  int bgColorEInk;                  // 墨水屏背景
  int textColorEInk;                // 墨水屏文字
  int textAccentColorEInk;          // 墨水屏强调色
  bool darkStatusIconEInk;          // 墨水屏状态栏暗色图标
  int pageAnimEInk;                 // 墨水屏专用翻页动画（默认 4 无动画）

  /* ===== 批次 3 · 极端值容错 / 文本选择菜单 / 退出提示 ===== */
  int systemTypefaces;              // 0 无衬线 / 1 衬线 / 2 等宽系统字体
  int contentSelectSpeakMod;        // 0 只朗读选中内容 / 1 从选择处一直朗读
  bool showAddToShelfAlert;         // 退出未入架书时弹「加入书架」确认

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
    this.keepLight = 0,
    this.showMenuOnTap = true,
    this.longPressSelect = true,
    this.charset,
    this.chineseConverter = 0,
    this.preDownloadCount = 0,
    this.showTimeBattery = true,
    this.customHeaderEnabled = false,
    this.customFooterEnabled = false,
    // ===== 补齐字段默认值=====
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
    // ===== 批次 3 默认值=====
    this.readThemeMode = 0,
    this.textAccentColor = 0xFFE53935,
    this.darkStatusIcon = true,
    this.bgColorNight = 0xFF000000,
    this.textColorNight = 0xFFADADAD,
    this.textAccentColorNight = 0xFFFE4D55,
    this.darkStatusIconNight = false,
    this.bgColorEInk = 0xFFFFFFFF,
    this.textColorEInk = 0xFF000000,
    this.textAccentColorEInk = 0xFF000000,
    this.darkStatusIconEInk = true,
    this.pageAnimEInk = 4,
    this.systemTypefaces = 0,
    this.contentSelectSpeakMod = 0,
    this.showAddToShelfAlert = true,
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
    'keepLight': keepLight,
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
    // ===== 批次 3 字段序列化 =====
    'readThemeMode': readThemeMode,
    'textAccentColor': textAccentColor,
    'darkStatusIcon': darkStatusIcon,
    'bgColorNight': bgColorNight,
    'textColorNight': textColorNight,
    'textAccentColorNight': textAccentColorNight,
    'darkStatusIconNight': darkStatusIconNight,
    'bgColorEInk': bgColorEInk,
    'textColorEInk': textColorEInk,
    'textAccentColorEInk': textAccentColorEInk,
    'darkStatusIconEInk': darkStatusIconEInk,
    'pageAnimEInk': pageAnimEInk,
    'systemTypefaces': systemTypefaces,
    'contentSelectSpeakMod': contentSelectSpeakMod,
    'showAddToShelfAlert': showAddToShelfAlert,
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
    keepLight: json['keepLight'] is int
        ? json['keepLight'] as int
        : (int.tryParse(json['keepLight']?.toString() ?? '') ?? 0),
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
    // ===== 批次 3 字段反序列化（旧配置缺省时用上游默认值；越界值钳回合法域）=====
    readThemeMode: _readInt(json['readThemeMode'], 0).clamp(0, 2).toInt(),
    textAccentColor: json['textAccentColor'] ?? 0xFFE53935,
    darkStatusIcon: json['darkStatusIcon'] ?? true,
    bgColorNight: json['bgColorNight'] ?? 0xFF000000,
    textColorNight: json['textColorNight'] ?? 0xFFADADAD,
    textAccentColorNight: json['textAccentColorNight'] ?? 0xFFFE4D55,
    darkStatusIconNight: json['darkStatusIconNight'] ?? false,
    bgColorEInk: json['bgColorEInk'] ?? 0xFFFFFFFF,
    textColorEInk: json['textColorEInk'] ?? 0xFF000000,
    textAccentColorEInk: json['textAccentColorEInk'] ?? 0xFF000000,
    darkStatusIconEInk: json['darkStatusIconEInk'] ?? true,
    pageAnimEInk: _readInt(json['pageAnimEInk'], 4).clamp(0, 5).toInt(),
    systemTypefaces: _readInt(json['systemTypefaces'], 0).clamp(0, 2).toInt(),
    contentSelectSpeakMod: _readInt(json['contentSelectSpeakMod'], 0).clamp(0, 1).toInt(),
    showAddToShelfAlert: json['showAddToShelfAlert'] ?? true,
  );

  /// 反序列化时把 num / 数字字符串统一为 int（兼容 Android 备份互通）。
  static int _readInt(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /* ===== 批次 3 · 三套配置的「当前模式」选择器 =====
      Config 的 curBgStr()/curTextColor()/curStatusIconDark()/curPageAnim()
     与 setCurBg()/setCurTextColor()/setCurStatusIconDark()/setCurPageAnim()：
     读取时按当前模式选对应那份，写入时只写当前那份，互不覆盖。 */

  bool get isNightMode => readThemeMode == 1;
  bool get isEInkMode => readThemeMode == 2;

  int get curBgColor => switch (readThemeMode) {
        1 => bgColorNight,
        2 => bgColorEInk,
        _ => bgColor,
      };

  int get curTextColor => switch (readThemeMode) {
        1 => textColorNight,
        2 => textColorEInk,
        _ => textColor,
      };

  int get curTextAccentColor => switch (readThemeMode) {
        1 => textAccentColorNight,
        2 => textAccentColorEInk,
        _ => textAccentColor,
      };

  bool get curStatusIconDark => switch (readThemeMode) {
        1 => darkStatusIconNight,
        2 => darkStatusIconEInk,
        _ => darkStatusIcon,
      };

  /// 墨水屏用独立翻页动画（默认 4 无动画），日/夜共用 pageAnim。
  int get curPageAnim => isEInkMode ? pageAnimEInk : pageAnim;

  void setCurBgColor(int color) {
    switch (readThemeMode) {
      case 1:
        bgColorNight = color;
      case 2:
        bgColorEInk = color;
      default:
        bgColor = color;
    }
  }

  void setCurTextColor(int color) {
    switch (readThemeMode) {
      case 1:
        textColorNight = color;
      case 2:
        textColorEInk = color;
      default:
        textColor = color;
    }
  }

  void setCurTextAccentColor(int color) {
    switch (readThemeMode) {
      case 1:
        textAccentColorNight = color;
      case 2:
        textAccentColorEInk = color;
      default:
        textAccentColor = color;
    }
  }

  void setCurStatusIconDark(bool dark) {
    switch (readThemeMode) {
      case 1:
        darkStatusIconNight = dark;
      case 2:
        darkStatusIconEInk = dark;
      default:
        darkStatusIcon = dark;
    }
  }

  void setCurPageAnim(int anim) {
    if (isEInkMode) {
      pageAnimEInk = anim;
    } else {
      pageAnim = anim;
    }
  }

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
