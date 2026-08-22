import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../../../l10n/app_localizations.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/responsive_scaffold.dart';

import '../../widgets/app_transitions.dart';
import '../../widgets/signer_picker.dart';
import '../../models/document_draft.dart';
import '../../providers/unified_auth_provider.dart';
import '../../services/document_draft_attachment_store.dart';
import '../../services/document_draft_remote_store.dart';
import '../../services/document_draft_service.dart';
import '../../services/file_manage_api_service.dart';
import '../../utils/auth_utils.dart';
import '../../utils/file_routes.dart';
import '../../utils/signature_task_status.dart';
import '../../utils/user_display_name.dart';
import 'audit_fix_doc_create_page.dart';
import 'photo_doc_create_page.dart';

@visibleForTesting
bool looksLikeDateValue(String value) {
  final String compact = value.trim().replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return false;

  return RegExp(r'^\d{4}[-\/.]\d{1,2}[-\/.]\d{1,2}$').hasMatch(compact) ||
      RegExp(r'^\d{4}年\d{1,2}月\d{1,2}日$').hasMatch(compact);
}

@visibleForTesting
bool looksLikeDatePlaceholder(String value) {
  final String compact = value.trim().replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return true;

  return <String>{
        '年月日',
        'yyyy/mm/dd',
        'yyyy-mm-dd',
        'yyyy.mm.dd',
        'mm/dd/yyyy',
        '__/__/____',
        '____/__/__',
        '--/--/----',
      }.contains(compact.toLowerCase()) ||
      RegExp(r'^[yYmMdD\/_\-.]+$').hasMatch(compact);
}

