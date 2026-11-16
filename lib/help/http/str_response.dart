/// 书源网络响应对象。
///
/// legado 语义下 body()/url()/code() 等均为方法，故本类以同名方法暴露状态；
/// Dart 不允许公开字段与方法同名，状态存于私有字段，另提供 [toMap] 供引擎
/// 按字段名读取。注意：在 Dart 侧 `resp.body` 是方法引用，取值请用 `body()`。
class StrResponse {
  StrResponse._({
    required String body,
    required String raw,
    required String errorBody,
    required int callTime,
    required String url,
    required int code,
    required String message,
    required Map<String, String> headers,
    required bool isSuccessful,
    StrResponse? redirectResponse,
  })  : _body = body,
        _raw = raw,
        _errorBody = errorBody,
        _callTime = callTime,
        _url = url,
        _code = code,
        _message = message,
        _headers = Map<String, String>.unmodifiable(headers),
        _isSuccessful = isSuccessful,
        _redirectResponse = redirectResponse;

  factory StrResponse({
    String body = '',
    String? raw,
    String errorBody = '',
    int callTime = 0,
    String url = '',
    int code = 200,
    String message = 'OK',
    Map<String, String> headers = const <String, String>{},
    bool? isSuccessful,
  }) {
    return StrResponse._(
      body: body,
      raw: raw ?? body,
      errorBody: errorBody,
      callTime: callTime,
      url: url,
      code: code,
      message: message,
      headers: headers,
      isSuccessful: isSuccessful ?? code < 400,
    );
  }

  /// 302/200 双层：返回代表最终 200 的响应，其 [redirectResponse] 为原始
  /// 重定向层（带传入的状态码与 Location 头）。
  factory StrResponse.fromRedirect(int code, String location, String finalUrl) {
    final redirectLayer = StrResponse._(
      body: '',
      raw: '',
      errorBody: '',
      callTime: 0,
      url: finalUrl,
      code: code,
      message: 'Redirect',
      headers: <String, String>{'Location': location},
      isSuccessful: code < 400,
    );
    return StrResponse._(
      body: '',
      raw: '',
      errorBody: '',
      callTime: 0,
      url: finalUrl,
      code: 200,
      message: 'OK',
      headers: const <String, String>{},
      isSuccessful: true,
      redirectResponse: redirectLayer,
    );
  }

  String _body;
  final String _raw;
  final String _errorBody;
  int _callTime;
  final String _url;
  final int _code;
  final String _message;
  final Map<String, String> _headers;
  final bool _isSuccessful;
  final StrResponse? _redirectResponse;

  String body() => _body;
  String raw() => _raw;
  String errorBody() => _errorBody;
  int callTime() => _callTime;
  String url() => _url;
  int code() => _code;
  String message() => _message;
  Map<String, String> headers() => _headers;
  bool isSuccessful() => _isSuccessful;

  /// 重定向场景下的前一层响应（非重定向构造时为 null）。
  StrResponse? redirectResponse() => _redirectResponse;

  void putCallTime(int t) => _callTime = t;

  /// 字段快照（供引擎按字段名读取）。
  Map<String, dynamic> toMap() => <String, dynamic>{
        'body': _body,
        'raw': _raw,
        'errorBody': _errorBody,
        'callTime': _callTime,
        'url': _url,
        'code': _code,
        'message': _message,
        'headers': _headers,
        'isSuccessful': _isSuccessful,
      };

  @override
  String toString() => _body;
}
