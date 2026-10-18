import "package:flutter/foundation.dart";

/// 视图模型基类，统一管理加载/错误/空状态
abstract class BaseViewModel extends ChangeNotifier {
  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;
  bool get hasError => _error != null;

  void setLoading(bool v) {
    _loading = v;
    if (v) _error = null;
    notifyListeners();
  }

  void setError(String? msg) {
    _error = msg;
    _loading = false;
    notifyListeners();
  }

  /// 安全执行异步任务，自动维护 loading/error
  Future<T?> guard<T>(Future<T> Function() task) async {
    setLoading(true);
    try {
      final result = await task();
      setLoading(false);
      return result;
    } catch (e) {
      setError(e.toString());
      return null;
    }
  }
}

/// 简单列表视图模型基类
class ListViewModel<T> extends BaseViewModel {
  List<T> items = [];
  bool get isEmpty => items.isEmpty;
  void setItems(List<T> list) {
    items = list;
    notifyListeners();
  }
}