@visibleForTesting
String normalizeFieldDescription(String description) {
  return description.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

@visibleForTesting
bool shouldTreatFieldAsDate({
  required String description,
  required String raw,
  String? currentValue,
}) {
  final String normalizedDescription = description.toLowerCase();
  final String trimmedRaw = raw.trim();
  final bool hintedByDescription = normalizedDescription.contains('date') ||
      description.contains('日期') ||
      description.contains('年月日') ||
      description.contains('日付');
  final bool explicitDatePlaceholder =
      trimmedRaw.isNotEmpty && looksLikeDatePlaceholder(trimmedRaw);

  return hintedByDescription ||
      looksLikeDateValue(raw) ||
      looksLikeDateValue(currentValue ?? '') ||
      explicitDatePlaceholder;
}

@visibleForTesting
bool isExactProjectNameLabel(String value) {
  final String normalized = normalizeFieldDescription(value);
  return const <String>{
    '工程名稱',
    '工地名稱',
    'projectname',
    'sitename',
  }.contains(normalized);
}

bool _isFillableTableTextField(dynamic field) {
  final String raw = (field['original_text'] as String? ?? '').trim();
  return raw != '{cb}' &&
      raw != 'V' &&
      raw != '{sgn}' &&
      !raw.startsWith('data:image/png');
}

@visibleForTesting
bool isProjectNameField(String description) {
  return isExactProjectNameLabel(description);
}

@visibleForTesting
List<int> findTableProjectNameAutofillTargets(List<dynamic> fields) {
  final Map<(int, int), List<dynamic>> byRow =
      <(int, int), List<dynamic>>{};
  for (final dynamic field in fields) {
    if (field['is_table'] != true) continue;
    final (int, int) key = (
      field['table_index'] as int,
      field['row_index'] as int,
    );
    byRow.putIfAbsent(key, () => <dynamic>[]).add(field);
  }

  final List<int> targetFieldIds = <int>[];
  for (final List<dynamic> rowFields in byRow.values) {
    for (int index = 0; index < rowFields.length; index++) {
      final dynamic field = rowFields[index];
      final String raw = (field['original_text'] as String? ?? '').trim();
      final String description = field['description'] as String? ?? '';
      final bool isProjectLabel =
          isExactProjectNameLabel(raw) || isProjectNameField(description);
      if (!isProjectLabel) continue;

      for (int candidateIndex = index + 1;
          candidateIndex < rowFields.length;
          candidateIndex++) {
        final dynamic candidate = rowFields[candidateIndex];
        final String candidateRaw =
            (candidate['original_text'] as String? ?? '').trim();
        final String candidateDescription =
            candidate['description'] as String? ?? '';
        if (!_isFillableTableTextField(candidate)) continue;
        if (isExactProjectNameLabel(candidateRaw) ||
            isProjectNameField(candidateDescription)) {
          continue;
        }

        targetFieldIds.add(candidate['field_id'] as int);
        break;
      }
      break;
    }
  }

  return targetFieldIds;
}

@visibleForTesting
bool isReviewDateField({
  required String description,
  required String raw,
  String? currentValue,
}) {
  final String normalized = normalizeFieldDescription(description);
  if (normalized.contains('複查日期') ||
      normalized.contains('reviewdate') ||
      normalized.contains('reinspectiondate')) {
    return true;
  }

  return (normalized.contains('複查') ||
          normalized.contains('review') ||
          normalized.contains('reinspection')) &&
      shouldTreatFieldAsDate(
        description: description,
        raw: raw,
        currentValue: currentValue,
      );
}

@visibleForTesting
String resolveInitialFieldText({
  required String description,
  required String raw,
  required String todayDateText,
  bool autoFillReviewDate = false,
  String? currentValue,
}) {
  final String trimmedRaw = raw.trim();
  final bool reviewDateField = isReviewDateField(
    description: description,
    raw: trimmedRaw,
    currentValue: currentValue,
  );
  final bool placeholder =
      trimmedRaw.isEmpty || looksLikeDatePlaceholder(trimmedRaw);

  if (reviewDateField) {
    if (autoFillReviewDate && placeholder) {
      return todayDateText;
    }
    return placeholder ? '' : trimmedRaw;
  }

  if (shouldTreatFieldAsDate(
        description: description,
        raw: trimmedRaw,
        currentValue: currentValue,
      ) &&
      looksLikeDatePlaceholder(trimmedRaw)) {
    return todayDateText;
  }
  return trimmedRaw;
}

/*───────────────────────────────────────────────
  FileEditPage – 支援 {sgn} 指派 / 簽名
  · 若 sign/assignments 已指定 signer，顯示 signer_name / status / comment，且不可修改
  · 若尚未指定 signer，維持下拉選單讓使用者選擇
───────────────────────────────────────────────*/
class FileEditPage extends StatefulWidget {
  const FileEditPage(
      {super.key,
      required this.fileId,
      this.freshlyCreated = false,
      this.clientDraftId});
  final int fileId;
  final bool freshlyCreated;
  final String? clientDraftId;

  @override
  State<FileEditPage> createState() => _FileEditPageState();
}

class _FileEditPageState extends State<FileEditPage> {
  /*───────── 通用欄位狀態 ─────────*/
  final Map<int, TextEditingController> _textCtrls = {};
  final Map<int, FocusNode> _tableFocusNodes = {};
  final Map<int, bool> _checkStates = {};
  final Map<int, Uint8List?> _signatureBytes = {};
  final Map<int, Uint8List?> _tableImageBytes = {};
  final Map<int, bool> _autoFillReviewDates = {};

  // 站點清單與選擇
  final Map<int, dynamic> _sitesById = <int, dynamic>{};
  int? _selectedSiteId;
  int? _originalSiteId;
  int? _latestVersionId;
  String _currentSiteName = '';

  // Busy 狀態
  bool _busy = false;
  void _setBusy(bool v) {
    if (!mounted) return;
    setState(() => _busy = v);
  }

  // 追蹤是否曾經儲存過（供新建文件回上一頁時刪除判斷）
  bool _savedAtLeastOnce = false;

  void _showMissingDocumentRouteRef() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文件缺少公開代碼，無法開啟連結')),
    );
  }

  void _goToPreview({int? versionId}) {
    final String? docRef = _mainDocumentRouteRef?.trim();
    if (docRef == null || docRef.isEmpty) {
      _showMissingDocumentRouteRef();
      context.go(fileListLocation());
      return;
    }

    context.go(
      filePreviewLocation(
        docRef: docRef,
        versionId: versionId,
      ),
    );
  }

  Future<void> _handleBackPress() async {
    if (widget.freshlyCreated && !_savedAtLeastOnce) {
      _setBusy(true);
      try {
        await _draftAutosaver.delete();
        if (!mounted) return;
        await AuthUtils.withAuthRetry(
          context,
          (token) => FileManageAPIService.deleteDocument(
            token: token,
            docId: widget.fileId,
          ),
        );
        await DocumentDraftService.deleteFileDrafts(
          userId: _draftUserId,
          fileId: widget.fileId,
          remoteDeleter: _draftRemoteStore.delete,
          waitForRemote: true,
        );
      } catch (_) {
        // best-effort: ignore errors, still leave the page
      } finally {
        _setBusy(false);
      }
      if (!mounted) return;
      context.go(fileListLocation());
    } else {
      unawaited(_draftAutosaver.flush());
      _goToPreview();
    }
  }

  /*───────── 與簽名任務相關 ─────────*/
  final Map<int, int?> _selectedSigner = {}; // fid → signer_id
  final Map<int, int?> _taskIdOfField = {}; // fid → task_id
  final Map<int, String> _assignedCmt = {}; // fid → comment
  final Map<int, String> _assignedSts = {}; // fid → status
  final Map<int, String> _assignedName = {}; // fid → username
  final Map<int, String> _assignedDisplayName = {}; // fid → display name
  final Map<int, int> _assignedOrder = {}; // fid → order
  final List<int> _signatureFieldOrder = <int>[];
  bool _orderedSigning = false;

  // ★ 新增 ↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓
  final Map<int, String> _assignedFamily = {}; // fid → family_name
  final Map<int, String> _assignedGiven = {}; // fid → given_name
  final Map<int, String> _assignedEmail = {}; // fid → email
  // ★ 新增 ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑
  final Map<int, Uint8List?> _pendingSigBytes =
      {}; // fid → png (current user 未送出)

  List<dynamic> _fields = [];
  bool _loading = true;
  String? _error;
  bool _mainDocumentLocked = false;
  String? _mainDocumentRouteRef;
  List<Map<String, dynamic>> _linkedChildren = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _childCapabilitiesByType =
      <String, Map<String, dynamic>>{};
  final Map<int, BundleChildDraftResult> _pendingChildDrafts =
      <int, BundleChildDraftResult>{};
  final List<BundleChildDraftResult> _newChildDrafts =
      <BundleChildDraftResult>[];
  final Map<int, dynamic> _fieldsById = <int, dynamic>{};
  final Map<String, dynamic> _fieldByDescription = <String, dynamic>{};
  final List<int> _signatureFieldIdsCache = <int>[];
  final Set<int> _projectNameFieldIdSet = <int>{};
  final List<_TableSectionInfo> _tableSections = <_TableSectionInfo>[];
  final List<_EditContentItem> _editContentItems = <_EditContentItem>[];
  late final DocumentDraftRemoteStore _draftRemoteStore;
  late final DocumentDraftAutosaver _draftAutosaver;
  int? _draftUserId;
  late final String _clientDraftId;
  bool _draftRestoreChecked = false;
  bool _suppressDraftAutosave = false;
  final Set<int> _draftObservedTextFields = <int>{};
  final Set<int> _draftDirtySignatureImageFields = <int>{};
  final Set<int> _draftDirtyTableImageFields = <int>{};
  final Set<int> _draftDirtyPendingSignatureFields = <int>{};

  bool _isSiteField(String description) => isProjectNameField(description);

  String _draftKey() {
    if (widget.freshlyCreated) {
      return DocumentDraftService.buildCreateKey(
        draftType: 'file_edit',
        clientDraftId: _clientDraftId,
      );
    }
    return DocumentDraftService.buildKey(
      draftType: 'file_edit',
      userId: _draftUserId,
      fileId: widget.fileId,
    );
  }

  void _scheduleDraftAutosave() {
    if (_loading ||
        _suppressDraftAutosave ||
        _mainDocumentLocked ||
        widget.freshlyCreated && !_savedAtLeastOnce && _fields.isEmpty) {
      return;
    }
    _draftAutosaver.schedule();
  }

  void _attachDraftListener(int fieldId) {
    if (!_draftObservedTextFields.add(fieldId)) return;
    _textCtrls[fieldId]?.addListener(_scheduleDraftAutosave);
  }

  void _attachDraftListenersForTextCtrls() {
    for (final int fieldId in _textCtrls.keys) {
      _attachDraftListener(fieldId);
    }
  }

  Map<String, dynamic> _jsonSafePayload(Map<String, dynamic> payload) {
    return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(payload)) as Map,
    );
  }

  String _safeAttachmentName(String name) {
    return name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  Future<List<Map<String, dynamic>>> _serializeBundleFiles(
    String group,
    List<BundleUploadFile> files,
  ) async {
    final String draftKey = _draftKey();
    final List<Map<String, dynamic>> serialized = <Map<String, dynamic>>[];
    for (int index = 0; index < files.length; index += 1) {
      final BundleUploadFile file = files[index];
      final String safeName = _safeAttachmentName(file.filename);
      final String? bytesRef = await DocumentDraftAttachmentStore.saveBytes(
        draftKey: draftKey,
        attachmentId: '$group-$index-$safeName',
        bytes: file.bytes,
      );
      if (bytesRef == null) continue;

      String? draftBytesRef;
      final Uint8List? draftBytes = file.draftBytes;
      if (draftBytes != null) {
        draftBytesRef = await DocumentDraftAttachmentStore.saveBytes(
          draftKey: draftKey,
          attachmentId: '$group-$index-draft-$safeName',
          bytes: draftBytes,
        );
      }

      serialized.add(<String, dynamic>{
        'filename': file.filename,
        'bytes_ref': bytesRef,
        if (draftBytesRef != null) 'draft_bytes_ref': draftBytesRef,
      });
    }
    return serialized;
  }

  Future<List<BundleUploadFile>> _restoreBundleFiles(dynamic raw) async {
    if (raw is! List) return const <BundleUploadFile>[];

    final List<BundleUploadFile> files = <BundleUploadFile>[];
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> data = Map<String, dynamic>.from(item);
      final String filename = data['filename']?.toString() ?? 'draft-file';
      final String? bytesRef = data['bytes_ref'] as String?;
      if (bytesRef == null || bytesRef.isEmpty) continue;

      final Uint8List? bytes =
          await DocumentDraftAttachmentStore.readBytes(bytesRef);
      if (bytes == null) continue;

      Uint8List? draftBytes;
      final String? draftBytesRef = data['draft_bytes_ref'] as String?;
      if (draftBytesRef != null && draftBytesRef.isNotEmpty) {
        draftBytes =
            await DocumentDraftAttachmentStore.readBytes(draftBytesRef);
      }

      files.add(
        BundleUploadFile(
          filename: filename,
          bytes: bytes,
          draftBytes: draftBytes,
        ),
      );
    }
    return files;
  }

  Future<Map<String, dynamic>> _serializeDirtyFieldBytes(
    String group,
    Map<int, Uint8List?> bytesByField,
    Set<int> dirtyFieldIds,
  ) async {
    final String draftKey = _draftKey();
    final Map<String, dynamic> serialized = <String, dynamic>{};
    for (final int fieldId in dirtyFieldIds) {
      final Uint8List? bytes = bytesByField[fieldId];
      if (bytes == null || bytes.isEmpty) continue;
      final String? reference = await DocumentDraftAttachmentStore.saveBytes(
        draftKey: draftKey,
        attachmentId: '$group-$fieldId.png',
        bytes: bytes,
      );
      if (reference != null) {
        serialized[fieldId.toString()] = reference;
      }
    }
    return serialized;
  }

  Future<Map<int, Uint8List?>> _restoreFieldBytes(dynamic raw) async {
    if (raw is! Map) return const <int, Uint8List?>{};

    final Map<int, Uint8List?> restored = <int, Uint8List?>{};
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      final int? fieldId = _parseDraftFieldId(entry.key.toString());
      final String? reference = entry.value as String?;
      if (fieldId == null || reference == null || reference.isEmpty) continue;
      final Uint8List? bytes =
          await DocumentDraftAttachmentStore.readBytes(reference);
      if (bytes != null) {
        restored[fieldId] = bytes;
      }
    }
    return restored;
  }

  Future<Map<String, dynamic>?> _buildLocalDraftPayload() async {
    if (_fields.isEmpty) return null;

    final Map<String, dynamic> newChildDrafts = <String, dynamic>{};
    final List<Map<String, dynamic>> newChildren = <Map<String, dynamic>>[];
    for (int index = 0; index < _newChildDrafts.length; index += 1) {
      final BundleChildDraftResult draft = _newChildDrafts[index];
      newChildren.add(<String, dynamic>{
        'document_type_name': draft.documentTypeName,
        'payload': _jsonSafePayload(draft.payload),
        'files': await _serializeBundleFiles('new-child-$index', draft.files),
      });
    }
    if (newChildren.isNotEmpty) {
      newChildDrafts['items'] = newChildren;
    }

    final Map<String, dynamic> pendingChildren = <String, dynamic>{};
    for (final MapEntry<int, BundleChildDraftResult> entry
        in _pendingChildDrafts.entries) {
      final BundleChildDraftResult draft = entry.value;
      pendingChildren[entry.key.toString()] = <String, dynamic>{
        'document_type_name': draft.documentTypeName,
        'payload': _jsonSafePayload(draft.payload),
        'files': await _serializeBundleFiles(
          'pending-child-${entry.key}',
          draft.files,
        ),
      };
    }

    final Map<String, dynamic> signatureBytes = await _serializeDirtyFieldBytes(
      'signature-image',
      _signatureBytes,
      _draftDirtySignatureImageFields,
    );
    final Map<String, dynamic> tableImageBytes =
        await _serializeDirtyFieldBytes(
      'table-image',
      _tableImageBytes,
      _draftDirtyTableImageFields,
    );
    final Map<String, dynamic> pendingSignatureBytes =
        await _serializeDirtyFieldBytes(
      'pending-signature',
      _pendingSigBytes,
      _draftDirtyPendingSignatureFields,
    );

    final Map<String, dynamic> payload = <String, dynamic>{
      'selected_site_id': _selectedSiteId,
      'ordered_signing': _orderedSigning,
      'signature_order': _signatureFieldOrder,
      'text_fields': <String, dynamic>{
        for (final MapEntry<int, TextEditingController> entry
            in _textCtrls.entries)
          entry.key.toString(): entry.value.text,
      },
      'check_states': <String, dynamic>{
        for (final MapEntry<int, bool> entry in _checkStates.entries)
          entry.key.toString(): entry.value,
      },
      'selected_signers': <String, dynamic>{
        for (final MapEntry<int, int?> entry in _selectedSigner.entries)
          if (entry.value != null) entry.key.toString(): entry.value,
      },
      'auto_fill_review_dates': <String, dynamic>{
        for (final MapEntry<int, bool> entry in _autoFillReviewDates.entries)
          entry.key.toString(): entry.value,
      },
      if (newChildren.isNotEmpty) 'new_child_drafts': newChildDrafts,
      if (pendingChildren.isNotEmpty) 'pending_child_drafts': pendingChildren,
      if (signatureBytes.isNotEmpty) 'signature_bytes': signatureBytes,
      if (tableImageBytes.isNotEmpty) 'table_image_bytes': tableImageBytes,
      if (pendingSignatureBytes.isNotEmpty)
        'pending_signature_bytes': pendingSignatureBytes,
    };

    return payload;
  }

  int? _parseDraftFieldId(String key) => int.tryParse(key);

  Future<void> _maybeRestoreLocalDraft() async {
    if (_draftRestoreChecked || !mounted || _error != null) return;
    _draftRestoreChecked = true;

    final DocumentDraft? draft = await _draftAutosaver.load();
    if (draft == null || !mounted) return;

    final bool? restore = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('找到未完成草稿'),
        content: Text(
          '上次自動保存於 ${DateFormat('yyyy/MM/dd HH:mm').format(draft.updatedAt.toLocal())}，是否恢復？',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('捨棄'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢復草稿'),
          ),
        ],
      ),
    );

    if (restore == true) {
      await _restoreLocalDraft(draft);
      return;
    }

    await _draftAutosaver.delete();
  }

  Future<void> _restoreLocalDraft(DocumentDraft draft) async {
    _suppressDraftAutosave = true;
    try {
      final Map<String, dynamic> payload = draft.payload;
      final int? siteId = (payload['selected_site_id'] as num?)?.toInt();

      final Map<int, String> textFields = <int, String>{};
      final dynamic rawTextFields = payload['text_fields'];
      if (rawTextFields is Map) {
        for (final MapEntry<dynamic, dynamic> entry in rawTextFields.entries) {
          final int? fieldId = _parseDraftFieldId(entry.key.toString());
          if (fieldId != null) {
            textFields[fieldId] = entry.value?.toString() ?? '';
          }
        }
      }

      final Map<int, bool> checkStates = <int, bool>{};
      final dynamic rawCheckStates = payload['check_states'];
      if (rawCheckStates is Map) {
        for (final MapEntry<dynamic, dynamic> entry in rawCheckStates.entries) {
          final int? fieldId = _parseDraftFieldId(entry.key.toString());
          if (fieldId != null && entry.value is bool) {
            checkStates[fieldId] = entry.value as bool;
          }
        }
      }

      final Map<int, int?> selectedSigners = <int, int?>{};
      final dynamic rawSelectedSigners = payload['selected_signers'];
      if (rawSelectedSigners is Map) {
        for (final MapEntry<dynamic, dynamic> entry
            in rawSelectedSigners.entries) {
          final int? fieldId = _parseDraftFieldId(entry.key.toString());
          final int? signerId = (entry.value as num?)?.toInt();
          if (fieldId != null) {
            selectedSigners[fieldId] = signerId;
          }
        }
      }

      final Map<int, bool> autoFillDates = <int, bool>{};
      final dynamic rawAutoFillDates = payload['auto_fill_review_dates'];
      if (rawAutoFillDates is Map) {
        for (final MapEntry<dynamic, dynamic> entry
            in rawAutoFillDates.entries) {
          final int? fieldId = _parseDraftFieldId(entry.key.toString());
          if (fieldId != null && entry.value is bool) {
            autoFillDates[fieldId] = entry.value as bool;
          }
        }
      }

      final List<int> signatureOrder = <int>[
        for (final dynamic value
            in (payload['signature_order'] as List<dynamic>? ??
                const <dynamic>[]))
          if (value is num) value.toInt(),
      ];

      final List<BundleChildDraftResult> newChildren =
          <BundleChildDraftResult>[];
      final dynamic rawNewChildren =
          (payload['new_child_drafts'] as Map?)?['items'];
      if (rawNewChildren is List) {
        for (final dynamic item in rawNewChildren) {
          if (item is! Map) continue;
          final Map<String, dynamic> data = Map<String, dynamic>.from(item);
          final dynamic childPayload = data['payload'];
          if (childPayload is! Map) continue;
          newChildren.add(
            BundleChildDraftResult(
              documentTypeName:
                  data['document_type_name']?.toString() ?? '圖片表格列',
              payload: Map<String, dynamic>.from(childPayload),
              files: await _restoreBundleFiles(data['files']),
            ),
          );
        }
      }

      final Map<int, BundleChildDraftResult> pendingChildren =
          <int, BundleChildDraftResult>{};
      final dynamic rawPendingChildren = payload['pending_child_drafts'];
      if (rawPendingChildren is Map) {
        for (final MapEntry<dynamic, dynamic> entry
            in rawPendingChildren.entries) {
          final int? documentId = int.tryParse(entry.key.toString());
          if (documentId == null || entry.value is! Map) continue;
          final Map<String, dynamic> data =
              Map<String, dynamic>.from(entry.value as Map);
          final dynamic childPayload = data['payload'];
          if (childPayload is! Map) continue;
          pendingChildren[documentId] = BundleChildDraftResult(
            documentTypeName: data['document_type_name']?.toString() ?? '圖片表格列',
            payload: Map<String, dynamic>.from(childPayload),
            files: await _restoreBundleFiles(data['files']),
          );
        }
      }

      final Map<int, Uint8List?> restoredSignatureBytes =
          await _restoreFieldBytes(payload['signature_bytes']);
      final Map<int, Uint8List?> restoredTableImageBytes =
          await _restoreFieldBytes(payload['table_image_bytes']);
      final Map<int, Uint8List?> restoredPendingSignatureBytes =
          await _restoreFieldBytes(payload['pending_signature_bytes']);

      if (!mounted) return;
      setState(() {
        if (siteId != null) {
          _selectedSiteId = siteId;
          _currentSiteName = _resolveCurrentSiteName(preferredSiteId: siteId);
        }

        for (final MapEntry<int, String> entry in textFields.entries) {
          final TextEditingController controller = _textCtrls.putIfAbsent(
            entry.key,
            () => TextEditingController(),
          );
          if (controller.text != entry.value) {
            controller.text = entry.value;
          }
        }

        _checkStates.addAll(checkStates);
        _selectedSigner.addAll(selectedSigners);
        _autoFillReviewDates.addAll(autoFillDates);
        _orderedSigning = payload['ordered_signing'] == true;

        if (signatureOrder.isNotEmpty) {
          _signatureFieldOrder
            ..clear()
            ..addAll(signatureOrder);
          _syncSignatureFieldOrder();
        }

        _newChildDrafts
          ..clear()
          ..addAll(newChildren);
        _pendingChildDrafts
          ..clear()
          ..addAll(pendingChildren);
        _signatureBytes.addAll(restoredSignatureBytes);
        _tableImageBytes.addAll(restoredTableImageBytes);
        _pendingSigBytes.addAll(restoredPendingSignatureBytes);
        _draftDirtySignatureImageFields.addAll(restoredSignatureBytes.keys);
        _draftDirtyTableImageFields.addAll(restoredTableImageBytes.keys);
        _draftDirtyPendingSignatureFields.addAll(
          restoredPendingSignatureBytes.keys,
        );
        _syncProjectNameFieldTexts();
      });
      _attachDraftListenersForTextCtrls();
    } finally {
      _suppressDraftAutosave = false;
    }
  }

  void _rebuildFieldIndexes() {
    _fieldsById.clear();
    _fieldByDescription.clear();
    _signatureFieldIdsCache.clear();
    _projectNameFieldIdSet.clear();

    for (final dynamic field in _fields) {
      final int fieldId = field['field_id'] as int;
      final String description = field['description'] as String? ?? '';
      final String raw = (field['original_text'] as String? ?? '').trim();

      _fieldsById[fieldId] = field;
      _fieldByDescription.putIfAbsent(description, () => field);
      if (raw == '{sgn}') {
        _signatureFieldIdsCache.add(fieldId);
      }
      if (_isSiteField(description)) {
        _projectNameFieldIdSet.add(fieldId);
      }
    }

    _projectNameFieldIdSet.addAll(findTableProjectNameAutofillTargets(_fields));
    _rebuildDocumentLayoutCache();
  }

  void _rebuildDocumentLayoutCache() {
    _tableSections
      ..clear()
      ..addAll(_buildTableSectionInfos());

    _editContentItems.clear();
    final List<dynamic> headerFields = <dynamic>[];
    final List<dynamic> bodyFields = <dynamic>[];
    final List<dynamic> footerFields = <dynamic>[];
    for (final dynamic field in _fields) {
      if (field['is_table'] == true) continue;
      switch (field['part']) {
        case 'header':
          headerFields.add(field);
          break;
        case 'body':
          bodyFields.add(field);
          break;
        case 'footer':
          footerFields.add(field);
          break;
      }
    }

    void addParagraphSection(String part, List<dynamic> sectionFields) {
      if (sectionFields.isEmpty) return;

      _editContentItems.add(_EditContentItem.sectionHeader(part));
      for (final dynamic field in sectionFields) {
        _editContentItems.add(_EditContentItem.paragraphField(field));
      }
      _editContentItems.add(_EditContentItem.spacer(20));
    }

    addParagraphSection('header', headerFields);
    addParagraphSection('body', bodyFields);
    addParagraphSection('footer', footerFields);

    for (final _TableSectionInfo section in _tableSections) {
      _editContentItems.add(_EditContentItem.tableSection(section));
    }

    _editContentItems
      ..add(_EditContentItem.spacer(8))
      ..add(const _EditContentItem(_EditContentItemType.signatureSection))
      ..add(const _EditContentItem(_EditContentItemType.bundleSection))
      ..add(const _EditContentItem(_EditContentItemType.saveButton))
      ..add(_EditContentItem.spacer(16));
  }

  List<_TableSectionInfo> _buildTableSectionInfos() {
    final Map<int, List<dynamic>> byTid = <int, List<dynamic>>{};
    for (final dynamic field in _fields) {
      if (field['is_table'] != true) continue;
      byTid
          .putIfAbsent(field['table_index'] as int, () => <dynamic>[])
          .add(field);
    }

    final List<_TableSectionInfo> sections = <_TableSectionInfo>[];
    for (final int tableIndex in (byTid.keys.toList()..sort())) {
      final Map<int, List<dynamic>> byRow = <int, List<dynamic>>{};
      for (final dynamic field in byTid[tableIndex]!) {
        byRow
            .putIfAbsent(field['row_index'] as int, () => <dynamic>[])
            .add(field);
      }
      final List<int> rows = byRow.keys.toList()..sort();
      final Map<int, int> rowIndexByNumber = <int, int>{
        for (int i = 0; i < rows.length; i++) rows[i]: i,
      };

      int maxCol = 0;
      final List<_TableCellInfo> cellInfos = <_TableCellInfo>[];
      for (final int row in rows) {
        int colCursor = 0;
        for (final dynamic field in byRow[row]!) {
          final int colSpan = field['col_span'] as int? ?? 1;
          final int rowSpan = field['row_span'] as int? ?? 1;
          cellInfos.add(
            _TableCellInfo(
              field: field,
              row: row,
              col: colCursor,
              colSpan: colSpan,
              rowSpan: rowSpan,
              mergedFieldIds: <int>[field['field_id'] as int],
            ),
          );
          colCursor += colSpan;
        }
        if (colCursor > maxCol) {
          maxCol = colCursor;
        }
      }

      sections.add(
        _TableSectionInfo(
          tableIndex: tableIndex,
          rows: rows,
          rowIndexByNumber: rowIndexByNumber,
          maxCol: maxCol,
          cells: _autoMergeCells(cellInfos, rows),
        ),
      );
    }

    return sections;
  }

  void _syncProjectNameFieldTexts() {
    final String resolvedSiteName = _resolveCurrentSiteName(
      preferredName: _currentSiteName,
      preferredSiteId: _selectedSiteId ?? _originalSiteId,
    );
    if (resolvedSiteName.isEmpty) return;

    _currentSiteName = resolvedSiteName;
    for (final dynamic field in _fields) {
      final int fieldId = field['field_id'] as int;
      if (!_projectNameFieldIdSet.contains(fieldId)) continue;

      _textCtrls.putIfAbsent(
        fieldId,
        () => TextEditingController(text: resolvedSiteName),
      );
      _attachDraftListener(fieldId);
      if (_textCtrls[fieldId]!.text != resolvedSiteName) {
        _textCtrls[fieldId]!.text = resolvedSiteName;
      }
    }
  }

  String _normalizeSiteName(dynamic value) {
    if (value == null) return '';
    final String text = value.toString().trim();
    return text == 'null' ? '' : text;
  }

  String _siteNameFromSiteId(int? siteId) {
    if (siteId == null) return '';
    final dynamic site = _sitesById[siteId];
    if (site == null) return '';
    return _normalizeSiteName(site['name']);
  }

  String _resolveCurrentSiteName({
    dynamic preferredName,
    int? preferredSiteId,
    dynamic fieldValue,
  }) {
    final String preferred = _normalizeSiteName(preferredName);
    if (preferred.isNotEmpty) return preferred;

    final String preferredSite = _siteNameFromSiteId(preferredSiteId);
    if (preferredSite.isNotEmpty) return preferredSite;

    final String selectedSite = _siteNameFromSiteId(_selectedSiteId);
    if (selectedSite.isNotEmpty) return selectedSite;

    final String originalSite = _siteNameFromSiteId(_originalSiteId);
    if (originalSite.isNotEmpty) return originalSite;

    return _normalizeSiteName(fieldValue);
  }

  dynamic _currentSiteObject() {
    final int? siteId = _selectedSiteId ?? _originalSiteId;
    if (siteId == null && _currentSiteName.trim().isEmpty) {
      return null;
    }

    final dynamic existing = siteId == null ? null : _sitesById[siteId];
    if (existing != null) {
      return existing;
    }

    return <String, dynamic>{
      'id': siteId,
      'name': _currentSiteName.trim(),
    };
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> _fetchBundleResponse() async {
    return await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.getFileBundle(
        token: token,
        fileId: widget.fileId,
      ),
    );
  }

  void _applyBundleResponse(Map<String, dynamic> bundleResponse) {
    final Map<String, dynamic> mainDocument =
        bundleResponse['main_document'] is Map
            ? Map<String, dynamic>.from(bundleResponse['main_document'] as Map)
            : <String, dynamic>{};

    _mainDocumentLocked = mainDocument['is_locked'] == true;
    _mainDocumentRouteRef =
        documentRouteRefFromMap(mainDocument) ?? _mainDocumentRouteRef;
    _latestVersionId = (mainDocument['latest_version_id'] as num?)?.toInt() ??
        _latestVersionId;
    _linkedChildren = _mapList(bundleResponse['linked_children']);

    final Object? rawRootCapabilities =
        bundleResponse['child_type_capabilities'];
    if (rawRootCapabilities is List &&
        rawRootCapabilities.whereType<Map>().isNotEmpty) {
      _setChildCapabilities(rawRootCapabilities);
      return;
    }

    _setChildCapabilities(
      _linkedChildren.map<Object?>(
        (Map<String, dynamic> item) => item['capabilities'],
      ),
    );
  }

  void _setChildCapabilities(Iterable<Object?> rawCapabilities) {
    _childCapabilitiesByType.clear();
    for (final Object? rawCapability in rawCapabilities) {
      if (rawCapability is! Map) continue;
      final Map<String, dynamic> capability =
          Map<String, dynamic>.from(rawCapability);
      final String typeName =
          (capability['document_type_name'] as String? ?? '').trim();
      if (typeName.isEmpty) continue;
      _childCapabilitiesByType.putIfAbsent(typeName, () => capability);
    }
  }

  Future<void> _refreshBundleState() async {
    try {
      final Map<String, dynamic> bundleResponse = await _fetchBundleResponse();
      if (!mounted) return;
      setState(() => _applyBundleResponse(bundleResponse));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新整理子文件失敗：$e')),
      );
    }
  }

  Map<String, dynamic>? _childCapability(String documentTypeName) {
    return _childCapabilitiesByType[documentTypeName];
  }

  bool _bundleCapabilityFlag(
    String documentTypeName,
    String key, {
    bool defaultValue = true,
  }) {
    final Map<String, dynamic>? capability = _childCapability(documentTypeName);
    if (capability == null) return defaultValue;
    final dynamic value = capability[key];
    return value is bool ? value : defaultValue;
  }

  Map<String, dynamic> _childDocument(Map<String, dynamic> item) {
    return item['document'] is Map
        ? Map<String, dynamic>.from(item['document'] as Map)
        : <String, dynamic>{};
  }

  Map<String, dynamic> _childLink(Map<String, dynamic> item) {
    return item['link'] is Map
        ? Map<String, dynamic>.from(item['link'] as Map)
        : <String, dynamic>{};
  }

  Map<String, dynamic> _childFieldsPayload(Map<String, dynamic> item) {
    return item['fields'] is Map
        ? Map<String, dynamic>.from(item['fields'] as Map)
        : <String, dynamic>{};
  }

  int _childDocumentId(Map<String, dynamic> item) {
    final Map<String, dynamic> document = _childDocument(item);
    final Map<String, dynamic> link = _childLink(item);
    return (document['id'] as num?)?.toInt() ??
        (link['document_id'] as num?)?.toInt() ??
        0;
  }

  int _childLinkId(Map<String, dynamic> item) {
    return (_childLink(item)['link_id'] as num?)?.toInt() ?? 0;
  }

  int? _childEffectiveVersionId(Map<String, dynamic> item) {
    return (_childLink(item)['effective_version_id'] as num?)?.toInt();
  }

  int? _childPinnedVersionId(Map<String, dynamic> item) {
    return (_childLink(item)['pinned_child_version_id'] as num?)?.toInt();
  }

  String _childDocumentTypeName(Map<String, dynamic> item) {
    final Map<String, dynamic> link = _childLink(item);
    final Map<String, dynamic> fields = _childFieldsPayload(item);
    return (link['document_type_name'] as String? ??
            fields['document_type_name'] as String? ??
            '')
        .trim();
  }

  String _childFullFileCode(Map<String, dynamic> item) {
    final Map<String, dynamic> document = _childDocument(item);
    final Map<String, dynamic> link = _childLink(item);
    return (document['full_file_code'] as String? ??
            link['full_file_code'] as String? ??
            '')
        .trim();
  }

  bool _childLocked(Map<String, dynamic> item) {
    return _childLink(item)['is_locked'] == true;
  }

  String _linkedChildSummary(Map<String, dynamic> item) {
    final BundleChildDraftResult? pendingDraft =
        _pendingChildDrafts[_childDocumentId(item)];
    final Map<String, dynamic> effectivePayload = pendingDraft?.payload ??
        (_childFieldsPayload(item)['editor_payload'] is Map
            ? Map<String, dynamic>.from(
                _childFieldsPayload(item)['editor_payload'] as Map,
              )
            : <String, dynamic>{});

    final String type = _childDocumentTypeName(item);
    final List<dynamic> items =
        (effectivePayload['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (type == '圖片表格列') {
      return '圖片 ${items.length} 組';
    }
    if (type == '缺失稽核改善') {
      return '改善 ${items.length} 組';
    }
    return '${items.length} 筆';
  }

  String _newChildSummary(BundleChildDraftResult draft) {
    final List<dynamic> items =
        (draft.payload['items'] as List<dynamic>?) ?? const <dynamic>[];
    if (draft.documentTypeName == '圖片表格列') {
      return '圖片 ${items.length} 組';
    }
    if (draft.documentTypeName == '缺失稽核改善') {
      return '改善 ${items.length} 組';
    }
    return '${items.length} 筆';
  }

  Future<BundleChildDraftResult?> _openBundleChildEditor({
    required String documentTypeName,
    required Map<String, dynamic>? initialPayload,
    List<BundleUploadFile> initialFiles = const <BundleUploadFile>[],
    int? existingDocumentId,
  }) async {
    final dynamic site = _currentSiteObject();
    if (documentTypeName == '圖片表格列') {
      return await pushAppPage<BundleChildDraftResult>(
        context,
        builder: (_) => PhotoDocCreatePage(
          initSite: site,
          fileId: existingDocumentId,
          draftMode: true,
          initialEditorPayload: initialPayload,
          initialDraftFiles: initialFiles,
        ),
      );
    }
    if (documentTypeName == '缺失稽核改善') {
      return await pushAppPage<BundleChildDraftResult>(
        context,
        builder: (_) => AuditFixDocCreatePage(
          initSite: site,
          fileId: existingDocumentId,
          draftMode: true,
          initialEditorPayload: initialPayload,
          initialDraftFiles: initialFiles,
        ),
      );
    }
    return null;
  }

  Future<void> _createBundleChildDraft(String documentTypeName) async {
    final BundleChildDraftResult? result = await _openBundleChildEditor(
      documentTypeName: documentTypeName,
      initialPayload: null,
    );
    if (result == null || !mounted) return;
    setState(() => _newChildDrafts.add(result));
    _scheduleDraftAutosave();
  }

  Future<void> _editNewChildDraft(int index) async {
    if (index < 0 || index >= _newChildDrafts.length) return;
    final BundleChildDraftResult currentDraft = _newChildDrafts[index];
    final BundleChildDraftResult? nextDraft = await _openBundleChildEditor(
      documentTypeName: currentDraft.documentTypeName,
      initialPayload: currentDraft.payload,
      initialFiles: currentDraft.files,
    );
    if (nextDraft == null || !mounted) return;
    setState(() => _newChildDrafts[index] = nextDraft);
    _scheduleDraftAutosave();
  }

  Future<void> _editLinkedChildDraft(Map<String, dynamic> item) async {
    if (_childLocked(item)) return;

    final int documentId = _childDocumentId(item);
    final BundleChildDraftResult? currentDraft =
        _pendingChildDrafts[documentId];
    final Map<String, dynamic> fields = _childFieldsPayload(item);
    final Map<String, dynamic>? initialPayload = currentDraft?.payload ??
        (fields['editor_payload'] is Map
            ? Map<String, dynamic>.from(fields['editor_payload'] as Map)
            : null);
    if (initialPayload == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('這個子文件目前沒有可編輯的結構化內容')),
      );
      return;
    }

    final BundleChildDraftResult? nextDraft = await _openBundleChildEditor(
      documentTypeName: _childDocumentTypeName(item),
      initialPayload: initialPayload,
      initialFiles: currentDraft?.files ?? const <BundleUploadFile>[],
      existingDocumentId: documentId,
    );
    if (nextDraft == null || !mounted) return;
    setState(() => _pendingChildDrafts[documentId] = nextDraft);
    _scheduleDraftAutosave();
  }

  Map<String, dynamic> _normalizeImageContract(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    final String text = raw?.toString().trim() ?? '';
    if (text.isEmpty) {
      return const <String, dynamic>{'mode': 'delete'};
    }
    return <String, dynamic>{'mode': 'keep', 'url': text};
  }

  Map<String, dynamic> _buildPhotoUpdatePayload(BundleChildDraftResult draft) {
    final Map<String, dynamic> payload =
        Map<String, dynamic>.from(draft.payload);
    final List<dynamic> items =
        (payload['items'] as List<dynamic>?) ?? const <dynamic>[];
    return <String, dynamic>{
      'type': 'photo_doc',
      'project_name': payload['project_name'] as String? ?? '',
      'items': items.whereType<Map>().map((Map item) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(item);
        return <String, dynamic>{
          'index': map['index'],
          'number': map['number'],
          'location': map['location'] as String? ?? '',
          'date': map['date'] as String? ?? '',
          'description': map['description'] as String? ?? '',
          'image': _normalizeImageContract(map['image']),
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _buildPhotoCreatePayload(BundleChildDraftResult draft) {
    final Map<String, dynamic> updatePayload = _buildPhotoUpdatePayload(draft);
    final List<dynamic> items =
        (updatePayload['items'] as List<dynamic>?) ?? const <dynamic>[];
    int fallbackNumber = 1;
    final List<Map<String, dynamic>> images = items
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .where((Map<String, dynamic> item) {
      final Map<String, dynamic> image =
          Map<String, dynamic>.from(item['image'] as Map);
      return (image['mode'] as String? ?? '') == 'upload';
    }).map((Map<String, dynamic> item) {
      final Map<String, dynamic> image =
          Map<String, dynamic>.from(item['image'] as Map);
      final String uploadKey = (image['upload_key'] as String? ?? '').trim();
      final String number = (item['number'] as String? ?? '').trim().isNotEmpty
          ? (item['number'] as String).trim()
          : '${fallbackNumber++}';
      return <String, dynamic>{
        'filename': uploadKey,
        'data_uri': uploadKey,
        'location': item['location'] as String? ?? '',
        'description': item['description'] as String? ?? '',
        'number': number,
        'date': item['date'] as String? ?? '',
      };
    }).toList();

    return <String, dynamic>{
      'images': images,
      if ((updatePayload['project_name'] as String? ?? '').trim().isNotEmpty)
        'project_name': updatePayload['project_name'],
    };
  }

  Map<String, dynamic> _buildAuditUpdatePayload(BundleChildDraftResult draft) {
    final Map<String, dynamic> payload =
        Map<String, dynamic>.from(draft.payload);
    final List<dynamic> items =
        (payload['items'] as List<dynamic>?) ?? const <dynamic>[];

    Map<String, dynamic> normalizeStage(Map<String, dynamic> stage) {
      return <String, dynamic>{
        'description': stage['description'] as String? ?? '',
        'date': stage['date'] as String? ?? '',
        'image': _normalizeImageContract(stage['image']),
      };
    }

    return <String, dynamic>{
      'type': 'audit_fix',
      'audit_date': payload['audit_date'] as String? ?? '',
      'items': items.whereType<Map>().map((Map item) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(item);
        return <String, dynamic>{
          'group_index': map['group_index'],
          'before': normalizeStage(
            map['before'] is Map
                ? Map<String, dynamic>.from(map['before'] as Map)
                : <String, dynamic>{},
          ),
          'improv': normalizeStage(
            map['improv'] is Map
                ? Map<String, dynamic>.from(map['improv'] as Map)
                : <String, dynamic>{},
          ),
          'after': normalizeStage(
            map['after'] is Map
                ? Map<String, dynamic>.from(map['after'] as Map)
                : <String, dynamic>{},
          ),
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _buildAuditCreatePayload(BundleChildDraftResult draft) {
    final Map<String, dynamic> updatePayload = _buildAuditUpdatePayload(draft);
    final List<dynamic> items =
        (updatePayload['items'] as List<dynamic>?) ?? const <dynamic>[];

    String imageKeyOf(Map<String, dynamic> stage) {
      final Map<String, dynamic> image =
          Map<String, dynamic>.from(stage['image'] as Map);
      if ((image['mode'] as String? ?? '') != 'upload') {
        return '';
      }
      return (image['upload_key'] as String? ?? '').trim();
    }

    return <String, dynamic>{
      'audit_date': updatePayload['audit_date'] as String? ?? '',
      'items': items.whereType<Map>().map((Map item) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(item);
        final Map<String, dynamic> before = Map<String, dynamic>.from(
          map['before'] as Map? ?? <String, dynamic>{},
        );
        final Map<String, dynamic> improv = Map<String, dynamic>.from(
          map['improv'] as Map? ?? <String, dynamic>{},
        );
        final Map<String, dynamic> after = Map<String, dynamic>.from(
          map['after'] as Map? ?? <String, dynamic>{},
        );
        return <String, dynamic>{
          'desc_before_impr': before['description'] as String? ?? '',
          'improv_desc': improv['description'] as String? ?? '',
          'impr_desc': after['description'] as String? ?? '',
          'image_before': imageKeyOf(before),
          'image_improv': imageKeyOf(improv),
          'image_after': imageKeyOf(after),
        };
      }).toList(),
    };
  }

  List<BundleUploadFile> _collectBundleFiles() {
    return <BundleUploadFile>[
      ..._newChildDrafts.expand((BundleChildDraftResult draft) => draft.files),
      ..._pendingChildDrafts.values
          .expand((BundleChildDraftResult draft) => draft.files),
    ];
  }

  List<Map<String, dynamic>> _buildChildUpdatesForBundle() {
    return _linkedChildren.where((Map<String, dynamic> item) {
      return _pendingChildDrafts.containsKey(_childDocumentId(item));
    }).map((Map<String, dynamic> item) {
      final int documentId = _childDocumentId(item);
      final BundleChildDraftResult draft = _pendingChildDrafts[documentId]!;
      final String typeName = _childDocumentTypeName(item);
      return <String, dynamic>{
        'child_document_id': documentId,
        'base_version_id': _childEffectiveVersionId(item),
        'update': typeName == '圖片表格列'
            ? _buildPhotoUpdatePayload(draft)
            : _buildAuditUpdatePayload(draft),
      };
    }).toList();
  }

  Map<String, dynamic> _buildBundleSaveMetadata({
    required List<Map<String, dynamic>> fillData,
  }) {
    final List<Map<String, dynamic>> photoDocuments = _newChildDrafts
        .where(
            (BundleChildDraftResult draft) => draft.documentTypeName == '圖片表格列')
        .map(_buildPhotoCreatePayload)
        .where((Map<String, dynamic> payload) =>
            (payload['images'] as List<dynamic>? ?? const <dynamic>[])
                .isNotEmpty)
        .toList();
    final List<Map<String, dynamic>> auditDocuments = _newChildDrafts
        .where((BundleChildDraftResult draft) =>
            draft.documentTypeName == '缺失稽核改善')
        .map(_buildAuditCreatePayload)
        .where((Map<String, dynamic> payload) =>
            (payload['items'] as List<dynamic>? ?? const <dynamic>[])
                .isNotEmpty)
        .toList();
    final List<Map<String, dynamic>> childUpdates =
        _buildChildUpdatesForBundle();

    final Map<String, dynamic> metadata = <String, dynamic>{};
    if (fillData.isNotEmpty) {
      metadata['main_update'] = <String, dynamic>{
        'type': 'generic',
        'fill_data': fillData,
      };
    }
    if (photoDocuments.isNotEmpty) {
      metadata['photo_documents'] = photoDocuments;
    }
    if (auditDocuments.isNotEmpty) {
      metadata['audit_fix_documents'] = auditDocuments;
    }
    if (childUpdates.isNotEmpty) {
      metadata['child_updates'] = childUpdates;
    }
    return metadata;
  }

  Future<void> _launchVersionDownload(int versionId, String kind) async {
    final String url = await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.generateTempUrl(
        token: token,
        versionId: versionId,
        kind: kind,
      ),
    );

    final bool launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法開啟下載連結：$url')),
      );
    }
  }

  Future<void> _updateLinkOrderOrPin({
    List<Map<String, dynamic>>? reorderedChildren,
    int? overrideLinkId,
    int? overridePinnedVersionId,
  }) async {
    final List<Map<String, dynamic>> source =
        reorderedChildren ?? List<Map<String, dynamic>>.from(_linkedChildren);
    final List<Map<String, dynamic>> items =
        List<Map<String, dynamic>>.generate(
      source.length,
      (int index) {
        final Map<String, dynamic> child = source[index];
        final int linkId = _childLinkId(child);
        return <String, dynamic>{
          'link_id': linkId,
          'sort_order': index + 1,
          'pinned_child_version_id': linkId == overrideLinkId
              ? overridePinnedVersionId
              : _childPinnedVersionId(child),
        };
      },
    );

    _setBusy(true);
    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.updateFileLinks(
          token: token,
          fileId: widget.fileId,
          items: items,
        ),
      );
      await _refreshBundleState();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _moveLinkedChild(int index, int offset) async {
    final int targetIndex = index + offset;
    if (index < 0 ||
        index >= _linkedChildren.length ||
        targetIndex < 0 ||
        targetIndex >= _linkedChildren.length) {
      return;
    }

    final List<Map<String, dynamic>> reordered =
        List<Map<String, dynamic>>.from(_linkedChildren);
    final Map<String, dynamic> moved = reordered.removeAt(index);
    reordered.insert(targetIndex, moved);
    await _updateLinkOrderOrPin(reorderedChildren: reordered);
  }

  Future<void> _unlinkLinkedChild(Map<String, dynamic> item) async {
    final int linkId = _childLinkId(item);
    final int documentId = _childDocumentId(item);
    if (linkId == 0) return;

    _setBusy(true);
    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.unlinkFileLink(
          token: token,
          linkId: linkId,
        ),
      );
      _pendingChildDrafts.remove(documentId);
      await _refreshBundleState();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _pickPinnedVersion(Map<String, dynamic> item) async {
    final int documentId = _childDocumentId(item);
    final int linkId = _childLinkId(item);
    if (documentId == 0 || linkId == 0) return;

    final List<dynamic> versions = await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.getDocumentVersions(
        token: token,
        docId: documentId,
      ),
    );

    if (!mounted) return;
    final int? nextPinnedVersionId = await showModalBottomSheet<int?>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.auto_awesome_motion_outlined),
                title: const Text('跟隨最新版本'),
                onTap: () => Navigator.pop(ctx, null),
              ),
              ...versions.whereType<Map>().map((Map version) {
                final int versionId = (version['id'] as num?)?.toInt() ?? 0;
                final int versionNum =
                    (version['version_num'] as num?)?.toInt() ?? 0;
                return ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text('固定版本 v$versionNum'),
                  subtitle: Text('Version ID: $versionId'),
                  onTap: () => Navigator.pop(ctx, versionId),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    await _updateLinkOrderOrPin(
      overrideLinkId: linkId,
      overridePinnedVersionId: nextPinnedVersionId,
    );
  }

  Future<void> _linkExistingChildDocument() async {
    final TextEditingController keywordController = TextEditingController();
    final int? currentSiteId = _selectedSiteId ?? _originalSiteId;

    Future<List<Map<String, dynamic>>> fetchResults(String keyword) async {
      final Map<String, dynamic> response = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getFiles(
          token: token,
          keyword: keyword,
          siteId: currentSiteId,
          limit: 50,
        ),
      );
      final List<Map<String, dynamic>> items = _mapList(response['items']);
      return items.where((Map<String, dynamic> item) {
        final int id = (item['id'] as num?)?.toInt() ?? 0;
        final String type =
            (item['document_type_name'] as String? ?? '').trim();
        return id != widget.fileId && (type == '圖片表格列' || type == '缺失稽核改善');
      }).toList();
    }

    final Map<String, dynamic>? selected =
        await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) {
        List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
        bool loading = true;
        String? error;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            Future<void> runSearch([String keyword = '']) async {
              setModalState(() {
                loading = true;
                error = null;
              });
              try {
                results = await fetchResults(keyword);
              } catch (e) {
                error = '$e';
              } finally {
                setModalState(() => loading = false);
              }
            }

            if (loading && results.isEmpty && error == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) {
                  runSearch();
                }
              });
            }

            return AlertDialog(
              title: const Text('掛載既有子文件'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: keywordController,
                      decoration: InputDecoration(
                        labelText: '搜尋代碼或名稱',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              runSearch(keywordController.text.trim()),
                          icon: const Icon(Icons.search),
                        ),
                      ),
                      onSubmitted: (String value) => runSearch(value.trim()),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : error != null
                              ? Center(child: Text(error!))
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: results.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, int index) {
                                    final Map<String, dynamic> item =
                                        results[index];
                                    return ListTile(
                                      title: Text(
                                        (item['full_file_code'] as String? ??
                                                '')
                                            .trim(),
                                      ),
                                      subtitle: Text(
                                        '${item['document_type_name'] ?? ''}  ${item['site_name'] ?? ''}',
                                      ),
                                      onTap: () =>
                                          Navigator.pop(dialogContext, item),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
              ],
            );
          },
        );
      },
    );

    keywordController.dispose();
    if (selected == null) return;

    final int childDocumentId = (selected['id'] as num?)?.toInt() ?? 0;
    if (childDocumentId == 0) return;
    if (!mounted) return;

    _setBusy(true);
    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.linkExistingChild(
          token: token,
          fileId: widget.fileId,
          payload: <String, dynamic>{
            'child_document_id': childDocumentId,
            'sort_order': _linkedChildren.length + 1,
          },
        ),
      );
      await _refreshBundleState();
    } finally {
      _setBusy(false);
    }
  }

  String _todayDateText() => DateFormat('yyyy/MM/dd').format(DateTime.now());

  String _resolveInitialText({
    required String description,
    required String raw,
    bool autoFillReviewDate = false,
  }) {
    return resolveInitialFieldText(
      description: description,
      raw: raw,
      todayDateText: _todayDateText(),
      autoFillReviewDate: autoFillReviewDate,
    );
  }

  bool _shouldAutoFillReviewDate(int fid) => _autoFillReviewDates[fid] == true;

  void _toggleReviewDateAutoFill(
    int fid, {
    required bool enabled,
    required String description,
    required String raw,
    List<int> mirrorFieldIds = const <int>[],
  }) {
    final String currentText = _textCtrls[fid]?.text ?? '';
    final String trimmedRaw = raw.trim();
    final String todayText = _todayDateText();
    final bool rawIsPlaceholder =
        trimmedRaw.isEmpty || looksLikeDatePlaceholder(trimmedRaw);
    final bool canReplaceWithToday = currentText.trim().isEmpty ||
        looksLikeDatePlaceholder(currentText) ||
        currentText.trim() == trimmedRaw;

    setState(() {
      _autoFillReviewDates[fid] = enabled;

      if (enabled) {
        if (isReviewDateField(description: description, raw: raw) &&
            canReplaceWithToday) {
          _setFieldText(fid, todayText, mirrorFieldIds: mirrorFieldIds);
        }
        return;
      }

      if (rawIsPlaceholder && currentText.trim() == todayText) {
        _setFieldText(fid, '', mirrorFieldIds: mirrorFieldIds);
      }
    });
    _scheduleDraftAutosave();
  }

  Widget _buildReviewDateAutoFillRow(
    int fid, {
    required String description,
    required String raw,
    List<int> mirrorFieldIds = const <int>[],
    bool dense = false,
  }) {
    final bool enabled = _shouldAutoFillReviewDate(fid);
    final TextStyle? labelStyle = dense
        ? Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
        : Theme.of(context).textTheme.bodySmall;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('自動帶入今天', style: labelStyle),
        Switch.adaptive(
          value: enabled,
          materialTapTargetSize:
              dense ? MaterialTapTargetSize.shrinkWrap : null,
          onChanged: (bool value) {
            _toggleReviewDateAutoFill(
              fid,
              enabled: value,
              description: description,
              raw: raw,
              mirrorFieldIds: mirrorFieldIds,
            );
          },
        ),
      ],
    );
  }

  Widget _buildReviewDateAutoFillButton(
    int fid, {
    required String description,
    required String raw,
    List<int> mirrorFieldIds = const <int>[],
  }) {
    final bool enabled = _shouldAutoFillReviewDate(fid);
    final ColorScheme cs = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: enabled ? '取消自動帶入今天' : '自動帶入今天',
      onPressed: () {
        _toggleReviewDateAutoFill(
          fid,
          enabled: !enabled,
          description: description,
          raw: raw,
          mirrorFieldIds: mirrorFieldIds,
        );
      },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      icon: Icon(
        enabled ? Icons.event_available_outlined : Icons.event_busy_outlined,
        color: enabled ? cs.primary : cs.onSurfaceVariant,
      ),
    );
  }

  DateTime? _parseDateFieldValue(String value) {
    final String compact = value.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return null;

    final Match? separatorMatch = RegExp(
      r'^(\d{4})[-\/.](\d{1,2})[-\/.](\d{1,2})$',
    ).firstMatch(compact);
    if (separatorMatch != null) {
      return DateTime.tryParse(
        '${separatorMatch.group(1)}-'
        '${separatorMatch.group(2)!.padLeft(2, '0')}-'
        '${separatorMatch.group(3)!.padLeft(2, '0')}',
      );
    }

    final Match? chineseMatch = RegExp(
      r'^(\d{4})年(\d{1,2})月(\d{1,2})日$',
    ).firstMatch(compact);
    if (chineseMatch != null) {
      return DateTime.tryParse(
        '${chineseMatch.group(1)}-'
        '${chineseMatch.group(2)!.padLeft(2, '0')}-'
        '${chineseMatch.group(3)!.padLeft(2, '0')}',
      );
    }

    return null;
  }

  void _setFieldText(
    int fid,
    String value, {
    Iterable<int> mirrorFieldIds = const <int>[],
  }) {
    final Set<int> targetIds = <int>{fid, ...mirrorFieldIds};
    for (final int targetId in targetIds) {
      _textCtrls.putIfAbsent(
        targetId,
        () => TextEditingController(text: value),
      );
      _attachDraftListener(targetId);
      final TextEditingController controller = _textCtrls[targetId]!;
      if (controller.text == value) continue;
      controller.value = controller.value.copyWith(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
        composing: TextRange.empty,
      );
    }
    _scheduleDraftAutosave();
  }

  Future<void> _openDateFieldHelper(
    int fid, {
    List<int> mirrorFieldIds = const <int>[],
  }) async {
    if (!mounted) return;

    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: const Text('帶入今天'),
                onTap: () => Navigator.pop(context, 'today'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('選擇日期'),
                onTap: () => Navigator.pop(context, 'pick'),
              ),
              ListTile(
                leading: const Icon(Icons.clear_outlined),
                title: const Text('清除'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    String? nextValue;
    if (action == 'today') {
      nextValue = _todayDateText();
    } else if (action == 'clear') {
      nextValue = '';
    } else if (action == 'pick') {
      final DateTime initialDate = _parseDateFieldValue(
            _textCtrls[fid]?.text ?? '',
          ) ??
          DateTime.now();
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked == null || !mounted) return;
      nextValue = DateFormat('yyyy/MM/dd').format(picked);
    }

    if (nextValue == null) return;
    setState(() {
      _setFieldText(fid, nextValue!, mirrorFieldIds: mirrorFieldIds);
    });
  }

  /*────────────────── 初始化 ──────────────────*/
  @override
  void initState() {
    super.initState();
    final auth = context.read<UnifiedAuthProvider>();
    _draftUserId = auth.userId;
    _clientDraftId = (widget.clientDraftId?.trim().isNotEmpty ?? false)
        ? widget.clientDraftId!.trim()
        : DocumentDraftService.createClientDraftId();
    _draftRemoteStore = DocumentDraftRemoteStore(auth: auth);
    _draftAutosaver = DocumentDraftAutosaver(
      type: 'file_edit',
      keyProvider: _draftKey,
      payloadProvider: _buildLocalDraftPayload,
      remoteLoader: _draftRemoteStore.load,
      remoteSaver: _draftRemoteStore.save,
      remoteDeleter: _draftRemoteStore.delete,
    );
    _fetchSitesAndLoadAll();
  }

  Future<void> _fetchSitesAndLoadAll() async {
    try {
      final List<dynamic> sites = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getMySites(token: token),
      );
      _sitesById
        ..clear()
        ..addEntries(
          sites.whereType<Map>().where((Map site) {
            return site['id'] is num;
          }).map(
            (Map site) => MapEntry<int, dynamic>(
              (site['id'] as num).toInt(),
              site,
            ),
          ),
        );
    } catch (_) {}
    if (mounted) await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      /* 1) 簽署人 */

      /* 2) 最新版本 id */
      final fileDetail = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getFileById(
          token: token,
          fileId: widget.fileId,
        ),
      );
      _originalSiteId = (fileDetail['site_id'] as num?)?.toInt();
      _selectedSiteId ??= _originalSiteId;
      _currentSiteName = _resolveCurrentSiteName(
        preferredName: fileDetail['site_name'],
        preferredSiteId: _selectedSiteId ?? _originalSiteId,
      );
      final int versionId = (fileDetail['latest_version_id'] as num).toInt();
      _latestVersionId = versionId;

      /* 3) bundle 初始化資料（主文件欄位 + linked children）*/
      if (!mounted) return;
      final Map<String, dynamic> bundleResp = await _fetchBundleResponse();
      _applyBundleResponse(bundleResp);

      final dynamic mainFieldsRaw = bundleResp['main_fields'];
      if (mainFieldsRaw is Map) {
        _fields =
            (mainFieldsRaw['fields'] as List<dynamic>?) ?? const <dynamic>[];
      }

      if (_fields.isEmpty) {
        if (!mounted) return;
        final docFieldsResp = await AuthUtils.withAuthRetry(
          context,
          (token) => FileManageAPIService.getDocumentFields(
            token: token,
            fileId: widget.fileId,
          ),
        );
        _fields = (docFieldsResp['fields'] as List<dynamic>?) ?? [];
      }
      _rebuildFieldIndexes();

      /* 4) assignments (需依照 _fields 對映 fid) */
      await _refreshAssignments(versionId);

      /* 5) 分類與預設狀態 */
      _autoFillReviewDates.clear();
      for (final f in _fields) {
        final fid = f['field_id'] as int;
        final desc = f['description'] as String? ?? '';
        final raw = (f['original_text'] as String? ?? '').trim();
        final bool reviewDateField = isReviewDateField(
          description: desc,
          raw: raw,
        );

        if (reviewDateField) {
          _autoFillReviewDates[fid] = false;
        }

        if (f['is_table'] == true && (raw == '{cb}' || raw == 'V')) {
          _checkStates[fid] = raw == 'V';
          continue;
        }

        if (raw == '{sgn}') {
          // 若 assignments 已指定 signer，_selectedSigner 早已填入；否則維持 null 供選擇
          _selectedSigner.putIfAbsent(fid, () => null);
          continue;
        }

        if (raw.startsWith('data:image/png')) {
          final bytes = _decodeBase64(raw);
          if (f['is_table'] == true) {
            _tableImageBytes[fid] = bytes;
          } else {
            _signatureBytes[fid] = bytes;
          }
          continue;
        }

        // 自動填入工地名稱
        if (_isSiteField(desc)) {
          final String resolvedSiteName = _resolveCurrentSiteName(
            fieldValue: raw,
            preferredSiteId: _selectedSiteId ?? _originalSiteId,
          );
          if (resolvedSiteName.isNotEmpty) {
            _currentSiteName = resolvedSiteName;
          }
          _textCtrls[fid] = TextEditingController(text: resolvedSiteName);
        } else {
          _textCtrls[fid] = TextEditingController(
            text: _resolveInitialText(
              description: desc,
              raw: raw,
              autoFillReviewDate: _shouldAutoFillReviewDate(fid),
            ),
          );
        }
      }

      _syncProjectNameFieldTexts();

      _syncSignatureFieldOrder();
      _applyExistingSignatureOrder();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_error == null) {
          _attachDraftListenersForTextCtrls();
          unawaited(_maybeRestoreLocalDraft());
        }
      }
    }
  }

  void _syncSignatureFieldOrder() {
    final Set<int> validIds = _signatureFieldIdsCache.toSet();
    _signatureFieldOrder.removeWhere((int fieldId) {
      return !validIds.contains(fieldId);
    });
    final Set<int> existingIds = _signatureFieldOrder.toSet();
    for (final fid in _signatureFieldIdsCache) {
      if (existingIds.add(fid)) {
        _signatureFieldOrder.add(fid);
      }
    }
  }

  void _applyExistingSignatureOrder() {
    if (_signatureFieldOrder.length < 2) return;

    final Map<int, int> baseIndex = <int, int>{
      for (int i = 0; i < _signatureFieldOrder.length; i++)
        _signatureFieldOrder[i]: i,
    };

    _signatureFieldOrder.sort((int a, int b) {
      final int? orderA = _assignedOrder[a];
      final int? orderB = _assignedOrder[b];
      if (orderA != null && orderB != null) {
        final int byOrder = orderA.compareTo(orderB);
        if (byOrder != 0) return byOrder;
      } else if (orderA != null) {
        return -1;
      } else if (orderB != null) {
        return 1;
      }
      return (baseIndex[a] ?? 0).compareTo(baseIndex[b] ?? 0);
    });
  }

  void _reorderSignatureFields(int oldIndex, int newIndex) {
    setState(() {
      final int fid = _signatureFieldOrder.removeAt(oldIndex);
      _signatureFieldOrder.insert(newIndex, fid);
    });
    _scheduleDraftAutosave();
  }

  /*───────── 重新抓 assignments: 對應 task_id / signer / status / comment ─────────*/
  Future<void> _refreshAssignments(int versionId) async {
    final assigns = await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.getSignatureAssignments(
        token: token,
        versionId: versionId,
      ),
    );

    for (final fid in _signatureFieldIdsCache) {
      _taskIdOfField.remove(fid);
      _assignedCmt.remove(fid);
      _assignedSts.remove(fid);
      _assignedName.remove(fid);
      _assignedDisplayName.remove(fid);
      _assignedFamily.remove(fid);
      _assignedGiven.remove(fid);
      _assignedEmail.remove(fid);
      _assignedOrder.remove(fid);
    }

    for (final a in assigns) {
      final String status =
          normalizeSignatureTaskStatus(a['status'] as String?);
      if (!isVisibleSignatureTaskStatus(status)) {
        continue;
      }
      final placeholder = a['placeholder_id'] as String;
      final field = _fieldByDescription[placeholder];
      if (field == null) continue;
      final fid = field['field_id'] as int;
      _taskIdOfField[fid] = a['task_id'] as int;
      _selectedSigner[fid] = a['signer_id'] as int?;
      _assignedName[fid] = a['signer_name'] as String? ?? '';
      _assignedDisplayName[fid] = userDisplayName(a);
      _assignedCmt[fid] = a['comment'] as String? ?? '';
      _assignedSts[fid] = status;
      _assignedOrder[fid] = (a['order'] as num?)?.toInt() ?? 1;
    }

    _orderedSigning = assigns.any(
      (a) => ((a['order'] as num?)?.toInt() ?? 1) > 1,
    );
  }

  @override
  void dispose() {
    if (!_loading && !_mainDocumentLocked && !_suppressDraftAutosave) {
      unawaited(_draftAutosaver.flush());
    }
    _draftAutosaver.dispose();
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    for (final node in _tableFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Uint8List? _decodeBase64(String uri) {
    final p = uri.split(',');
    if (p.length == 2 && p[1].isNotEmpty) {
      try {
        return base64Decode(p[1]);
      } catch (_) {}
    }
    return null;
  }

  String _tableCellText(dynamic field) {
    final int fid = field['field_id'] as int;
    return _textCtrls[fid]?.text ??
        (field['original_text'] as String? ?? '').trim();
  }

  FocusNode _tableFocusNodeFor(int fid) {
    return _tableFocusNodes.putIfAbsent(fid, FocusNode.new);
  }

  Widget _buildWordTableCellFrame({
    required int fieldId,
    required Widget child,
    VoidCallback? onTap,
    bool enabled = true,
    bool textCursor = true,
    Color? idleColor,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    AlignmentGeometry alignment = Alignment.center,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final FocusNode focusNode = _tableFocusNodeFor(fieldId);

    return AnimatedBuilder(
      animation: focusNode,
      builder: (BuildContext context, Widget? child) {
        final bool focused = focusNode.hasFocus;
        return MouseRegion(
          cursor: !enabled
              ? SystemMouseCursors.basic
              : textCursor
                  ? SystemMouseCursors.text
                  : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 48),
              alignment: alignment,
              padding: padding,
              decoration: BoxDecoration(
                color: focused
                    ? cs.primary.withValues(alpha: 0.08)
                    : idleColor ?? Colors.transparent,
                border: Border.all(
                  color: focused ? cs.primary : Colors.transparent,
                  width: 1.4,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }

  InputDecoration _wordTableInputDecoration() {
    return const InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      isCollapsed: true,
      isDense: true,
      filled: false,
    );
  }

  void _focusTableCell(int fid) {
    final FocusNode node = _tableFocusNodeFor(fid);
    if (!node.canRequestFocus) {
      return;
    }

    node.requestFocus();
    final TextEditingController? controller = _textCtrls[fid];
    if (controller != null) {
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }
  }

  /*──────────────────────── 提交 ───────────────────────*/
  Future<void> _submit() async {
    if (_busy) return;
    _setBusy(true);
    final auth = context.read<UnifiedAuthProvider>();
    await auth.refreshIfNeeded();
    final token = auth.requestToken;
    final myUid = auth.userId;
    if (token == null || myUid == null) {
      _setBusy(false);
      return;
    }

    // 0) 檢查下拉尚未選擇 signer 的 {sgn}
    for (final fid in _signatureFieldOrder) {
      if (_taskIdOfField[fid] != null) continue; // 已指定
      final int? signerId = _selectedSigner[fid];
      if (signerId == null) {
        final desc = (_fieldsById[fid]?['description'] as String?) ?? '';
        if (!mounted) {
          _setBusy(false);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.pleaseSelectSignerFor(desc))),
        );
        _setBusy(false);
        return;
      }
    }

    // 1) 組 assignments（僅新指派）
    final assignments = <Map<String, dynamic>>[];
    int order = 1;
    for (final fid in _signatureFieldOrder) {
      final uid = _selectedSigner[fid];
      if (_taskIdOfField[fid] != null) continue; // 已存在
      final placeholder = (_fieldsById[fid]?['description'] as String?) ?? '';
      assignments.add({
        'placeholder_id': placeholder,
        'signer_id': uid,
        'order': _orderedSigning ? order++ : 1,
      });
    }

    bool submitted = false;
    _suppressDraftAutosave = true;
    try {
      if (_selectedSiteId != null && _selectedSiteId != _originalSiteId) {
        await FileManageAPIService.updateFileContent(
          token: token,
          fileId: widget.fileId,
          updatedContent: <String, dynamic>{'site_id': _selectedSiteId},
        );
        _originalSiteId = _selectedSiteId;
      }

      // 2) 最新 versionId
      final fileDetail = await FileManageAPIService.getFileById(
        token: token,
        fileId: widget.fileId,
      );
      _selectedSiteId =
          (fileDetail['site_id'] as num?)?.toInt() ?? _selectedSiteId;
      _originalSiteId = _selectedSiteId;
      _currentSiteName = _resolveCurrentSiteName(
        preferredName: fileDetail['site_name'],
        preferredSiteId: _selectedSiteId,
      );
      _syncProjectNameFieldTexts();
      int versionId = (fileDetail['latest_version_id'] as num).toInt();

      // 3) 填欄位（文字 / checkbox / 圖片 / 簽名檔）
      final fillData = <Map<String, String>>[];
      _textCtrls.forEach(
          (fid, c) => fillData.add({'field_id': '$fid', 'new_text': c.text}));
      _checkStates.forEach((fid, v) =>
          fillData.add({'field_id': '$fid', 'new_text': v ? 'V' : '{cb}'}));
      _signatureBytes.forEach((fid, b) {
        if (b != null) {
          fillData.add({
            'field_id': '$fid',
            'new_text': 'data:image/png;base64,${base64Encode(b)}'
          });
        }
      });
      _tableImageBytes.forEach((fid, b) {
        final txt = b == null ? '' : 'data:image/png;base64,${base64Encode(b)}';
        fillData.add({'field_id': '$fid', 'new_text': txt});
      });
      final List<Map<String, dynamic>> normalizedFillData =
          <Map<String, dynamic>>[];
      final List<BundleUploadFile> bundleFiles = <BundleUploadFile>[
        ..._collectBundleFiles(),
      ];
      int mainUploadCounter = 0;
      final int uploadTimestamp = DateTime.now().millisecondsSinceEpoch;

      for (final Map<String, dynamic> rawItem in fillData) {
        final Map<String, dynamic> item = Map<String, dynamic>.from(rawItem);
        if (item.containsKey('_bytes')) {
          final List<int> bytes = List<int>.from(item.remove('_bytes') as List);
          final String uploadKey =
              'main-fill-$uploadTimestamp-$mainUploadCounter.png';
          mainUploadCounter += 1;
          bundleFiles.add(
            BundleUploadFile(
              filename: uploadKey,
              bytes: Uint8List.fromList(bytes),
              draftBytes: Uint8List.fromList(bytes),
            ),
          );
          item['new_text'] = uploadKey;
        }
        normalizedFillData.add(item);
      }

      final Map<String, dynamic> bundleMetadata = _buildBundleSaveMetadata(
        fillData: normalizedFillData,
      );
      if (bundleMetadata.isNotEmpty) {
        final Map<String, dynamic> bundleResponse =
            await FileManageAPIService.updateFileBundle(
          token: token,
          fileId: widget.fileId,
          metadata: bundleMetadata,
          files: bundleFiles,
        );

        versionId =
            (bundleResponse['main_version_id'] as num?)?.toInt() ?? versionId;
        _latestVersionId = versionId;
        _pendingChildDrafts.clear();
        _newChildDrafts.clear();
      }

      if (assignments.isNotEmpty) {
        await FileManageAPIService.setupSignatureFlow(
          token: token,
          versionId: versionId,
          ordered: _orderedSigning,
          assignments: assignments,
        );
      }

      if (mounted) {
        await _refreshAssignments(versionId);
      }

      // 6) 送自己的簽名（依序送出，每次都要取得新 versionId）
      final pendingList = _pendingSigBytes.entries.toList();
      for (final entry in pendingList) {
        final fid = entry.key;
        final bytes = entry.value;
        final taskId = _taskIdOfField[fid];
        if (bytes == null || taskId == null) continue;

        final result = await FileManageAPIService.submitSignature(
          token: token,
          taskId: taskId,
          status: 'signed',
          pngBytes: bytes,
          comment: _assignedCmt[fid] ?? '',
        );

        // 取得新 versionId
        if (result.containsKey('version_id')) {
          versionId = (result['version_id'] as num).toInt();
          _latestVersionId = versionId;
          // 重新 refresh assignments，確保下個 taskId 是新版本的
          await _refreshAssignments(versionId);
        }
      }

      await _draftAutosaver.delete(waitForRemote: true);
      _savedAtLeastOnce = true;
      submitted = true;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.submitted)));
      _goToPreview(versionId: versionId);
    } on FileManageApiException catch (e) {
      if (e.statusCode == 409) {
        await _refreshBundleState();
      }
      if (!mounted) return;
      final String message =
          e.statusCode == 423 ? '此文件已建立簽核任務，無法再變更工地' : e.message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context)!.failedWith(e.toString()))));
    } finally {
      if (!submitted) {
        _suppressDraftAutosave = false;
      }
      _setBusy(false);
    }
  }

  /*───────────────────────── UI ───────────────────────*/
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ResponsiveScaffold(
          title: AppLocalizations.of(context)!.loading,
          isFullscreen: !kIsWeb,
          onBackPressed: _handleBackPress,
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return ResponsiveScaffold(
          title: AppLocalizations.of(context)!.error,
          isFullscreen: !kIsWeb,
          onBackPressed: _handleBackPress,
          body: Center(
              child: Text(AppLocalizations.of(context)!.errorPrefix(_error!))));
    }

    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.editDocumentTitle,
      isFullscreen: !kIsWeb,
      onBackPressed: _handleBackPress,
      actions: kIsWeb ? _buildWebEditorActions() : null,
      body: _buildEditContentStack(webLayout: kIsWeb),
    );
  }

  List<Widget> _buildWebEditorActions() {
    final AppLocalizations l = AppLocalizations.of(context)!;
    return <Widget>[
      OutlinedButton.icon(
        onPressed: _busy ? null : () => unawaited(_handleBackPress()),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('返回文件'),
      ),
      FilledButton.icon(
        onPressed: (_busy || _mainDocumentLocked) ? null : _submit,
        icon: const Icon(Icons.save_outlined, size: 18),
        label: Text(l.saveAndSubmit),
      ),
    ];
  }

  Widget _buildEditContentStack({required bool webLayout}) {
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: _busy,
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: webLayout
                ? _buildWebEditWorkspace()
                : _buildMobileEditScrollView(),
          ),
        ),
        if (_busy)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileEditScrollView() {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final int contentOffset = _mainDocumentLocked ? 1 : 0;
                if (_mainDocumentLocked && index == 0) {
                  return _buildLockedBanner();
                }
                return _buildEditContentItem(
                  _editContentItems[index - contentOffset],
                );
              },
              childCount:
                  _editContentItems.length + (_mainDocumentLocked ? 1 : 0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebEditWorkspace() {
    final List<Widget> children = <Widget>[
      if (_mainDocumentLocked) _buildLockedBanner(),
      for (final String part in const <String>['header', 'body', 'footer'])
        _buildWebParagraphSection(part),
      for (final _TableSectionInfo section in _tableSections)
        _buildTableSection(section),
      _buildSignatureSection(),
      _buildBundleSection(),
    ];

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 36),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<dynamic> _paragraphFieldsForPart(String part) {
    return _fields.where((dynamic field) {
      if (field['part'] != part || field['is_table'] == true) {
        return false;
      }
      final String raw = (field['original_text'] as String? ?? '').trim();
      return raw != '{sgn}';
    }).toList(growable: false);
  }

  Widget _buildWebParagraphSection(String part) {
    final List<dynamic> fields = _paragraphFieldsForPart(part);
    if (fields.isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildWebSectionHeader(
            _sectionTitle(part),
            trailing: Text(
              '${fields.length} 欄位',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final int columns = _webParagraphColumnCount(
                    part: part,
                    fieldCount: fields.length,
                    maxWidth: constraints.maxWidth,
                  );
                  const double spacing = 16;
                  final double fieldWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: 16,
                    children: <Widget>[
                      for (final dynamic field in fields)
                        _buildWebParagraphField(
                          field,
                          width: _webParagraphFieldWidth(
                            field: field,
                            part: part,
                            baseWidth: fieldWidth,
                            maxWidth: constraints.maxWidth,
                            spacing: spacing,
                            columns: columns,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _webParagraphColumnCount({
    required String part,
    required int fieldCount,
    required double maxWidth,
  }) {
    if (fieldCount <= 1 || maxWidth < 680) return 1;
    if (part == 'body' && fieldCount <= 2) return 2;
    if (maxWidth >= 1120 && fieldCount >= 3) return 3;
    return 2;
  }

  double _webParagraphFieldWidth({
    required dynamic field,
    required String part,
    required double baseWidth,
    required double maxWidth,
    required double spacing,
    required int columns,
  }) {
    final bool compactSingle = part == 'body' && columns == 1;
    if (compactSingle) {
      return math.min(baseWidth, 520).clamp(280, maxWidth).toDouble();
    }

    final bool wide = _webParagraphFieldPrefersWide(field, part);
    if (wide && columns >= 2) {
      return math
          .min(baseWidth * 2 + spacing, maxWidth)
          .clamp(280, maxWidth)
          .toDouble();
    }
    return baseWidth.clamp(280, maxWidth).toDouble();
  }

  bool _webParagraphFieldPrefersWide(dynamic field, String part) {
    if (part != 'header') return false;
    final String desc =
        (field['description'] as String? ?? '').replaceAll(' ', '');
    return desc.contains('文件名稱') ||
        desc.contains('工程名稱') ||
        desc.toLowerCase().contains('name');
  }

  Widget _buildWebParagraphField(dynamic f, {required double width}) {
    final int fid = f['field_id'] as int;
    final String desc = f['description'] as String? ?? '';
    final String raw = (f['original_text'] as String? ?? '').trim();
    final bool siteField = _isSiteField(desc);

    if (siteField) {
      final String siteName = _resolveCurrentSiteName(
        preferredName: _currentSiteName,
        preferredSiteId: _selectedSiteId ?? _originalSiteId,
        fieldValue: _textCtrls[fid]?.text ?? raw,
      );
      _textCtrls.putIfAbsent(
        fid,
        () => TextEditingController(text: siteName),
      );
      _attachDraftListener(fid);
      if (siteName.isNotEmpty && _textCtrls[fid]!.text != siteName) {
        _textCtrls[fid]!.text = siteName;
      }
    } else {
      _textCtrls.putIfAbsent(
        fid,
        () => TextEditingController(
          text: _resolveInitialText(
            description: desc,
            raw: raw,
            autoFillReviewDate: _shouldAutoFillReviewDate(fid),
          ),
        ),
      );
      _attachDraftListener(fid);
    }

    final bool isDateField = shouldTreatFieldAsDate(
      description: desc,
      raw: raw,
      currentValue: _textCtrls[fid]?.text,
    );
    final bool reviewDateField = isReviewDateField(
      description: desc,
      raw: raw,
      currentValue: _textCtrls[fid]?.text,
    );
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  desc.isEmpty ? '欄位' : desc,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (reviewDateField)
                _buildReviewDateAutoFillButton(
                  fid,
                  description: desc,
                  raw: raw,
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _textCtrls[fid],
            readOnly: siteField,
            keyboardType: isDateField ? TextInputType.datetime : null,
            decoration: _webFieldDecoration(
              suffixIcon: isDateField
                  ? IconButton(
                      tooltip: '日期工具',
                      onPressed: () => _openDateFieldHelper(fid),
                      icon: const Icon(Icons.calendar_month_outlined),
                    )
                  : null,
            ),
            minLines: 1,
            maxLines: null,
          ),
        ],
      ),
    );
  }

  InputDecoration _webFieldDecoration({Widget? suffixIcon}) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: cs.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      suffixIcon: suffixIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.primary, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
    );
  }

  Widget _buildWebSectionHeader(String title, {Widget? trailing}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Row(
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Divider(
            height: 1,
            indent: 16,
            color: cs.outlineVariant,
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: 16),
          trailing,
        ],
      ],
    );
  }

  Widget _buildLockedBanner() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: const Text(
        '主文件已鎖定，內容改為唯讀。你仍然可以下載或整包匯出。',
      ),
    );
  }

  Widget _buildEditContentItem(
    _EditContentItem item, {
    bool includeSaveButton = true,
  }) {
    switch (item.type) {
      case _EditContentItemType.sectionHeader:
        return _buildSectionHeader(_sectionTitle(item.part!));
      case _EditContentItemType.paragraphField:
        return _buildParagraphField(item.field);
      case _EditContentItemType.tableSection:
        return _buildTableSection(item.tableSection!);
      case _EditContentItemType.spacer:
        return SizedBox(height: item.height);
      case _EditContentItemType.signatureSection:
        return _buildSignatureSection();
      case _EditContentItemType.bundleSection:
        return _buildBundleSection();
      case _EditContentItemType.saveButton:
        return includeSaveButton ? _buildSaveButton() : const SizedBox.shrink();
    }
  }

  String _sectionTitle(String part) {
    final AppLocalizations l = AppLocalizations.of(context)!;
    return switch (part) {
      'header' => l.headerSection,
      'body' => l.bodySection,
      'footer' => l.footerSection,
      _ => part,
    };
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: (_busy || _mainDocumentLocked) ? null : _submit,
        icon: const Icon(Icons.save_outlined, size: 18),
        label: Text(AppLocalizations.of(context)!.saveAndSubmit),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildTableSection(_TableSectionInfo section) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int columnCount = math.max(1, section.maxCol);
    Widget buildTable(List<TrackSize> columnSizes) {
      return Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(kIsWeb ? 6 : 8),
        ),
        child: LayoutGrid(
          columnSizes: columnSizes,
          rowSizes: List.generate(
            section.rows.length,
            (_) => auto,
          ),
          children: <Widget>[
            for (final _TableCellInfo cell in section.cells)
              GridPlacement(
                columnStart: cell.col,
                columnSpan: cell.colSpan,
                rowStart: section.rowIndexByNumber[cell.row] ?? 0,
                rowSpan: cell.rowSpan,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.6),
                      ),
                      bottom: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  child: _tableFieldWidget(cell.field),
                ),
              ),
          ],
        ),
      );
    }

    final Widget tableViewport = kIsWeb
        ? LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final List<double> columnWidths =
                  _webTableColumnWidths(section, constraints.maxWidth);
              final double tableWidth = columnWidths.fold<double>(
                0,
                (double sum, double width) => sum + width,
              );
              final Widget sizedTable = SizedBox(
                width: tableWidth,
                child: buildTable(
                  columnWidths
                      .map<TrackSize>((double width) => FixedTrackSize(width))
                      .toList(growable: false),
                ),
              );

              if (tableWidth <= constraints.maxWidth) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: sizedTable,
                );
              }

              return Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: sizedTable,
                ),
              );
            },
          )
        : buildTable(List.generate(columnCount, (_) => 1.fr));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSectionHeader(
          AppLocalizations.of(context)!.tableLabel(
            section.tableIndex.toString(),
          ),
        ),
        const SizedBox(height: 6),
        tableViewport,
        const SizedBox(height: 24),
      ],
    );
  }

  List<double> _webTableColumnWidths(
    _TableSectionInfo section,
    double availableWidth,
  ) {
    final int columnCount = math.max(1, section.maxCol);
    const double minColumnWidth = 58;
    const double maxShortColumnWidth = 132;
    const double maxTextColumnWidth = 248;
    final List<double> widths = List<double>.filled(columnCount, 72);
    final TextStyle textStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 13);

    for (final _TableCellInfo cell in section.cells) {
      final int start = cell.col.clamp(0, columnCount - 1);
      final int span = math.max(
        1,
        math.min(cell.colSpan <= 0 ? 1 : cell.colSpan, columnCount - start),
      );
      final double desiredWidth = _webTableDesiredCellWidth(cell, textStyle);
      final double perColumn = (desiredWidth / span).clamp(
        minColumnWidth,
        _webTableCellCanHoldLongText(cell)
            ? maxTextColumnWidth
            : maxShortColumnWidth,
      );

      for (int col = start; col < start + span; col++) {
        widths[col] = math.max(widths[col], perColumn);
      }
    }

    final double measuredTotal = widths.fold<double>(
      0,
      (double sum, double width) => sum + width,
    );
    final double floorTotal = columnCount * minColumnWidth;
    final double comfortCap = availableWidth <= 0
        ? (columnCount <= 8 ? 980 : 1180)
        : math.min(availableWidth, columnCount <= 8 ? 980 : 1180);
    final double targetTotal = math.max(
      floorTotal,
      math.min(measuredTotal, comfortCap),
    );

    if (measuredTotal <= targetTotal || measuredTotal <= floorTotal) {
      return widths;
    }

    final double flexibleTotal = widths.fold<double>(
      0,
      (double sum, double width) => sum + math.max(0, width - minColumnWidth),
    );
    if (flexibleTotal <= 0) return widths;

    final double shrink = measuredTotal - targetTotal;
    return widths.map<double>((double width) {
      final double flex = math.max(0, width - minColumnWidth);
      final double reduced = width - shrink * flex / flexibleTotal;
      return reduced.clamp(minColumnWidth, width).toDouble();
    }).toList(growable: false);
  }

  double _webTableDesiredCellWidth(
    _TableCellInfo cell,
    TextStyle textStyle,
  ) {
    final dynamic field = cell.field;
    final int fid = field['field_id'] as int;
    if (_checkStates.containsKey(fid)) return 64;
    if (_tableImageBytes.containsKey(fid) || _signatureBytes.containsKey(fid)) {
      return 152;
    }

    final String text = _webTableMeasureText(field);
    if (text.isEmpty) return 72;

    final double measured = _measureSingleLineText(text, textStyle);
    final int length = text.runes.length;
    final String desc = field['description'] as String? ?? '';
    final bool dateLike = shouldTreatFieldAsDate(
      description: desc,
      raw: text,
      currentValue: text,
    );

    final double minimum = dateLike
        ? 132
        : length <= 4
            ? 72
            : length <= 8
                ? 96
                : length <= 18
                    ? 128
                    : 168;
    final double maximum = _webTableCellCanHoldLongText(cell) ? 288 : 180;
    return (measured + 34).clamp(minimum, maximum).toDouble();
  }

  bool _webTableCellCanHoldLongText(_TableCellInfo cell) {
    final dynamic field = cell.field;
    final String text = _webTableMeasureText(field);
    if (text.runes.length >= 14) return true;
    final String desc = field['description'] as String? ?? '';
    return desc.contains('標準') ||
        desc.contains('情形') ||
        desc.contains('檢查值') ||
        desc.toLowerCase().contains('description');
  }

  String _webTableMeasureText(dynamic field) {
    final String text =
        _tableCellText(field).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty || text == '{cb}' || text == 'V' || text == '{sgn}') {
      final String desc = (field['description'] as String? ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (desc == '{cb}' || desc == 'V' || desc == '{sgn}') return '';
      return desc;
    }
    return text;
  }

  double _measureSingleLineText(String text, TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    return painter.size.width;
  }

  /*─── 段落欄位 (非表格) ───*/
  Widget _buildParagraphField(dynamic f) {
    final fid = f['field_id'] as int;
    final desc = f['description'] as String? ?? '';
    final raw = (f['original_text'] as String? ?? '').trim();

    if (raw == '{sgn}') {
      // 跳過，不在段落顯示簽名
      return const SizedBox.shrink();
    }

    // 工地名稱欄位唯讀顯示
    if (_isSiteField(desc)) {
      final String siteName = _resolveCurrentSiteName(
        preferredName: _currentSiteName,
        preferredSiteId: _selectedSiteId ?? _originalSiteId,
        fieldValue: _textCtrls[fid]?.text ?? raw,
      );
      _textCtrls.putIfAbsent(
        fid,
        () => TextEditingController(text: siteName),
      );
      _attachDraftListener(fid);
      if (siteName.isNotEmpty && _textCtrls[fid]!.text != siteName) {
        _textCtrls[fid]!.text = siteName;
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: desc,
            border: const OutlineInputBorder(),
          ),
          child: Text(
            siteName.isEmpty
                ? AppLocalizations.of(context)!.unnamedSite
                : siteName,
          ),
        ),
      );
    }

    _textCtrls.putIfAbsent(
      fid,
      () => TextEditingController(
        text: _resolveInitialText(
          description: desc,
          raw: raw,
          autoFillReviewDate: _shouldAutoFillReviewDate(fid),
        ),
      ),
    );
    _attachDraftListener(fid);
    final bool isDateField = shouldTreatFieldAsDate(
      description: desc,
      raw: raw,
      currentValue: _textCtrls[fid]?.text,
    );
    final bool reviewDateField = isReviewDateField(
      description: desc,
      raw: raw,
      currentValue: _textCtrls[fid]?.text,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (reviewDateField)
            _buildReviewDateAutoFillRow(
              fid,
              description: desc,
              raw: raw,
            ),
          TextFormField(
            controller: _textCtrls[fid],
            keyboardType: isDateField ? TextInputType.datetime : null,
            decoration: InputDecoration(
              labelText: desc,
              border: const OutlineInputBorder(),
              suffixIcon: isDateField
                  ? IconButton(
                      tooltip: '日期工具',
                      onPressed: () => _openDateFieldHelper(fid),
                      icon: const Icon(Icons.calendar_month_outlined),
                    )
                  : null,
            ),
            maxLines: null,
          ),
        ],
      ),
    );
  }

  Widget _tableFieldWidget(dynamic f) {
    final fid = f['field_id'] as int;
    final raw = _tableCellText(f).trim();
    final List<int> mergedFieldIds =
        (f['merged_field_ids'] as List<dynamic>? ?? <dynamic>[fid]).cast<int>();

    if (_checkStates.containsKey(fid)) {
      return InkWell(
        onTap: () {
          setState(() => _checkStates[fid] = !_checkStates[fid]!);
          _scheduleDraftAutosave();
        },
        child: Center(
          child: Checkbox(
            value: _checkStates[fid]!,
            onChanged: (v) {
              setState(() => _checkStates[fid] = v ?? false);
              _scheduleDraftAutosave();
            },
          ),
        ),
      );
    }

    if (raw == '{sgn}') {
      // 跳過，不在表格顯示簽名
      return const SizedBox.shrink();
    }

    if (_tableImageBytes.containsKey(fid)) {
      final img = _tableImageBytes[fid];
      final cs = Theme.of(context).colorScheme;
      return GestureDetector(
        onTap: () async {
          final bytes = await _pickImage();
          if (bytes != null) {
            setState(() {
              _tableImageBytes[fid] = bytes;
              _draftDirtyTableImageFields.add(fid);
            });
            _scheduleDraftAutosave();
          }
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
          child: (img != null && img.isNotEmpty)
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.memory(img,
                        fit: BoxFit.contain, width: double.infinity),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: cs.surface.withValues(alpha: 0.85),
                        child: Icon(Icons.edit, size: 13, color: cs.primary),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Icon(Icons.add_photo_alternate_outlined,
                        color: cs.primary, size: 22),
                    const SizedBox(height: 4),
                    Text(AppLocalizations.of(context)!.addImage,
                        style: TextStyle(fontSize: 11, color: cs.primary)),
                    const SizedBox(height: 8),
                  ],
                ),
        ),
      );
    }

    if (_signatureBytes.containsKey(fid)) {
      final img = _signatureBytes[fid];
      final cs = Theme.of(context).colorScheme;
      return GestureDetector(
        onTap: () async {
          final bytes = await _openPad();
          if (bytes != null) {
            setState(() {
              _signatureBytes[fid] = bytes;
              _draftDirtySignatureImageFields.add(fid);
            });
            _scheduleDraftAutosave();
          }
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
          child: (img != null && img.isNotEmpty)
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.memory(img,
                        fit: BoxFit.contain, width: double.infinity),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: cs.surface.withValues(alpha: 0.85),
                        child: Icon(Icons.edit, size: 13, color: cs.primary),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Icon(Icons.draw_outlined, color: cs.primary, size: 22),
                    const SizedBox(height: 4),
                    Text(AppLocalizations.of(context)!.tapToSign,
                        style: TextStyle(fontSize: 11, color: cs.primary)),
                    const SizedBox(height: 8),
                  ],
                ),
        ),
      );
    }

    final String desc = f['description'] as String? ?? '';
    _textCtrls.putIfAbsent(
      fid,
      () => TextEditingController(
        text: _resolveInitialText(
          description: desc,
          raw: raw,
          autoFillReviewDate: _shouldAutoFillReviewDate(fid),
        ),
      ),
    );
    _attachDraftListener(fid);
    final bool projectField = _projectNameFieldIdSet.contains(fid);
    if (projectField) {
      final String resolvedSiteName = _resolveCurrentSiteName(
        preferredName: _currentSiteName,
        preferredSiteId: _selectedSiteId ?? _originalSiteId,
        fieldValue: _textCtrls[fid]?.text ?? raw,
      );
      if (resolvedSiteName.isNotEmpty &&
          _textCtrls[fid]!.text != resolvedSiteName) {
        _textCtrls[fid]!.text = resolvedSiteName;
      }
    }
    final FocusNode focusNode = _tableFocusNodeFor(fid);
    final cs = Theme.of(context).colorScheme;
    final bool isDateField = shouldTreatFieldAsDate(
      description: desc,
      raw: raw,
      currentValue: _textCtrls[fid]?.text,
    );
    final bool reviewDateField = isReviewDateField(
      description: desc,
      raw: raw,
      currentValue: _textCtrls[fid]?.text,
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _textCtrls[fid]!,
      builder: (BuildContext context, TextEditingValue value, Widget? child) {
        final String currentText = value.text.trim();
        return _buildWordTableCellFrame(
          fieldId: fid,
          onTap: () => _focusTableCell(fid),
          idleColor: currentText.isEmpty
              ? cs.surfaceContainerHighest.withValues(alpha: 0.28)
              : Colors.transparent,
          alignment:
              currentText.isEmpty ? Alignment.centerLeft : Alignment.center,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _textCtrls[fid],
                  focusNode: focusNode,
                  readOnly: projectField,
                  enableInteractiveSelection: true,
                  minLines: 1,
                  maxLines: null,
                  keyboardType: isDateField ? TextInputType.datetime : null,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.22),
                  textAlign:
                      currentText.isEmpty ? TextAlign.start : TextAlign.center,
                  decoration: _wordTableInputDecoration(),
                  onTap: () => _focusTableCell(fid),
                  onChanged: projectField
                      ? null
                      : (String value) {
                          _setFieldText(
                            fid,
                            value,
                            mirrorFieldIds: mergedFieldIds
                                .where((int mergedFid) => mergedFid != fid),
                          );
                        },
                ),
              ),
              if (reviewDateField)
                _buildReviewDateAutoFillButton(
                  fid,
                  description: desc,
                  raw: raw,
                  mirrorFieldIds: mergedFieldIds
                      .where((int mergedFid) => mergedFid != fid)
                      .toList(),
                ),
              if (isDateField)
                IconButton(
                  tooltip: '日期工具',
                  onPressed: () => _openDateFieldHelper(
                    fid,
                    mirrorFieldIds: mergedFieldIds
                        .where((int mergedFid) => mergedFid != fid)
                        .toList(),
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 28),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: Icon(
                    Icons.calendar_month_outlined,
                    color: cs.primary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /*─── 內嵌簽名預覽 ───*/
  Widget _inlineSignPreview(int fid) {
    final img = _pendingSigBytes[fid];
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final bytes = await _openPad();
        if (bytes != null && mounted) {
          setState(() {
            _pendingSigBytes[fid] = bytes;
            _draftDirtyPendingSignatureFields.add(fid);
          });
          _scheduleDraftAutosave();
        }
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(8),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        clipBehavior: Clip.hardEdge,
        child: (img != null && img.isNotEmpty)
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Image.memory(img,
                      fit: BoxFit.contain, width: double.infinity),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: cs.surface.withValues(alpha: 0.85),
                      child: Icon(Icons.edit, size: 13, color: cs.primary),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  Icon(Icons.draw_outlined, color: cs.primary, size: 26),
                  const SizedBox(height: 6),
                  Text(AppLocalizations.of(context)!.tapToSign,
                      style: TextStyle(fontSize: 12, color: cs.primary)),
                  const SizedBox(height: 12),
                ],
              ),
      ),
    );
  }

  /*─── 工具: 圖 / pad ───*/
  Future<Uint8List?> _pickImage() async {
    final picker = ImagePicker();
    final XFile? x =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    return x == null ? null : await x.readAsBytes();
  }

  Future<Uint8List?> _openPad() async {
    final ctrl = SignatureController(penStrokeWidth: 2, penColor: Colors.black);
    return showDialog<Uint8List?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('簽名'),
        content: SizedBox(
            width: 400, height: 250, child: Signature(controller: ctrl)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel)),
          TextButton(
            onPressed: () async {
              final bytes = await ctrl.toPngBytes();
              if (!mounted) return;
              Navigator.pop(context, bytes);
            },
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
  }

  /*─── 章節標題（左色條 + 加粗文字） ───*/
  Widget _buildSectionHeader(String title) {
    if (kIsWeb) {
      return _buildWebSectionHeader(title);
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 19,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  String _signatureFieldTitle(dynamic f) {
    final String desc = f['description'] as String? ?? '';
    return desc.isEmpty
        ? AppLocalizations.of(context)!.signatureFieldLabel
        : desc;
  }

  String _signatureSignerLabel(int fid, int? uid) {
    if (uid == null) return AppLocalizations.of(context)!.selectSignerHint;

    final username = _assignedName[fid] ?? '';
    final family = _assignedFamily[fid] ?? '';
    final given = _assignedGiven[fid] ?? '';
    final email = _assignedEmail[fid] ?? '';

    final fullName = '$family$given'.trim();
    final displayName = (_assignedDisplayName[fid] ?? '').trim();
    final emailText = email.isNotEmpty ? ' <$email>' : '';
    final name = displayName.isNotEmpty
        ? displayName
        : fullName.isNotEmpty
            ? fullName
            : '-';
    final account =
        username.isNotEmpty && username != name ? ' ($username)' : '';

    return '$name$account$emailText';
  }

  Future<void> _selectSignerForSignatureField(int fid, int? myUid) async {
    final int? versionId = _latestVersionId;
    if (versionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing document version')),
      );
      return;
    }

    final picked = await SignerPicker.show(
      context,
      versionId: versionId,
    );
    if (picked == null || !mounted) return;

    final int pickedId = (picked['id'] as num).toInt();
    setState(() {
      _selectedSigner[fid] = pickedId;
      _assignedName[fid] = picked['username'] as String? ?? '';
      _assignedDisplayName[fid] = userDisplayName(picked);
      _assignedFamily[fid] = picked['family_name'] as String? ?? '';
      _assignedGiven[fid] = picked['given_name'] as String? ?? '';
      _assignedEmail[fid] = picked['email'] as String? ?? '';
      _pendingSigBytes.remove(fid);
      _draftDirtyPendingSignatureFields.remove(fid);
    });
    _scheduleDraftAutosave();

    if (pickedId == myUid) {
      final bytes = await _openPad();
      if (bytes != null && mounted) {
        setState(() {
          _pendingSigBytes[fid] = bytes;
          _draftDirtyPendingSignatureFields.add(fid);
        });
        _scheduleDraftAutosave();
      }
    }
  }

  // 將所有 {sgn} 欄位集中顯示
  Widget _buildSignatureSection() {
    if (_signatureFieldIdsCache.isEmpty) return const SizedBox.shrink();
    final myUid = context.read<UnifiedAuthProvider>().userId;
    final Map<int, dynamic> fieldsById = <int, dynamic>{
      for (final int fieldId in _signatureFieldIdsCache)
        if (_fieldsById[fieldId] != null) fieldId: _fieldsById[fieldId],
    };
    final List<int> orderedFieldIds =
        _signatureFieldOrder.where(fieldsById.containsKey).toList();
    final bool hasExistingTasks =
        orderedFieldIds.any((fid) => _taskIdOfField[fid] != null);

    if (kIsWeb) {
      return _buildWebSignatureSection(
        fieldsById: fieldsById,
        orderedFieldIds: orderedFieldIds,
        hasExistingTasks: hasExistingTasks,
        myUid: myUid,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.signatureSection,
            style: Theme.of(context).textTheme.titleMedium),
        const Divider(),
        _buildSignatureFlowPanel(hasExistingTasks),
        const SizedBox(height: 12),
        if (_orderedSigning && !hasExistingTasks)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: _reorderSignatureFields,
            children: [
              for (int index = 0; index < orderedFieldIds.length; index++)
                Container(
                  key: ValueKey('signature-$index-${orderedFieldIds[index]}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: _buildSignatureField(
                    fieldsById[orderedFieldIds[index]],
                    myUid,
                    displayOrder: index + 1,
                    reorderIndex: index,
                    showDragHandle: true,
                  ),
                ),
            ],
          )
        else
          for (int index = 0; index < orderedFieldIds.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSignatureField(
                fieldsById[orderedFieldIds[index]],
                myUid,
                displayOrder: _taskIdOfField[orderedFieldIds[index]] != null
                    ? _assignedOrder[orderedFieldIds[index]]
                    : (_orderedSigning ? index + 1 : null),
              ),
            ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWebSignatureSection({
    required Map<int, dynamic> fieldsById,
    required List<int> orderedFieldIds,
    required bool hasExistingTasks,
    required int? myUid,
  }) {
    if (orderedFieldIds.isEmpty) return const SizedBox.shrink();

    final AppLocalizations l = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool showOrderColumn = _orderedSigning;
    final int assignedCount =
        orderedFieldIds.where((int id) => _selectedSigner[id] != null).length;
    final int signedCount = orderedFieldIds
        .where((int id) =>
            normalizeSignatureTaskStatus(_assignedSts[id]) == 'signed')
        .length;

    final Widget list = _orderedSigning && !hasExistingTasks
        ? ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: _reorderSignatureFields,
            children: <Widget>[
              for (int index = 0; index < orderedFieldIds.length; index++)
                KeyedSubtree(
                  key: ValueKey(
                      'web-signature-$index-${orderedFieldIds[index]}'),
                  child: _buildWebSignatureField(
                    fieldsById[orderedFieldIds[index]],
                    myUid,
                    displayOrder: index + 1,
                    reorderIndex: index,
                    showDragHandle: true,
                    showOrderColumn: showOrderColumn,
                  ),
                ),
            ],
          )
        : Column(
            children: <Widget>[
              for (int index = 0; index < orderedFieldIds.length; index++)
                _buildWebSignatureField(
                  fieldsById[orderedFieldIds[index]],
                  myUid,
                  displayOrder: _orderedSigning
                      ? (_taskIdOfField[orderedFieldIds[index]] != null
                          ? _assignedOrder[orderedFieldIds[index]]
                          : index + 1)
                      : null,
                  showOrderColumn: showOrderColumn,
                ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildWebSectionHeader(
            l.signatureFlow,
            trailing: Text(
              hasExistingTasks
                  ? '已完成 $signedCount / ${orderedFieldIds.length}'
                  : '已指派 $assignedCount / ${orderedFieldIds.length}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      _buildWebStatusPill(
                        _orderedSigning ? l.signInOrder : l.anyOrder,
                        background: cs.primaryContainer,
                        foreground: cs.onPrimaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hasExistingTasks
                              ? l.signingOrderLocked
                              : (_orderedSigning
                                  ? l.orderedSigningDragHint
                                  : l.freeSigningHint),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (!hasExistingTasks) ...<Widget>[
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 340,
                          child: SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: <ButtonSegment<bool>>[
                              ButtonSegment<bool>(
                                value: false,
                                label: Text(l.anyOrder),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                label: Text(l.signInOrder),
                              ),
                            ],
                            selected: <bool>{_orderedSigning},
                            onSelectionChanged: (Set<bool> values) {
                              setState(() => _orderedSigning = values.first);
                              _scheduleDraftAutosave();
                            },
                          ),
                        ),
                      ] else ...<Widget>[
                        const SizedBox(width: 16),
                        _buildWebStatusPill(
                          '流程已鎖定',
                          background: cs.surfaceContainerHighest,
                          foreground: cs.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                _buildWebSignatureTableHeader(showOrderColumn: showOrderColumn),
                list,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebSignatureTableHeader({required bool showOrderColumn}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextStyle? style = theme.textTheme.labelLarge?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
      child: Row(
        children: <Widget>[
          if (showOrderColumn)
            SizedBox(width: 82, child: Text('順序', style: style)),
          Expanded(flex: 3, child: Text('簽核角色', style: style)),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: Text('簽核人員', style: style)),
          const SizedBox(width: 16),
          SizedBox(width: 118, child: Text('狀態', style: style)),
          const SizedBox(width: 16),
          SizedBox(
            width: 132,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('動作', style: style),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebSignatureField(
    dynamic f,
    int? myUid, {
    int? displayOrder,
    int? reorderIndex,
    bool showDragHandle = false,
    bool showOrderColumn = false,
  }) {
    final int fid = f['field_id'] as int;
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int? taskId = _taskIdOfField[fid];
    final int? signerId = _selectedSigner[fid];
    final String status = _assignedSts[fid] ?? 'pending';
    final String statusLabel = taskId == null
        ? '未建立任務'
        : signatureTaskStatusLabel(status, AppLocalizations.of(context)!);
    final String comment = _assignedCmt[fid] ?? '';
    final bool signerCanSign = taskId != null &&
        signerId == myUid &&
        isActionableSignatureTaskStatus(status);
    final Widget action = SizedBox(
      width: 132,
      child: Align(
        alignment: Alignment.centerRight,
        child: taskId == null
            ? OutlinedButton(
                onPressed: _mainDocumentLocked
                    ? null
                    : () => _selectSignerForSignatureField(fid, myUid),
                child: const Text('選擇人員'),
              )
            : signerCanSign
                ? FilledButton.tonal(
                    onPressed: () async {
                      final bytes = await _openPad();
                      if (bytes != null && mounted) {
                        setState(() {
                          _pendingSigBytes[fid] = bytes;
                          _draftDirtyPendingSignatureFields.add(fid);
                        });
                        _scheduleDraftAutosave();
                      }
                    },
                    child: Text(AppLocalizations.of(context)!.tapToSign),
                  )
                : Text(
                    '—',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (showOrderColumn)
                SizedBox(
                  width: 82,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildWebStatusPill(
                      displayOrder == null
                          ? '—'
                          : AppLocalizations.of(context)!
                              .orderRank(displayOrder.toString()),
                      background: cs.surfaceContainerHighest,
                      foreground: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              Expanded(
                flex: 3,
                child: Row(
                  children: <Widget>[
                    if (showDragHandle && reorderIndex != null)
                      ReorderableDragStartListener(
                        index: reorderIndex,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.drag_indicator,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        _signatureFieldTitle(f),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Text(
                  _signatureSignerLabel(fid, signerId),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 118,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildWebSignatureStatusPill(
                    taskId: taskId,
                    status: status,
                    label: statusLabel,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              action,
            ],
          ),
          if (comment.isNotEmpty)
            _buildSignatureCommentPanel(status: status, comment: comment),
          if (signerId == myUid && taskId == null) ...<Widget>[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: _inlineSignPreview(fid),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebSignatureStatusPill({
    required int? taskId,
    required String status,
    required String label,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String normalized = normalizeSignatureTaskStatus(status);
    Color background = cs.surfaceContainerHighest;
    Color foreground = cs.onSurfaceVariant;

    if (taskId != null) {
      switch (normalized) {
        case 'signed':
          background = cs.tertiaryContainer;
          foreground = cs.onTertiaryContainer;
          break;
        case 'rejected':
          background = cs.errorContainer;
          foreground = cs.onErrorContainer;
          break;
        case 'commented':
        case 'skipped':
          background = cs.secondaryContainer;
          foreground = cs.onSecondaryContainer;
          break;
        case 'pending':
        default:
          background = cs.primaryContainer;
          foreground = cs.onPrimaryContainer;
          break;
      }
    }

    return _buildWebStatusPill(
      label,
      background: background,
      foreground: foreground,
    );
  }

  Widget _buildBundleSection() {
    if (kIsWeb) {
      return _buildWebBundleSection();
    }

    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool canCreatePhoto = _bundleCapabilityFlag('圖片表格列', 'can_create');
    final bool canCreateAudit = _bundleCapabilityFlag('缺失稽核改善', 'can_create');
    final bool canLinkExisting =
        _bundleCapabilityFlag('圖片表格列', 'can_link_existing') ||
            _bundleCapabilityFlag('缺失稽核改善', 'can_link_existing');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSectionHeader('附屬子文件'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (canCreatePhoto)
                OutlinedButton.icon(
                  onPressed: _mainDocumentLocked
                      ? null
                      : () => _createBundleChildDraft('圖片表格列'),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('新增圖片表格列'),
                ),
              if (canCreateAudit)
                OutlinedButton.icon(
                  onPressed: _mainDocumentLocked
                      ? null
                      : () => _createBundleChildDraft('缺失稽核改善'),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('新增缺失稽核改善'),
                ),
              if (canLinkExisting)
                OutlinedButton.icon(
                  onPressed:
                      _mainDocumentLocked ? null : _linkExistingChildDocument,
                  icon: const Icon(Icons.link_outlined),
                  label: const Text('掛載既有子文件'),
                ),
            ],
          ),
        ),
        if (_newChildDrafts.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            '待建立子文件',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...List<Widget>.generate(_newChildDrafts.length, (int index) {
            final BundleChildDraftResult draft = _newChildDrafts[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(
                  draft.documentTypeName == '圖片表格列'
                      ? Icons.photo_library_outlined
                      : Icons.fact_check_outlined,
                ),
                title: Text(draft.documentTypeName),
                subtitle: Text(_newChildSummary(draft)),
                trailing: Wrap(
                  spacing: 4,
                  children: <Widget>[
                    IconButton(
                      tooltip: '編輯',
                      onPressed: _mainDocumentLocked
                          ? null
                          : () => _editNewChildDraft(index),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '移除',
                      onPressed: _mainDocumentLocked
                          ? null
                          : () {
                              setState(() => _newChildDrafts.removeAt(index));
                              _scheduleDraftAutosave();
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 12),
        if (_linkedChildren.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              '目前沒有掛載的圖片表格列或缺失稽核改善。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          ...List<Widget>.generate(_linkedChildren.length, (int index) {
            final Map<String, dynamic> item = _linkedChildren[index];
            final int documentId = _childDocumentId(item);
            final bool hasPendingDraft =
                _pendingChildDrafts.containsKey(documentId);
            final bool locked = _childLocked(item) || _mainDocumentLocked;
            final int? effectiveVersionId = _childEffectiveVersionId(item);
            final int? effectiveVersionNum =
                (_childLink(item)['effective_version_num'] as num?)?.toInt();
            final int? pinnedVersionId = _childPinnedVersionId(item);
            final String fullFileCode = _childFullFileCode(item);
            final String typeName = _childDocumentTypeName(item);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: <Widget>[
                                  Text(
                                    fullFileCode.isEmpty
                                        ? typeName
                                        : '$fullFileCode  $typeName',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (hasPendingDraft)
                                    Chip(
                                      label: const Text('未儲存編輯'),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  if (locked)
                                    Chip(
                                      label: const Text('唯讀'),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_linkedChildSummary(item)}  ·  目前版本 v${effectiveVersionNum ?? '-'}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pinnedVersionId == null
                                    ? '版本策略：跟隨最新'
                                    : '版本策略：固定到 $pinnedVersionId',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: <Widget>[
                            IconButton(
                              tooltip: WidgetsLocalizations.of(context)
                                  .reorderItemUp,
                              onPressed: locked || index == 0
                                  ? null
                                  : () => _moveLinkedChild(index, -1),
                              icon: const Icon(Icons.keyboard_arrow_up),
                            ),
                            IconButton(
                              tooltip: WidgetsLocalizations.of(context)
                                  .reorderItemDown,
                              onPressed:
                                  locked || index == _linkedChildren.length - 1
                                      ? null
                                      : () => _moveLinkedChild(index, 1),
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: locked ||
                                  !_bundleCapabilityFlag(typeName, 'can_edit')
                              ? null
                              : () => _editLinkedChildDraft(item),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('編輯'),
                        ),
                        OutlinedButton.icon(
                          onPressed: locked ||
                                  !_bundleCapabilityFlag(
                                      typeName, 'can_select_version')
                              ? null
                              : () => _pickPinnedVersion(item),
                          icon: const Icon(Icons.push_pin_outlined),
                          label: Text(
                            pinnedVersionId == null ? '跟隨最新' : '固定版本',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              locked ? null : () => _unlinkLinkedChild(item),
                          icon: const Icon(Icons.link_off_outlined),
                          label: const Text('解除關聯'),
                        ),
                        OutlinedButton.icon(
                          onPressed: effectiveVersionId == null
                              ? null
                              : () => _launchVersionDownload(
                                    effectiveVersionId,
                                    'docx',
                                  ),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('DOCX'),
                        ),
                        OutlinedButton.icon(
                          onPressed: effectiveVersionId == null
                              ? null
                              : () => _launchVersionDownload(
                                    effectiveVersionId,
                                    'pdf',
                                  ),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('PDF'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildWebBundleSection() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool canCreatePhoto = _bundleCapabilityFlag('圖片表格列', 'can_create');
    final bool canCreateAudit = _bundleCapabilityFlag('缺失稽核改善', 'can_create');
    final bool canLinkExisting =
        _bundleCapabilityFlag('圖片表格列', 'can_link_existing') ||
            _bundleCapabilityFlag('缺失稽核改善', 'can_link_existing');

    final List<Widget> rows = <Widget>[
      for (int index = 0; index < _newChildDrafts.length; index++)
        _buildWebNewChildDraftRow(index),
      for (int index = 0; index < _linkedChildren.length; index++)
        _buildWebLinkedChildRow(index),
    ];
    final int totalCount = rows.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildWebSectionHeader(
            '附屬子文件',
            trailing: Text(
              '$totalCount 筆',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      final Widget summary = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '關聯文件',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '建立或掛載會隨主文件一併送審的圖片表格列、缺失稽核改善與既有文件。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      );
                      final Widget actions = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          if (canCreatePhoto)
                            _buildWebBundleActionButton(
                              icon: Icons.photo_library_outlined,
                              label: '圖片表格列',
                              onPressed: _mainDocumentLocked
                                  ? null
                                  : () => _createBundleChildDraft('圖片表格列'),
                            ),
                          if (canCreateAudit)
                            _buildWebBundleActionButton(
                              icon: Icons.fact_check_outlined,
                              label: '缺失稽核改善',
                              onPressed: _mainDocumentLocked
                                  ? null
                                  : () => _createBundleChildDraft('缺失稽核改善'),
                            ),
                          if (canLinkExisting)
                            _buildWebBundleActionButton(
                              icon: Icons.link_outlined,
                              label: '掛載既有',
                              onPressed: _mainDocumentLocked
                                  ? null
                                  : _linkExistingChildDocument,
                            ),
                        ],
                      );

                      if (constraints.maxWidth < 900) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            summary,
                            const SizedBox(height: 12),
                            actions,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Expanded(child: summary),
                          const SizedBox(width: 24),
                          actions,
                        ],
                      );
                    },
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '目前沒有掛載的圖片表格列或缺失稽核改善。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                else ...<Widget>[
                  _buildWebBundleTableHeader(),
                  ...rows,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebBundleActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildWebBundleTableHeader() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextStyle? style = theme.textTheme.labelLarge?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
      child: Row(
        children: <Widget>[
          Expanded(flex: 4, child: Text('文件', style: style)),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: Text('資訊', style: style)),
          const SizedBox(width: 16),
          SizedBox(width: 190, child: Text('狀態', style: style)),
          const SizedBox(width: 16),
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('動作', style: style),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebNewChildDraftRow(int index) {
    final BundleChildDraftResult draft = _newChildDrafts[index];
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  draft.documentTypeName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Text(
              _newChildSummary(draft),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildWebStatusPill(
                '待建立',
                background: cs.primaryContainer,
                foreground: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                IconButton(
                  tooltip: '編輯',
                  onPressed: _mainDocumentLocked
                      ? null
                      : () => _editNewChildDraft(index),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '移除',
                  onPressed: _mainDocumentLocked
                      ? null
                      : () {
                          setState(() => _newChildDrafts.removeAt(index));
                          _scheduleDraftAutosave();
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLinkedChildRow(int index) {
    final Map<String, dynamic> item = _linkedChildren[index];
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int documentId = _childDocumentId(item);
    final bool hasPendingDraft = _pendingChildDrafts.containsKey(documentId);
    final bool locked = _childLocked(item) || _mainDocumentLocked;
    final int? effectiveVersionId = _childEffectiveVersionId(item);
    final int? effectiveVersionNum =
        (_childLink(item)['effective_version_num'] as num?)?.toInt();
    final int? pinnedVersionId = _childPinnedVersionId(item);
    final String fullFileCode = _childFullFileCode(item);
    final String typeName = _childDocumentTypeName(item);

    void onMenuSelected(String value) {
      switch (value) {
        case 'up':
          unawaited(_moveLinkedChild(index, -1));
          break;
        case 'down':
          unawaited(_moveLinkedChild(index, 1));
          break;
        case 'edit':
          unawaited(_editLinkedChildDraft(item));
          break;
        case 'pin':
          unawaited(_pickPinnedVersion(item));
          break;
        case 'unlink':
          unawaited(_unlinkLinkedChild(item));
          break;
        case 'docx':
          if (effectiveVersionId != null) {
            unawaited(_launchVersionDownload(effectiveVersionId, 'docx'));
          }
          break;
        case 'pdf':
          if (effectiveVersionId != null) {
            unawaited(_launchVersionDownload(effectiveVersionId, 'pdf'));
          }
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  fullFileCode.isEmpty ? typeName : '$fullFileCode  $typeName',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_linkedChildSummary(item)} · v${effectiveVersionNum ?? '-'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  pinnedVersionId == null
                      ? '版本：跟隨最新'
                      : '版本：固定到 $pinnedVersionId',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                if (hasPendingDraft)
                  _buildWebStatusPill(
                    '未儲存編輯',
                    background: cs.tertiaryContainer,
                    foreground: cs.onTertiaryContainer,
                  ),
                if (locked)
                  _buildWebStatusPill(
                    '唯讀',
                    background: cs.surfaceContainerHighest,
                    foreground: cs.onSurfaceVariant,
                  ),
                if (!hasPendingDraft && !locked)
                  _buildWebStatusPill(
                    '已掛載',
                    background: cs.secondaryContainer,
                    foreground: cs.onSecondaryContainer,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: '更多動作',
                onSelected: onMenuSelected,
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'edit',
                    enabled:
                        !locked && _bundleCapabilityFlag(typeName, 'can_edit'),
                    child: const Text('編輯'),
                  ),
                  PopupMenuItem<String>(
                    value: 'pin',
                    enabled: !locked &&
                        _bundleCapabilityFlag(typeName, 'can_select_version'),
                    child: Text(pinnedVersionId == null ? '固定版本' : '跟隨最新'),
                  ),
                  PopupMenuItem<String>(
                    value: 'up',
                    enabled: !locked && index > 0,
                    child: const Text('上移'),
                  ),
                  PopupMenuItem<String>(
                    value: 'down',
                    enabled: !locked && index < _linkedChildren.length - 1,
                    child: const Text('下移'),
                  ),
                  PopupMenuItem<String>(
                    value: 'unlink',
                    enabled: !locked,
                    child: const Text('解除關聯'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'docx',
                    enabled: effectiveVersionId != null,
                    child: const Text('下載 DOCX'),
                  ),
                  PopupMenuItem<String>(
                    value: 'pdf',
                    enabled: effectiveVersionId != null,
                    child: const Text('下載 PDF'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebStatusPill(
    String label, {
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildSignatureFlowPanel(bool hasExistingTasks) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!.signatureFlow,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (hasExistingTasks) ...[
            Text(
              _orderedSigning
                  ? AppLocalizations.of(context)!.orderedSigningActive
                  : AppLocalizations.of(context)!.freeSigningActive,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.signingOrderLocked,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    icon: const Icon(Icons.hub_outlined, size: 18),
                    label: Text(AppLocalizations.of(context)!.anyOrder),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.reorder, size: 18),
                    label: Text(AppLocalizations.of(context)!.signInOrder),
                  ),
                ],
                selected: <bool>{_orderedSigning},
                onSelectionChanged: (Set<bool> values) {
                  setState(() => _orderedSigning = values.first);
                  _scheduleDraftAutosave();
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _orderedSigning
                  ? AppLocalizations.of(context)!.orderedSigningDragHint
                  : AppLocalizations.of(context)!.freeSigningHint,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSignatureCommentPanel({
    required String status,
    required String comment,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String normalizedStatus = normalizeSignatureTaskStatus(status);
    final bool isRejected = normalizedStatus == 'rejected';
    final bool requiresComment =
        signatureTaskStatusRequiresComment(normalizedStatus);

    final Color backgroundColor = isRejected
        ? cs.errorContainer
        : requiresComment
            ? cs.tertiaryContainer
            : cs.surfaceContainerHighest;
    final Color foregroundColor = isRejected
        ? cs.onErrorContainer
        : requiresComment
            ? cs.onTertiaryContainer
            : cs.onSurfaceVariant;
    final IconData icon = isRejected
        ? Icons.error_outline
        : requiresComment
            ? Icons.feedback_outlined
            : Icons.chat_bubble_outline;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              comment,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foregroundColor,
                    fontWeight:
                        requiresComment ? FontWeight.w500 : FontWeight.normal,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureField(
    dynamic f,
    int? myUid, {
    int? displayOrder,
    int? reorderIndex,
    bool showDragHandle = false,
  }) {
    final int fid = f['field_id'] as int;
    final String desc = f['description'] as String? ?? '';
    final ColorScheme cs = Theme.of(context).colorScheme;

    /*──────────── 共用：產生顯示用文字 ────────────*/
    String composeLabel(int? uid) => _signatureSignerLabel(fid, uid);

    Widget buildHeader() {
      return Row(
        children: [
          if (displayOrder != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                AppLocalizations.of(context)!
                    .orderRank(displayOrder.toString()),
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              desc.isEmpty
                  ? AppLocalizations.of(context)!.signatureFieldLabel
                  : desc,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (showDragHandle && reorderIndex != null)
            ReorderableDragStartListener(
              index: reorderIndex,
              child: Icon(Icons.drag_indicator, color: cs.onSurfaceVariant),
            ),
        ],
      );
    }

    /*─────────── 1) 已存在任務 → 只顯示 ───────────*/
    final int? taskId = _taskIdOfField[fid];
    if (taskId != null) {
      final int? sid = _selectedSigner[fid];
      final String status = _assignedSts[fid] ?? 'pending';
      final String cmt = _assignedCmt[fid] ?? '';
      final String statusLabel = signatureTaskStatusLabel(
        status,
        AppLocalizations.of(context)!,
      );

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildHeader(),
            const SizedBox(height: 10),
            Text('${composeLabel(sid)}（$statusLabel）'),
            if (cmt.isNotEmpty)
              signatureTaskStatusRequiresComment(status)
                  ? _buildSignatureCommentPanel(
                      status: status,
                      comment: cmt,
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        AppLocalizations.of(context)!.commentLabel(cmt),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
            if (sid == myUid && isActionableSignatureTaskStatus(status)) ...[
              const SizedBox(height: 10),
              _inlineSignPreview(fid),
            ],
          ],
        ),
      );
    }

    /*─────────── 2) 未指派 signer → 可挑選 ─────────*/
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildHeader(),
          const SizedBox(height: 10),

          /*── 點擊區塊 ─*/
          GestureDetector(
            onTap: () => _selectSignerForSignatureField(fid, myUid),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      composeLabel(_selectedSigner[fid]),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          if (_selectedSigner[fid] == myUid) ...[
            const SizedBox(height: 8),
            _inlineSignPreview(fid),
          ],
        ],
      ),
    );
  }
}

enum _EditContentItemType {
  sectionHeader,
  paragraphField,
  tableSection,
  spacer,
  signatureSection,
  bundleSection,
  saveButton,
}

class _EditContentItem {
  const _EditContentItem(
    this.type, {
    this.part,
    this.field,
    this.tableSection,
    this.height = 0,
  });

  factory _EditContentItem.sectionHeader(String part) {
    return _EditContentItem(_EditContentItemType.sectionHeader, part: part);
  }

  factory _EditContentItem.paragraphField(dynamic field) {
    return _EditContentItem(_EditContentItemType.paragraphField, field: field);
  }

  factory _EditContentItem.tableSection(_TableSectionInfo section) {
    return _EditContentItem(
      _EditContentItemType.tableSection,
      tableSection: section,
    );
  }

  factory _EditContentItem.spacer(double height) {
    return _EditContentItem(_EditContentItemType.spacer, height: height);
  }

  final _EditContentItemType type;
  final String? part;
  final dynamic field;
  final _TableSectionInfo? tableSection;
  final double height;
}

class _TableSectionInfo {
  const _TableSectionInfo({
    required this.tableIndex,
    required this.rows,
    required this.rowIndexByNumber,
    required this.maxCol,
    required this.cells,
  });

  final int tableIndex;
  final List<int> rows;
  final Map<int, int> rowIndexByNumber;
  final int maxCol;
  final List<_TableCellInfo> cells;
}

// 表格 cell 資訊
class _TableCellInfo {
  final dynamic field;
  final int row;
  final int col;
  final int colSpan;
  final int rowSpan;
  final List<int> mergedFieldIds;
  _TableCellInfo({
    required this.field,
    required this.row,
    required this.col,
    required this.colSpan,
    required this.rowSpan,
    required this.mergedFieldIds,
  });
}

/// 自動合併相鄰行中、同欄、相同內容的標籤存格
/// （相当於 Office 的合併存格）
List<_TableCellInfo> _autoMergeCells(
  List<_TableCellInfo> cells,
  List<int> rows,
) {
  bool isMergeable(_TableCellInfo c) {
    final raw = (c.field['original_text'] as String? ?? '').trim();
    return raw.isNotEmpty &&
        raw != '{cb}' &&
        raw != 'V' &&
        raw != '{sgn}' &&
        !raw.startsWith('data:image/png');
  }

  // 依欄位 (col, colSpan) 分組；以 record key 避免建立字串索引。
  final Map<(int, int), List<_TableCellInfo>> byCol =
      <(int, int), List<_TableCellInfo>>{};
  for (final c in cells) {
    byCol.putIfAbsent((c.col, c.colSpan), () => <_TableCellInfo>[]).add(c);
  }

  final toRemove = <_TableCellInfo>{};
  final newSpan = <_TableCellInfo, int>{};
  final Map<int, int> rowOrder = <int, int>{
    for (int i = 0; i < rows.length; i++) rows[i]: i,
  };
  for (final group in byCol.values) {
    group.sort(
      (a, b) => rowOrder[a.row]!.compareTo(rowOrder[b.row]!),
    );

    int i = 0;
    while (i < group.length) {
      final head = group[i];
      if (!isMergeable(head)) {
        i++;
        continue;
      }
      final headText = (head.field['original_text'] as String? ?? '').trim();
      int totalSpan = head.rowSpan;
      int expected = rowOrder[head.row]! + head.rowSpan;
      int count = 1;
      final List<int> mergedFieldIds = <int>[...head.mergedFieldIds];

      while (i + count < group.length) {
        final next = group[i + count];
        final int nextIdx = rowOrder[next.row]!;
        final nextText = (next.field['original_text'] as String? ?? '').trim();
        if (nextIdx == expected && isMergeable(next) && nextText == headText) {
          totalSpan += next.rowSpan;
          expected = nextIdx + next.rowSpan;
          mergedFieldIds.addAll(next.mergedFieldIds);
          count++;
        } else {
          break;
        }
      }

      if (count > 1) {
        newSpan[head] = totalSpan;
        head.field['merged_field_ids'] = mergedFieldIds;
        for (int m = 1; m < count; m++) {
          toRemove.add(group[i + m]);
        }
      } else {
        head.field['merged_field_ids'] = mergedFieldIds;
      }
      i += count;
    }
  }

  final List<_TableCellInfo> merged = <_TableCellInfo>[];
  for (final _TableCellInfo cell in cells) {
    if (toRemove.contains(cell)) continue;
    final int? rowSpan = newSpan[cell];
    merged.add(
      rowSpan == null
          ? cell
          : _TableCellInfo(
              field: cell.field,
              row: cell.row,
              col: cell.col,
              colSpan: cell.colSpan,
              rowSpan: rowSpan,
              mergedFieldIds: cell.mergedFieldIds,
            ),
    );
  }
  return merged;
}
