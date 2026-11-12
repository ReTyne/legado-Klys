/// 批次 6 · 基础层异常层次。
///
/// 上游 `NoStackTraceException` 通过覆写 `fillInStackTrace()` 让高频业务异常
/// 跳过堆栈采集以省开销。Dart 无法覆写该方法，这里以 [StackTrace.empty] 作为
/// 固定堆栈并覆写 toString，达到「无堆栈、仅文案」的等价效果。
///
/// 文件所有权说明：本目录为新建，不触碰
/// `lib/help/source/check_source_service.dart` 中已有的同名局部异常
/// （作用域不同，互不冲突）。
library;

/// 无堆栈异常基类（对齐 `exception/NoStackTraceException.kt:6-15`）。
class NoStackTraceException implements Exception {
  final String message;
  const NoStackTraceException(this.message);

  /// 固定为空堆栈，跳过采集（等价上游 `stackTrace = emptyStackTrace`）。
  StackTrace get stackTrace => StackTrace.empty;

  @override
  String toString() => message;
}

/// 目录为空（对齐 `exception/TocEmptyException.kt`）。
class TocEmptyException extends NoStackTraceException {
  const TocEmptyException([super.message = '目录为空']);
}

/// 正文为空（对齐 `exception/ContentEmptyException.kt`）。
class ContentEmptyException extends NoStackTraceException {
  const ContentEmptyException([super.message = '正文为空']);
}

/// 文件为空（对齐 `exception/EmptyFileException.kt`）。
class EmptyFileException extends NoStackTraceException {
  const EmptyFileException([super.message = '文件为空']);
}

/// 书籍目录无效（对齐 `exception/InvalidBooksDirException.kt`）。
class InvalidBooksDirException extends NoStackTraceException {
  const InvalidBooksDirException([super.message = '书籍目录无效']);
}

/// 未设置书籍目录（对齐 `exception/NoBooksDirException.kt:6`，自带默认文案）。
class NoBooksDirException extends NoStackTraceException {
  const NoBooksDirException() : super('未设置书籍目录');
}

/// 正则替换超时（对齐 `exception/RegexTimeoutException.kt`）。
class RegexTimeoutException extends NoStackTraceException {
  const RegexTimeoutException([super.message = '正则替换超时']);
}

/// 并发限制异常（对齐 `exception/ConcurrentException.kt:8`，
/// 携带 [waitTime] 供上层做并发等待）。
class ConcurrentException extends NoStackTraceException {
  final int waitTime;
  const ConcurrentException(super.message, this.waitTime);
}

/// 对齐 `utils/ThrowableExtensions.kt:5-13` 的 `Throwable.stackTraceStr`：
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

/// 对齐 `utils/ThrowableExtensions.kt:15-18` 的 `asIOException()`：
/// 保留 cause 链的 IOException 包装。Dart 无 `initCause`，用本类显式保存
/// [cause]，语义与上游一致（不丢失原始异常）。
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
