/// 由 settings_screen.dart 拆分还原（历史合并点）。
/// 以 part 形式归属同一库，私有成员互通，外部 import 路径不变。
part of 'settings_screen.dart';

/// 导入书籍配置已移除：import_path / import_sort / import_nameTpl 无任何消费方，
/// ImportBookService.importPath(path) 仅接收调用方传入的 path 参数。

/// 字体选择列表项：区分内置资源与本机文件，便于 FontLoader 取字节
class _FontEntry {
  final String path;
  final String name;
  final String source;
  final bool asset;
  const _FontEntry({required this.path, required this.name, required this.source, required this.asset});
}
