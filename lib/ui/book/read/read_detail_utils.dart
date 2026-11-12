import 'dart:io';

/// 批次 3 · 阅读器细节：可单测的纯函数与状态机。
///
/// 每个函数都标注了对应的 （Android/Kotlin）证据行号，供
/// `reading_screen.dart` / `reading_settings_screen.dart` 真实消费，
/// 避免「只写不读」的假开关。本文件不依赖 Flutter widget，便于单元测试。

/// 对齐 `res/xml/pref_config_read.xml` 的 `click_image_way_title`
/// 与 `ui/book/read/page/ContentTextView.kt:267-308` 的 5 档图片点击方式。
/// 上游值：`0 默认行为 / 1 预览图片 / 2 兼容旧版 / 3 关闭点击 / 4 双击生效`。
const List<String> clickImgWayLabels = [
  '默认行为',
  '预览图片',
  '兼容旧版',
  '关闭点击',
  '双击生效',
];

/// 排版边距求解结果（对齐 `ChapterProvider.upLayout()` / `setFallbackLayout()`）。
class ReadPadding {
  final int left;
  final int top;
  final int right;
  final int bottom;

  /// 是否触发了「边距设置过大」回退。
  final bool fellBack;

  /// 可视文本宽。
  final double visibleWidth;

  /// 可视文本高（已扣上下边距）。
  final double visibleHeight;

  const ReadPadding({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.fellBack,
    required this.visibleWidth,
    required this.visibleHeight,
  });
}

/// 对齐 `ui/book/read/page/provider/ChapterProvider.kt:328-374`：
/// ```
/// visibleRight  = viewWidth - paddingRight          // 双页也用整屏宽（上游如此）
/// visibleBottom = paddingTop + visibleHeight
///               = viewHeight - paddingBottom
/// if (paddingLeft >= visibleRight || paddingTop >= visibleBottom) {
///     AppLog.put("边距设置过大，请重新设置", toast = true); setFallbackLayout() }
/// ```
/// 回退值 `20/5/20/5`（上游 `20.dpToPx()` / `5.dpToPx()`；Flutter 用逻辑像素等价）。
/// 边距过大时可视宽会为负导致 `TextPainter` 除零/白屏，故必须钳制。
ReadPadding resolveReadPadding({
  required double viewWidth,
  required double viewHeight,
  required int left,
  required int top,
  required int right,
  required int bottom,
  bool doublePage = false,
}) {
  // 对齐 `ChapterProvider.upViewSize():285-287`：尺寸未测量出来时直接返回，
  // 避免 0 宽高的首帧被误判为「边距过大」而弹 Toast。
  if (viewWidth <= 0 || viewHeight <= 0) {
    return ReadPadding(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      fellBack: false,
      visibleWidth: 0,
      visibleHeight: 0,
    );
  }
  // 上游条件：left >= viewWidth - right（即 left+right >= 屏宽）
  //          top  >= viewHeight - bottom（即 top+bottom >= 屏高）
  final overflow = left >= viewWidth - right || top >= viewHeight - bottom;
  final l = overflow ? 20 : left;
  final t = overflow ? 5 : top;
  final r = overflow ? 20 : right;
  final b = overflow ? 5 : bottom;
  final vw = (doublePage ? viewWidth / 2 : viewWidth) - l - r;
  final vh = viewHeight - t - b;
  return ReadPadding(
    left: l,
    top: t,
    right: r,
    bottom: b,
    fellBack: overflow,
    visibleWidth: vw > 0 ? vw : 0,
    visibleHeight: vh > 0 ? vh : 0,
  );
}

/// 对齐 `ui/book/read/ReadMenu.kt:304`：
/// `val brightness = if (value < 1f) 0.004f else value / 255f`（value 为 0..255 的滑杆值）。
/// 亮度调到 0 时仍保留最小背光 `0.004f`，防止屏幕全黑不可读。
/// Flutter 亮度是 0..1 归一化值，等价为「低于 1/255 抬到 0.004」。
double minBacklight(double normalized, {double floor = 0.004}) =>
    normalized < 1.0 / 255.0 ? floor : normalized;

