/// 由 rule_auto_completer.dart 按「一类一文件」拆出的 _FirstOrNull。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../rule_auto_completer.dart';


extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
