import 'package:flutter/widgets.dart';

/// 当前生效的应用语言（由 main 在启动时从 oc_language 偏好写入：
/// 1 = 简体中文，2 = English，null = 跟随系统）。
Locale? appLocale;

/// 应用显示名：中文环境 -> 「阅读」，其他语言 -> legado。
String get appDisplayName {
  final locale = appLocale ?? WidgetsBinding.instance.platformDispatcher.locale;
  return locale.languageCode == 'zh' ? '阅读' : 'legado';
}
