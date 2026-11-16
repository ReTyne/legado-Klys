/// 基础层异常层次。
///
/// 高频业务异常跳过堆栈采集以省开销。这里以 [StackTrace.empty] 作为
/// 固定堆栈并覆写 toString，达到「无堆栈、仅文案」的效果。
library;

/// 无堆栈异常基类。
class NoStackTraceException implements Exception {
  final String message;
  const NoStackTraceException(this.message);

  /// 固定为空堆栈，跳过采集。
  StackTrace get stackTrace => StackTrace.empty;

  @override
  String toString() => message;
}

/// 目录为空异常。
class TocEmptyException extends NoStackTraceException {
  const TocEmptyException([super.message = '目录为空']);
}

/// 正文为空异常。
class ContentEmptyException extends NoStackTraceException {
  const ContentEmptyException([super.message = '正文为空']);
}

/// 文件为空异常。
class EmptyFileException extends NoStackTraceException {
  const EmptyFileException([super.message = '文件为空']);
}

/// 书籍目录无效异常。
class InvalidBooksDirException extends NoStackTraceException {
  const InvalidBooksDirException([super.message = '书籍目录无效']);
}

/// 未设置书籍目录异常，自带默认文案。
class NoBooksDirException extends NoStackTraceException {
  const NoBooksDirException() : super('未设置书籍目录');
}

/// 正则替换超时异常。
class RegexTimeoutException extends NoStackTraceException {
  const RegexTimeoutException([super.message = '正则替换超时']);
}

/// 并发限制异常，携带 [waitTime] 供上层做并发等待。
class ConcurrentException extends NoStackTraceException {
  final int waitTime;
  const ConcurrentException(super.message, this.waitTime);
}

/// 有堆栈则返回堆栈文本，否则回退错误文案，再空则 `noErrorMsg`。
/// 对 [NoStackTraceException] 因堆栈恒为空，直接回退到文案。
String stackTraceStr(Object error, [StackTrace? stack]) {
  if (error is NoStackTraceException) {
    return error.message.isEmpty ? 'noErrorMsg' : error.message;
  }
  final stText = stack?.toString() ?? '';
  if (stText.trim().isNotEmpty) return stText;
  final msg = error.toString();
  return msg.isEmpty ? 'noErrorMsg' : msg;
}

/// 保留 cause 链的 IOException 包装。用本类显式保存 [cause]，不丢失原始异常。
class WrappedIOException implements Exception {
  final String message;
  final Object cause;
  const WrappedIOException(this.message, this.cause);

  @override
  String toString() => 'IOException: $message (cause: $cause)';
}

/// 把任意错误包装成带 cause 的 IOException 等价对象。
WrappedIOException asIOException(Object error) =>
    WrappedIOException(error.toString(), error);
