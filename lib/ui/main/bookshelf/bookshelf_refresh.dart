import 'package:flutter/foundation.dart';

/// 书架布局/排序配置变更信号。
///
/// 配置页保存任一 `bs_*` 偏好后递增；书架页作为常驻 PageView 子页监听此信号，
/// 在返回前台时重新读取配置并刷新，避免改动需重启 App 才生效。
final ValueNotifier<int> bookshelfConfigRevision = ValueNotifier<int>(0);
