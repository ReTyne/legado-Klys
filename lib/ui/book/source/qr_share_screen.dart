import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/common/deep_link_service.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/ui/book/source/source_manage_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';
import 'package:share_plus/share_plus.dart';

part 'parts/qr_code.dart';
part 'parts/qr_encoder.dart';
part 'parts/matrix_builder.dart';
part 'parts/qr_share_screen.dart';
part 'parts/qr_share_screen_state.dart';
part 'parts/qr_painter.dart';


/// 二维码内容超出容量（版本 1-10 + 纠错等级 M 上限约 271 字节）时抛出
class QrEncodeException implements Exception {
  final int dataLength;
  final int maxCapacity;
  const QrEncodeException(this.dataLength, this.maxCapacity);

  @override
  String toString() => '内容长度 $dataLength 字节，超出二维码容量上限 $maxCapacity 字节';
}
