// 统一设计令牌（Design Tokens）与语义化上下文扩展。
//
// 目标：把散落在 182 个 UI 文件里的间距 / 圆角 / 字号 / 断点 / 时长魔法数
// 收敛为单一来源，并让语义色、文本样式通过 context 直接读取，跟随全局
// AppTheme（亮/暗/AMOLED/E-ink/字体缩放）。所有常量均为编译期 const，
// 可在 const 构造中使用，替换不产生运行时开销。

import 'package:flutter/material.dart';

/// 间距阶梯（4pt 栅格）。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: l, vertical: s);
  static const EdgeInsets pageAll = EdgeInsets.all(l);
  static const EdgeInsets card = EdgeInsets.all(l);
  static const EdgeInsets tile = EdgeInsets.symmetric(horizontal: l, vertical: s);
  static const EdgeInsets section = EdgeInsets.fromLTRB(l, l, l, s);
  static const EdgeInsets dialog = EdgeInsets.all(xl);
}

/// 圆角阶梯。
abstract final class AppRadius {
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius sAll = BorderRadius.all(Radius.circular(s));
  static const BorderRadius mAll = BorderRadius.all(Radius.circular(m));
  static const BorderRadius lAll = BorderRadius.all(Radius.circular(l));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// 动效时长。
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}

/// 响应式断点（Material 3 窗口尺寸类）。
abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;

  /// 宽屏（平板 / 桌面 / 横屏大屏）：导航栏应切换为 NavigationRail、
  /// 内容区应居中限宽。
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= compact;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;
}

/// 语义化文本样式：基于当前 Theme 的 TextTheme，自动跟随字体缩放。
abstract final class AppType {
  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium ?? const TextStyle(fontSize: 16);
  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
  static TextStyle label(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);
  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 11);
}

/// 语义化上下文扩展：减少 `Theme.of(context).colorScheme.xxx` 样板。
extension AppThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;

  /// 主文字色（自动适配亮/暗）。
  Color get onSurface => Theme.of(this).colorScheme.onSurface;

  /// 次要文字 / 图标色。
  Color get onSurfaceVariant => Theme.of(this).colorScheme.onSurfaceVariant;
}