/// 视口尺寸变化分类（对齐 `ChapterProvider.upViewSize()`：284-301 行）。
enum ViewSizeChange {
  /// 尺寸回到原值：取消待执行的延迟回调，不重排。
  none,

  /// 宽度变化：立即重排（键盘/分屏改宽不会频繁抖动）。
  immediate,

  /// 仅高度变化（键盘弹收/状态栏显隐）：延迟 300ms 再重排，连续抖动取消上一次。
  debounced,
}

/// 对齐 `ChapterProvider.upViewSize()`：
/// `width == viewWidth`（仅高度变）→ `handler.postDelayed(300)`；
/// `width != viewWidth`（宽度变）→ 立即 `notifyViewSizeChange`；
/// `width == viewWidth && height == viewHeight` 且有挂起回调 → 取消。
ViewSizeChange classifyViewSizeChange({
  required double? oldW,
  required double? oldH,
  required double newW,
  required double newH,
  double eps = 0.5,
}) {
  if (oldW == null || oldH == null) return ViewSizeChange.immediate;
  final wChanged = (oldW - newW).abs() >= eps;
  final hChanged = (oldH - newH).abs() >= eps;
  if (!wChanged && !hChanged) return ViewSizeChange.none;
  if (!wChanged && hChanged) return ViewSizeChange.debounced;
  return ViewSizeChange.immediate;
}

/// 上游 `handler.postDelayed(300)`：仅高度变化时的重排防抖时长（毫秒）。
const int viewSizeDebounceMs = 300;

/// 单击 300ms 防抖 + 双击状态机，对齐
/// `ui/book/read/page/ContentTextView.kt:245-253`：
/// ```
/// val debounceClick = currentTime - lastClickTime < 300L
/// lastClickTime = currentTime
/// doubleClick = if (debounceClick) !doubleClick else false
/// ```
class ClickTracker {
  final int windowMs;
  int _lastClickAt = -1;
  bool _doubleClick = false;

  ClickTracker({this.windowMs = 300});

  /// 登记一次点击，返回本次的防抖态与双击态。
  ({bool debounced, bool doubleClick}) onTap(int nowMs) {
    final debounced = _lastClickAt >= 0 && nowMs - _lastClickAt < windowMs;
    _lastClickAt = nowMs;
    _doubleClick = debounced ? !_doubleClick : false;
    return (debounced: debounced, doubleClick: _doubleClick);
  }

  bool get doubleClick => _doubleClick;

  void reset() {
    _lastClickAt = -1;
    _doubleClick = false;
  }
}

/// 判断是否为「自定义字体文件路径」而非系统字体预设名。
/// 上游 `ChapterProvider.getTypeface()`（207-234）对 `content://` / 文件路径用
/// `Typeface.createFromFile`，失败时清空 `textFont` 并回退系统字体。
/// Flutter 侧：设置页的「衬线体/等宽字体」是显示名而非路径，不参与校验。
bool isFontFilePath(String? fontFamily) {
  if (fontFamily == null || fontFamily.isEmpty) return false;
  final lower = fontFamily.toLowerCase();
  return fontFamily.contains('/') ||
      fontFamily.contains('\\') ||
      lower.endsWith('.ttf') ||
      lower.endsWith('.otf') ||
      lower.endsWith('.ttc');
}

/// 字体坏路径校验：路径型字体文件不存在时返回 false，调用方据此清空并落盘。
/// 非路径（系统预设名）恒返回 true。
bool fontPathExists(String? fontFamily) {
  if (!isFontFilePath(fontFamily)) return true;
  try {
    return File(fontFamily!).existsSync();
  } catch (_) {
    return false;
  }
}

/// 对齐 `ChapterProvider.getTypeface():223-227`：
/// `AppConfig.systemTypefaces` 0=无衬线(默认) 1=衬线 2=等宽。
/// Flutter 用引擎通用族名，解析不到时引擎自行回退默认字体（无崩溃）。
String? systemFontFamily(int systemTypefaces) => switch (systemTypefaces) {
      1 => 'serif',
      2 => 'monospace',
      _ => null,
    };
