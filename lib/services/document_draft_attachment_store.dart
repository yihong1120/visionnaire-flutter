import 'dart:typed_data';

import 'document_draft_attachment_store_stub.dart'
    if (dart.library.io) 'document_draft_attachment_store_io.dart'
    if (dart.library.html) 'document_draft_attachment_store_web.dart' as impl;

class DocumentDraftAttachmentStore {
  const DocumentDraftAttachmentStore._();

  static Future<String?> saveBytes({
    required String draftKey,
    required String attachmentId,
    required Uint8List bytes,
  }) {
    return impl.saveBytes(
      draftKey: draftKey,
      attachmentId: attachmentId,
      bytes: bytes,
    );
  }

  static Future<Uint8List?> readBytes(String reference) {
    return impl.readBytes(reference);
  }

  static Future<void> deleteDraftAttachments(String draftKey) {
    return impl.deleteDraftAttachments(draftKey);
  }
}
