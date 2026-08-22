import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> saveBytesToTempFile(
  String filename,
  List<int> bytes, {
  String? mimeType,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
