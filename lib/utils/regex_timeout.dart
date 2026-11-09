import 'dart:async';
import 'dart:isolate';

import 'package:legado_md3/help/exceptions/app_exceptions.dart';

/// 批次 6 · 正则替换超时（对齐 legado-E `utils/RegexExtensions.kt:28-89`
/// 与 `api/controller/ReplaceRuleController.kt:79-92`），防 ReDoS 卡死 Web 服务。

/// 对齐 `data/entities/ReplaceRule.kt:115-120` 的 getValidTimeoutMillisecond()：
/// `timeoutMillisecond <= 0` 时回退默认 3000ms。
int validTimeoutMillisecond(int timeoutMillisecond) =>
    timeoutMillisecond <= 0 ? 3000 : timeoutMillisecond;

/// 独立 isolate 的入参（仅含可跨 isolate 发送的类型）。
class _ReplaceTask {
  const _ReplaceTask(this.input, this.pattern, this.replacement, this.port);
  final String input;
  final String pattern;
  final String replacement;
  final SendPort port;
}

class _ReplaceError {
  const _ReplaceError(this.message);
  final String message;
}

/// isolate 入口：必须是顶层/静态函数。非法正则等异常主动回传，避免 isolate
/// 未捕获异常直接终止。
void _replaceEntry(_ReplaceTask task) {
  try {
    // Dart 的替换 API 在 String 上：String.replaceAll(Pattern, String)。
    task.port.send(
        task.input.replaceAll(RegExp(task.pattern), task.replacement));
  } catch (e) {
    task.port.send(_ReplaceError(e.toString()));
  }
}

/// 带超时保护的正则替换。
///
/// Dart 的 [RegExp] 在单个 isolate 内同步执行且无法从外部中断，故把替换放到
/// 独立 isolate：主 isolate（Web 服务事件循环）永不被阻塞；一旦超过
/// [timeoutMillisecond] 即 `kill` 该 isolate 并抛 [RegexTimeoutException]，
/// 真正阻断灾难性回溯（ReDoS）。
///
/// 上游超时后还需「3 秒未结束则重启应用」（RegexExtensions.kt:74-84），
/// Flutter 通过直接 `Isolate.kill(immediate)` 达到更强隔离，无需重启进程。
///
/// [isRegex] 为 false 时退化为字面替换
/// （对齐 `ReplaceRuleController.kt:88` 的 `text.replace(pattern, replacement)`）。
Future<String> replaceRegexWithTimeout({
  required String input,
  required String pattern,
  required String replacement,
  bool isRegex = true,
  int timeoutMillisecond = 3000,
  String ruleName = '',
}) async {
  final timeout = validTimeoutMillisecond(timeoutMillisecond);
  if (!isRegex) {
    return input.replaceAll(pattern, replacement);
  }
  final port = ReceivePort();
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn<_ReplaceTask>(
      _replaceEntry,
      _ReplaceTask(input, pattern, replacement, port.sendPort),
    );
    final message =
        await port.first.timeout(Duration(milliseconds: timeout));
    if (message is _ReplaceError) {
      throw FormatException(message.message);
    }
    return message as String;
  } on TimeoutException {
    isolate?.kill(priority: Isolate.immediate);
    // 文案对齐 RegexExtensions.kt:73-75 的「替换超时 / 规则名称 / 替换规则」。
    throw RegexTimeoutException(
        '替换超时(${timeout}ms)\n规则名称:$ruleName\n替换规则:$pattern');
  } finally {
    port.close();
  }
}
