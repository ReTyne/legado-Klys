import 'package:legado_md3/help/source/js/js_source.dart';

/// 定时任务「执行自定义脚本」动作所需的最小 JsSource 占位实现。
///
/// 定时脚本不绑定具体书源（无探索/目录/登录规则），但 JS 运行时
/// [MiniLegadoJs] 仍需一个 JsSource 提供 getVariable/setVariable 等
/// 变量作用域。这里提供一个纯内存实现，变量不持久化。
class AutoTaskJsSource implements JsSource {
  AutoTaskJsSource();

  @override
  String get jsUrl => 'legado://autoTask';
  @override
  String get jsName => '定时任务';
  @override
  String get jsHttpUrl => '';
  @override
  String? variable;
  @override
  String? get variableComment => null;
  @override
  int? get lastUpdateTime => null;
  @override
  String? get jsLib => null;
  @override
  String? get loginUrl => null;
  @override
  String? get header => null;
  @override
  bool get enabledCookieJar => false;
  @override
  String get jsGroup => '';
  @override
  String get jsComment => '';
  @override
  int get jsType => 0;
  @override
  String get jsBookUrlPattern => '';
  @override
  int get jsConcurrentRate => 0;
  @override
  bool get jsEnabledExplore => false;
  @override
  String get jsExploreUrl => '';
  @override
  String get jsSearchUrl => '';
  @override
  String get jsTocUrl => '';
  @override
  String get jsRuleBookUrlPattern => '';
}
