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
