import 'dart:typed_data';
import 'package:flutter/material.dart';

class ImgMeta {
  Uint8List? rawBytes; // Make nullable to support existing images (network URL)
  Uint8List? stampedBytes; // Make nullable
  String? stampedDateText;
  String name; // Could be the URL for existing images
  final int? sourceIndex;
  final TextEditingController locCtrl;
  final TextEditingController descCtrl;
  final TextEditingController dateCtrl;
  bool showDate;
  bool useTodayDate;

  ImgMeta({
    this.rawBytes,
    this.stampedBytes,
    required this.name,
    this.sourceIndex,
    required String defaultDate,
    this.useTodayDate = false,
  })  : locCtrl = TextEditingController(),
        descCtrl = TextEditingController(),
        dateCtrl = TextEditingController(text: defaultDate),
        showDate = true {
    if (stampedBytes != null && defaultDate.trim().isNotEmpty) {
      stampedDateText = defaultDate.trim();
    }
  }

  bool get isNetworkImage =>
      rawBytes == null &&
      (name.startsWith('http') ||
          name.startsWith('https') ||
          name.startsWith('/'));
}
