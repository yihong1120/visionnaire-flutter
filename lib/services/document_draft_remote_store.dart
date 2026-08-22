import 'dart:typed_data';

import '../models/document_draft.dart';
import '../providers/unified_auth_provider.dart';
import 'document_draft_attachment_store.dart';
import 'file_manage_api_service.dart';

const Set<String> supportedRemoteDocumentDraftTypes = <String>{
  'file_edit',
  'photo_doc',
  'audit_fix',
};

bool isRemoteDocumentDraftSupported({String? draftType, String? draftKey}) {
  final String normalizedType = draftType?.trim() ?? '';
  if (normalizedType.isNotEmpty) {
    return supportedRemoteDocumentDraftTypes.contains(normalizedType);
  }

  final String normalizedKey = draftKey?.trim() ?? '';
  if (normalizedKey.isEmpty) return false;
  return supportedRemoteDocumentDraftTypes.any(
    (type) => normalizedKey.startsWith('$type:'),
  );
}

class DocumentDraftRemoteStore {
  DocumentDraftRemoteStore({
    required UnifiedAuthProvider auth,
    bool enabled = true,
  })  : _auth = auth,
        _enabled = enabled;

  final UnifiedAuthProvider _auth;
  final bool _enabled;
  final Map<String, DocumentDraftAttachmentResult> _uploadedAttachments =
      <String, DocumentDraftAttachmentResult>{};

  Future<DocumentDraft?> load(String key) async {
    if (!_enabled) return null;
    if (!isRemoteDocumentDraftSupported(draftKey: key)) return null;
    final token = await _token();
    final draft = await FileManageAPIService.getDocumentDraft(
      token: token,
      draftKey: key,
    );
    if (draft == null) return null;
    return _withDownloadedAttachments(draft, token: token);
  }

  Future<void> save(DocumentDraft draft) async {
    if (!_enabled) return;
    if (!isRemoteDocumentDraftSupported(
      draftType: draft.type,
      draftKey: draft.key,
    )) {
      return;
    }
    final token = await _token();
    final remoteDraft = await _withUploadedAttachments(draft, token: token);
    await FileManageAPIService.upsertDocumentDraft(
      token: token,
      draft: remoteDraft,
    );
  }

  Future<void> delete(String key) async {
    if (!_enabled) return;
    if (!isRemoteDocumentDraftSupported(draftKey: key)) return;
    final token = await _token();
    await FileManageAPIService.deleteDocumentDraft(
      token: token,
      draftKey: key,
    );
    _uploadedAttachments
        .removeWhere((cacheKey, _) => cacheKey.startsWith('$key|'));
  }

  Future<String> _token() async {
    var token = _auth.requestToken;
    if (token == null) {
      await _auth.refreshIfNeeded();
      token = _auth.requestToken;
    }
    if (token == null) {
      throw Exception('Not logged in');
    }
    return token;
  }

  Future<DocumentDraft> _withUploadedAttachments(
    DocumentDraft draft, {
    required String token,
  }) async {
    final payload = _deepCopyMap(draft.payload);
    await _uploadLocalAttachments(
      payload,
      token: token,
      draft: draft,
      path: draft.type,
    );
    return DocumentDraft(
      key: draft.key,
      type: draft.type,
      payload: payload,
      updatedAt: draft.updatedAt,
      expiresAt: draft.expiresAt,
    );
  }

  Future<DocumentDraft> _withDownloadedAttachments(
    DocumentDraft draft, {
    required String token,
  }) async {
    final payload = _deepCopyMap(draft.payload);
    await _downloadRemoteAttachments(
      payload,
      token: token,
      draftKey: draft.key,
      path: draft.type,
    );
    return DocumentDraft(
      key: draft.key,
      type: draft.type,
      payload: payload,
      updatedAt: draft.updatedAt,
      expiresAt: draft.expiresAt,
    );
  }

