/// 由 source_debug_screen.dart 按「一类一文件」拆出的 _StepStatus。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../source_debug_screen.dart';


/// 分步调试步骤执行状态
enum _StepStatus { idle, running, ok, fail }
