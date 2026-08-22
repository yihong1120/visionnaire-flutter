import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

String _safeSegment(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return safe.isEmpty ? 'draft' : safe;
}

Future<Directory> _draftDirectory(String draftKey) async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory(
    p.join(root.path, 'visionnaire_drafts', _safeSegment(draftKey)),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<String?> saveBytes({
  required String draftKey,
  required String attachmentId,
  required Uint8List bytes,
}) async {
  if (bytes.isEmpty) return null;
  final dir = await _draftDirectory(draftKey);
  final file = File(p.join(dir.path, _safeSegment(attachmentId)));
  await file.writeAsBytes(bytes, flush: false);
  return 'file:${file.path}';
}

Future<Uint8List?> readBytes(String reference) async {
  if (!reference.startsWith('file:')) return null;
  final file = File(reference.substring(5));
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

Future<void> deleteDraftAttachments(String draftKey) async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory(
    p.join(root.path, 'visionnaire_drafts', _safeSegment(draftKey)),
  );
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}
