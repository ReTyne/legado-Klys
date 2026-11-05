import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 回归「代码调用 / 互相联系」：java.openVideoPlayer 必须是三层贯通的真实链路
///   JS 桥(java.openVideoPlayer → legado://video)
///     → Dart JS 运行时(_intercept 分发 → _handleVideo → LegadoBridgeJs.openVideoPlayer)
///       → Kotlin MainActivity(MethodChannel('legado/video').open → ACTION_VIEW 播放器)
/// 任何一层缺失都会让书源的视频播放能力变成孤儿/死实现，故用源码契约锁定。
void main() {
  String read(String p) => File(p).readAsStringSync();

  test('JS 桥发 legado://video 并交由 Dart handler 处理', () {
    final bridge = read('lib/help/source/js/legado_bridge_js.dart');
    // java.openVideoPlayer 走内部协议
    expect(bridge, contains('openVideoPlayer: function'));
    expect(bridge, contains('legado://video?url='));
    // Dart helper 明确调用同名 MethodChannel
    expect(bridge, contains("MethodChannel('legado/video')"));
    expect(bridge, contains("invokeMethod('open'"));
    // 注释不再声称「Kotlin 未实现」（避免文档与代码不符的假完成）
    expect(bridge.contains('Kotlin 侧未接'), isFalse);
  });

  test('Dart JS 运行时有 legado://video 分发与 _handleVideo', () {
    final rt = read('lib/help/source/js/legado_js_runtime.dart');
    expect(rt, contains("url.startsWith('legado://video')"));
    expect(rt, contains('_handleVideo(uri)'));
    expect(rt, contains('LegadoBridgeJs.openVideoPlayer(url, title)'));
  });

  test('Kotlin 原生侧注册同名通道并用系统播放器打开（K 风格原生实现）', () {
    final kt = read(
        'android/app/src/main/kotlin/com/legado/md3/MainActivity.kt');
    expect(kt, contains('"legado/video"'));
    expect(kt, contains('videoChannelName'));
    expect(kt, contains('"open" ->'));
    expect(kt, contains('Intent.ACTION_VIEW'));
    expect(kt, contains('setDataAndType(Uri.parse(url), "video/*")'));
  });
}
