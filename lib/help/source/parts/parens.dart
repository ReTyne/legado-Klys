/// 由 js_mini_eval.dart 按「一类一文件」拆出的 _Parens。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../js_mini_eval.dart';


class _Parens { final List<String> args; final int end; _Parens(this.args, this.end); }
