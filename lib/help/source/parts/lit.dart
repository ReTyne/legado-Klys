/// 由 js_mini_eval.dart 按「一类一文件」拆出的 _Lit。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../js_mini_eval.dart';

class _Lit { final String value; final int end; _Lit(this.value, this.end); }
