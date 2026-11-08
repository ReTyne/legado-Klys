/// 由 rule_auto_completer.dart 按「一类一文件」拆出的 _Block。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../rule_auto_completer.dart';


class _Block {
  final dom.Element container;
  final String itemTag;
  final List<dom.Element> items;
  _Block(this.container, this.itemTag, this.items);
}
