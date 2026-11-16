import 'package:flutter/foundation.dart';

/// 发现分类刷新信号。
///
/// 书源脚本在发现页控件动作里改了分类依赖的变量后，会调用 refreshExplore()；
/// 原生侧失效分类缓存并递增此信号，发现页监听后重新求值分类。
final ValueNotifier<int> exploreRefreshSignal = ValueNotifier<int>(0);

/// 通知发现页重新加载分类。
void notifyExploreRefresh() {
  exploreRefreshSignal.value = exploreRefreshSignal.value + 1;
}

/// 重新登录信号：登录检测发现会话失效时，把待登录书源地址写入，
/// 登录通道/书源管理页监听后拉起登录界面。同一书源连续触发时追加时间戳
/// 保证 ValueNotifier 一定发出通知。
final ValueNotifier<String> reloginSignal = ValueNotifier<String>('');

/// 触发某书源的重新登录流程。
void notifyRelogin(String sourceUrl) {
  reloginSignal.value = '$sourceUrl#${DateTime.now().microsecondsSinceEpoch}';
}

/// 从 [reloginSignal] 值里取回书源地址（去掉尾部时间戳）。
String reloginSourceOf(String signal) {
  final i = signal.lastIndexOf('#');
  return i > 0 ? signal.substring(0, i) : signal;
}