  Future<void> _uploadLocalAttachments(
    dynamic value, {
    required String token,
    required DocumentDraft draft,
    required String path,
  }) async {
    if (value is List) {
      for (int index = 0; index < value.length; index++) {
        await _uploadLocalAttachments(
          value[index],
          token: token,
          draft: draft,
          path: '${path}_$index',
        );
      }
      return;
    }
    if (value is! Map) return;

    final map = Map<String, dynamic>.from(value);
    value
      ..clear()
      ..addAll(map);

    final String attachmentId = _cleanString(value['attachment_id']);
    final String attachmentRef = _cleanString(value['attachment_ref']);
    if (attachmentId.isNotEmpty) {
      value.remove('attachment_ref');
    } else if (attachmentRef.isNotEmpty) {
      final Uint8List? bytes =
          await DocumentDraftAttachmentStore.readBytes(attachmentRef);
      if (bytes != null && bytes.isNotEmpty) {
        final result = await _uploadAttachment(
          token: token,
          draft: draft,
          attachmentRef: attachmentRef,
          bytes: bytes,
          filename: _filenameForAttachment(value, path),
        );
        value['attachment_id'] = result.attachmentId;
        if (result.filename.isNotEmpty) value['filename'] = result.filename;
        value.remove('attachment_ref');
      }
    }

    for (final entry in List<MapEntry<dynamic, dynamic>>.from(value.entries)) {
      await _uploadLocalAttachments(
        entry.value,
        token: token,
        draft: draft,
        path: '${path}_${entry.key}',
      );
    }
  }

  Future<DocumentDraftAttachmentResult> _uploadAttachment({
    required String token,
    required DocumentDraft draft,
    required String attachmentRef,
    required Uint8List bytes,
    required String filename,
  }) async {
    final cacheKey = _attachmentCacheKey(draft.key, attachmentRef, bytes);
    final cached = _uploadedAttachments[cacheKey];
    if (cached != null) return cached;

    final result = await FileManageAPIService.uploadDocumentDraftAttachment(
      token: token,
      draftKey: draft.key,
      draftType: draft.type,
      bytes: bytes,
      filename: filename,
      expiresAt: draft.expiresAt,
    );
    _uploadedAttachments[cacheKey] = result;
    return result;
  }

  Future<void> _downloadRemoteAttachments(
    dynamic value, {
    required String token,
    required String draftKey,
    required String path,
  }) async {
    if (value is List) {
      for (int index = 0; index < value.length; index++) {
        await _downloadRemoteAttachments(
          value[index],
          token: token,
          draftKey: draftKey,
          path: '${path}_$index',
        );
      }
      return;
    }
    if (value is! Map) return;

    final String attachmentId = _cleanString(value['attachment_id']);
    final String attachmentRef = _cleanString(value['attachment_ref']);
    if (attachmentId.isNotEmpty && attachmentRef.isEmpty) {
      final bytes = await FileManageAPIService.getDocumentDraftAttachment(
        token: token,
        draftKey: draftKey,
        attachmentId: attachmentId,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final localRef = await DocumentDraftAttachmentStore.saveBytes(
          draftKey: draftKey,
          attachmentId: _localAttachmentId(attachmentId, value, path),
          bytes: bytes,
        );
        if (localRef != null) {
          value['source'] = 'attachment';
          value['attachment_ref'] = localRef;
        }
      }
    }

    for (final entry in List<MapEntry<dynamic, dynamic>>.from(value.entries)) {
      await _downloadRemoteAttachments(
        entry.value,
        token: token,
        draftKey: draftKey,
        path: '${path}_${entry.key}',
      );
    }
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
    return <String, dynamic>{
      for (final entry in source.entries)
        entry.key: _deepCopyValue(entry.value),
    };
  }

  static dynamic _deepCopyValue(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _deepCopyValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_deepCopyValue).toList(growable: true);
    }
    return value;
  }

  static String _cleanString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text == 'null' ? '' : text;
  }

  static String _filenameForAttachment(
      Map<dynamic, dynamic> value, String path) {
    for (final key in const <String>[
      'filename',
      'name',
      'image',
      'image_before',
      'image_improv',
      'image_after',
    ]) {
      final candidate = _cleanString(value[key]);
      if (candidate.isNotEmpty) return candidate;
    }
    return '${_safeSegment(path)}.png';
  }

  static String _localAttachmentId(
    String attachmentId,
    Map<dynamic, dynamic> value,
    String path,
  ) {
    final filename = _filenameForAttachment(value, path);
    return '${_safeSegment(attachmentId)}_${_safeSegment(filename)}';
  }

  static String _attachmentCacheKey(
    String draftKey,
    String attachmentRef,
    Uint8List bytes,
  ) {
    final int first = bytes.isEmpty ? 0 : bytes.first;
    final int last = bytes.isEmpty ? 0 : bytes.last;
    return '$draftKey|$attachmentRef|${bytes.lengthInBytes}|$first|$last';
  }

  static String _safeSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return safe.isEmpty ? 'draft_attachment' : safe;
  }
}
