import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

const int _maxStoredBytes = 2 * 1024 * 1024;
const String _prefix = 'visionnaire.document_draft_attachment.v1.';

String _key(String draftKey, String attachmentId) {
  return '$_prefix$draftKey.$attachmentId';
}

Future<String?> saveBytes({
  required String draftKey,
  required String attachmentId,
  required Uint8List bytes,
}) async {
  if (bytes.isEmpty || bytes.lengthInBytes > _maxStoredBytes) return null;
  final prefs = await SharedPreferences.getInstance();
  final key = _key(draftKey, attachmentId);
  await prefs.setString(key, base64Encode(bytes));
  return 'prefs:$key';
}

Future<Uint8List?> readBytes(String reference) async {
  if (!reference.startsWith('prefs:')) return null;
  final prefs = await SharedPreferences.getInstance();
  final encoded = prefs.getString(reference.substring(6));
  if (encoded == null || encoded.isEmpty) return null;
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}

Future<void> deleteDraftAttachments(String draftKey) async {
  final prefs = await SharedPreferences.getInstance();
  final keyPrefix = '$_prefix$draftKey.';
  final keys = prefs.getKeys().where((key) => key.startsWith(keyPrefix));
  for (final key in keys) {
    await prefs.remove(key);
  }
}
