import 'package:flutter/widgets.dart';

/// 全局导航 Key：供无 BuildContext 的服务（如书源 JS 运行时拉起网页登录）使用。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
