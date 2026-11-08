import 'dart:io';

/// 源码契约测试的辅助读取。
///
/// 项目按 legado-E 的「一类一文件」方式拆细后，一个库的实现会分散到主文件、
/// part 文件与相邻的独立库文件里。契约断言应当覆盖「库整体」而不是某个物理
/// 文件，因此这里按主库路径补读对应的拆分目录并拼接，避免重构后契约误报。
const Map<String, List<String>> _splitSourceDirs = {
  // JS 注入脚本按行切片到 bridge/ 目录
  'lib/help/source/js/legado_bridge_js.dart': [
    'lib/help/source/js/bridge',
  ],
  // DAO 方法按业务域拆到 data/dao/ 目录
  'lib/data/local/app_database.dart': [
    'lib/data/dao',
  ],
};

/// 返回 [path] 对应库被拆分出去的源码内容（未拆分时为空串）。
///
/// 除了显式映射的目录，还会检查主文件同级的 `parts/` 目录——「一类一文件」
/// 拆分把辅助类放在那里。多个主库可能共用同一个 `parts/` 目录，因此只拼接
/// `part of '../主文件名'` 明确归属当前主库的文件。
String extraLibrarySources(String path) {
  final sb = StringBuffer();
  final mainName = path.split('/').last;
  final dirs = <String>[
    ...?_splitSourceDirs[path],
    '${path.substring(0, path.lastIndexOf('/'))}/parts',
  ];
  for (final d in dirs) {
    final dir = Directory(d);
    if (!dir.existsSync()) continue;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final text = f.readAsStringSync();
      if (d.endsWith('/parts') &&
          !text.contains("part of '../$mainName';")) {
        continue;
      }
      sb.write('\n');
      sb.write(text);
    }
  }
  return sb.toString();
}
