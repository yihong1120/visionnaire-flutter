import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/document_draft.dart';
import '../../providers/unified_auth_provider.dart';
import '../../services/document_draft_attachment_store.dart';
import '../../services/document_draft_remote_store.dart';
import '../../services/document_draft_service.dart';
import '../../services/file_manage_api_service.dart';
import '../../services/unified_image_service.dart';
import '../../widgets/responsive_scaffold.dart';
import 'camera_capture_page.dart';
import '../../widgets/busy_overlay.dart';
import '../../widgets/image_box.dart';
import '../../widgets/labeled_text_field.dart';
import '../../utils/auth_utils.dart';
import '../../utils/file_routes.dart';

class AuditFixDocCreatePage extends StatefulWidget {
  const AuditFixDocCreatePage({
    super.key,
    this.initSite,
    this.fileId,
    this.draftMode = false,
    this.initialEditorPayload,
    this.initialDraftFiles = const <BundleUploadFile>[],
  });
  final dynamic initSite;
  final int? fileId;
  final bool draftMode;
  final Map<String, dynamic>? initialEditorPayload;
  final List<BundleUploadFile> initialDraftFiles;

  @override
  State<AuditFixDocCreatePage> createState() => _AuditFixDocCreatePageState();
}

/*───────────────── 影像資料（含日期 + 顯示開關） ────────────────*/
class _ImgData {
  Uint8List? rawBytes;
  Uint8List? stampedBytes;
  String? stampedDateText;
  String? imageUrl;
  bool showDate;
  final TextEditingController dateCtrl;

  _ImgData(
    this.rawBytes,
    this.stampedBytes,
    String defaultDate, {
    this.showDate = true,
  }) : dateCtrl = TextEditingController(text: defaultDate) {
    if (stampedBytes != null && defaultDate.trim().isNotEmpty) {
      stampedDateText = defaultDate.trim();
    }
  }
}

/*───────────────── 一筆缺失改善 (前 / 中 / 後三張) ───────────────*/
enum _Stage { before, improv, after }

class _FixItem {
  _FixItem({this.sourceIndex});

  final int? sourceIndex;
  _ImgData? before, improv, after;

  final descBefore = TextEditingController();
  final descImprov = TextEditingController();
  final descAfter = TextEditingController();

  bool get isComplete => before != null && improv != null && after != null;

  _Stage? addImage(_ImgData data) {
    if (before == null) {
      before = data;
      return _Stage.improv;
    }
    if (improv == null) {
      improv = data;
      return _Stage.after;
    }
    after ??= data;
    return null;
  }

  _ImgData? dataOf(_Stage s) => switch (s) {
        _Stage.before => before,
        _Stage.improv => improv,
        _Stage.after => after,
      };

  TextEditingController descOf(_Stage s) => switch (s) {
        _Stage.before => descBefore,
        _Stage.improv => descImprov,
        _Stage.after => descAfter,
      };

  void setOptionalData(_Stage s, _ImgData? data) {
    switch (s) {
      case _Stage.before:
        before = data;
      case _Stage.improv:
        improv = data;
      case _Stage.after:
        after = data;
    }
  }

  void setData(_Stage s, _ImgData data) {
    setOptionalData(s, data);
  }

  void swapStages(_Stage first, _Stage second) {
    final _ImgData? firstData = dataOf(first);
    final _ImgData? secondData = dataOf(second);
    final String firstDesc = descOf(first).text;
    final String secondDesc = descOf(second).text;

    setOptionalData(first, secondData);
    setOptionalData(second, firstData);
    descOf(first).text = secondDesc;
    descOf(second).text = firstDesc;
  }

  void clearData(_Stage s) {
    switch (s) {
      case _Stage.before:
        before?.dateCtrl.dispose();
        before = null;
      case _Stage.improv:
        improv?.dateCtrl.dispose();
        improv = null;
      case _Stage.after:
        after?.dateCtrl.dispose();
        after = null;
    }
  }

  void dispose() {
    before?.dateCtrl.dispose();
    improv?.dateCtrl.dispose();
    after?.dateCtrl.dispose();
    descBefore.dispose();
    descImprov.dispose();
    descAfter.dispose();
  }
}

/// Maps a [_FixItem] back to the document field IDs for edit-mode saving.
class _AuditFieldMapping {
  int? imageBeforeFieldId;
  int? imageImprovFieldId;
  int? imageAfterFieldId;
  int? descBeforeFieldId;
  int? descImprovFieldId;
  int? descAfterFieldId;
}

class _AuditFixDocCreatePageState extends State<AuditFixDocCreatePage> {
  final _formKey = GlobalKey<FormState>();

  bool get _isEditMode => widget.fileId != null;
  bool get _isDraftMode => widget.draftMode;

  int? get _selectedSiteId => (_selectedSite?['id'] as num?)?.toInt();

  /*── 站點清單 ───────────────────────────*/
  List<dynamic> _sites = [];
  dynamic _selectedSite;
  bool _siteLoading = true;
  String? _siteErr;

  /*── 稽核日期 ───────────────────────────*/
  late final String _todayStr;
  final _auditDateCtrl = TextEditingController();

  /*── 影像與欄位 ─────────────────────────*/
  final List<_FixItem> _items = [];
  late final DocumentDraftRemoteStore _draftRemoteStore;
  late final DocumentDraftAutosaver _draftAutosaver;
  int? _draftUserId;
  late final String _clientDraftId;
  bool _draftRestoreChecked = false;
  bool _suppressDraftAutosave = false;
  final Set<_FixItem> _draftObservedItems = <_FixItem>{};
  final Set<_ImgData> _draftObservedImages = <_ImgData>{};

  /*── 編輯模式的欄位映射 ──────────────────*/
  /// 每個 _FixItem 對應的欄位 IDs
  final List<_AuditFieldMapping> _fieldMappings = [];
  final List<_AuditFieldMapping> _deletedFieldMappings = [];
  final Set<int> _deletedStructuredItemIndexes = <int>{};

  /// 不屬於圖片/說明但也需要回寫的欄位
  final Map<int, String> _extraFields = {};

  bool _usesStructuredEditorPayload = false;
  String _apiBaseUrl = '';

  /*── Busy overlay ──────────────────────*/
  bool _busy = false;
  void _setBusy(bool v) {
    if (mounted) setState(() => _busy = v);
  }

  @override
  void initState() {
    super.initState();
    _todayStr = DateFormat('yyyy/MM/dd').format(DateTime.now());
    _auditDateCtrl.text = _todayStr;
    final auth = context.read<UnifiedAuthProvider>();
    _draftUserId = auth.userId;
    _clientDraftId = DocumentDraftService.createClientDraftId();
    _draftRemoteStore = DocumentDraftRemoteStore(
      auth: auth,
      enabled: !_isDraftMode,
    );
    _draftAutosaver = DocumentDraftAutosaver(
      type: 'audit_fix',
      keyProvider: _draftKey,
      payloadProvider: _buildLocalDraftPayload,
      remoteLoader: _draftRemoteStore.load,
      remoteSaver: _draftRemoteStore.save,
      remoteDeleter: _draftRemoteStore.delete,
    );
    _auditDateCtrl.addListener(_scheduleDraftAutosave);
    if (_isDraftMode) {
      _initializeDraftMode();
    } else if (_isEditMode) {
      _loadExistingDoc();
    } else {
      _fetchSites();
    }
  }

  @override
  void dispose() {
    if (!_isDraftMode) {
      unawaited(_draftAutosaver.flush());
    }
    _draftAutosaver.dispose();
    for (final item in _items) {
      item.dispose();
    }
    _auditDateCtrl.dispose();
    super.dispose();
  }

  int? get _initSiteId => (widget.initSite?['id'] as num?)?.toInt();

  String _draftKey() {
    if (!_isEditMode) {
      return DocumentDraftService.buildCreateKey(
        draftType: 'audit_fix',
        clientDraftId: _clientDraftId,
      );
    }
    return DocumentDraftService.buildKey(
      draftType: 'audit_fix',
      userId: _draftUserId,
      fileId: widget.fileId,
      siteId: _initSiteId,
      scope: 'create',
    );
  }

  void _scheduleDraftAutosave() {
    if (_isDraftMode || _suppressDraftAutosave || _siteLoading) return;
    _draftAutosaver.schedule();
  }

  void _attachImageDraftListener(_ImgData? data) {
    if (data == null || !_draftObservedImages.add(data)) return;
    data.dateCtrl.addListener(_scheduleDraftAutosave);
  }

  void _attachItemDraftListeners(_FixItem item) {
    if (_draftObservedItems.add(item)) {
      item.descBefore.addListener(_scheduleDraftAutosave);
      item.descImprov.addListener(_scheduleDraftAutosave);
      item.descAfter.addListener(_scheduleDraftAutosave);
    }
    for (final stage in _Stage.values) {
      _attachImageDraftListener(item.dataOf(stage));
    }
  }

  void _attachDraftListenersForAllItems() {
    for (final item in _items) {
      _attachItemDraftListeners(item);
    }
  }

  Future<Map<String, dynamic>?> _buildLocalDraftPayload() async {
    if (_isDraftMode) return null;
    final String draftKey = _draftKey();

    Future<Map<String, dynamic>> stagePayload(
      _FixItem item,
      _Stage stage,
      String stageName,
      int itemIndex,
    ) async {
      final data = item.dataOf(stage);
      final description = item.descOf(stage).text;
      String source = 'empty';
      String? attachmentRef;
      String? imageUrl;

      if (data?.imageUrl != null) {
        source = 'network';
        imageUrl = data!.imageUrl;
      } else if (data?.rawBytes != null) {
        attachmentRef = await DocumentDraftAttachmentStore.saveBytes(
          draftKey: draftKey,
          attachmentId: 'item_${itemIndex}_$stageName.png',
          bytes: data!.rawBytes!,
        );
        if (attachmentRef != null) {
          source = 'attachment';
        } else {
          source = 'unavailable';
        }
      }

      return <String, dynamic>{
        'description': description,
        'source': source,
        if (attachmentRef != null) 'attachment_ref': attachmentRef,
        if (imageUrl != null) 'url': imageUrl,
        'date': data?.dateCtrl.text ?? _auditDateCtrl.text,
        'show_date': data?.showDate ?? false,
      };
    }

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    for (int index = 0; index < _items.length; index++) {
      final item = _items[index];
      items.add(<String, dynamic>{
        'before': await stagePayload(item, _Stage.before, 'before', index),
        'improv': await stagePayload(item, _Stage.improv, 'improv', index),
        'after': await stagePayload(item, _Stage.after, 'after', index),
      });
    }

    if (_auditDateCtrl.text.trim() == _todayStr &&
        _selectedSite == null &&
        items.isEmpty) {
      return null;
    }

    return <String, dynamic>{
      'audit_date': _auditDateCtrl.text,
      'selected_site_id': _selectedSiteId,
      'items': items,
    };
  }

  Future<void> _maybeRestoreLocalDraft() async {
    if (_isDraftMode || _draftRestoreChecked || !mounted) return;
    _draftRestoreChecked = true;

    final DocumentDraft? draft = await _draftAutosaver.load();
    if (draft == null || !mounted) return;

    final bool? restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
      _draftObservedItems.clear();
      _draftObservedImages.clear();

      final payload = draft.payload;
      _auditDateCtrl.text = (payload['audit_date'] as String?) ?? _todayStr;

      final int? selectedSiteId =
          (payload['selected_site_id'] as num?)?.toInt();
      if (selectedSiteId != null) {
        for (final site in _sites) {
          if ((site['id'] as num?)?.toInt() == selectedSiteId) {
            _selectedSite = site;
            break;
          }
        }
      }

      Future<_ImgData?> restoreStage(Map<String, dynamic> stage) async {
        final source = (stage['source'] as String?) ?? '';
        final dateText = (stage['date'] as String?) ?? _auditDateCtrl.text;
        final showDate = stage['show_date'] != false;
        if (source == 'network') {
          final url = (stage['url'] as String?)?.trim();
          if (url == null || url.isEmpty) return null;
          return _ImgData(null, null, dateText, showDate: showDate)
            ..imageUrl = url;
        }
        if (source == 'attachment') {
          final reference = stage['attachment_ref'] as String?;
          if (reference == null) return null;
          final bytes = await DocumentDraftAttachmentStore.readBytes(reference);
          if (bytes == null) return null;
          return _ImgData(bytes, null, dateText, showDate: showDate);
        }
        return null;
      }

      final List<dynamic> items =
          payload['items'] as List<dynamic>? ?? const <dynamic>[];
      for (final dynamic rawItem in items) {
        if (rawItem is! Map) continue;
        final itemPayload = Map<String, dynamic>.from(rawItem);
        final item = _FixItem();

        Future<void> assign(_Stage stage, String key) async {
          final rawStage = itemPayload[key];
          if (rawStage is! Map) return;
          final stagePayload = Map<String, dynamic>.from(rawStage);
          item.descOf(stage).text =
              (stagePayload['description'] as String?) ?? '';
          final data = await restoreStage(stagePayload);
          if (data != null) {
            item.setData(stage, data);
          }
        }

        await assign(_Stage.before, 'before');
        await assign(_Stage.improv, 'improv');
        await assign(_Stage.after, 'after');
        _attachItemDraftListeners(item);
        _items.add(item);
      }

      if (!mounted) return;
      setState(() {});
    } finally {
      _suppressDraftAutosave = false;
    }
  }

  Future<void> _initializeDraftMode() async {
    try {
      _apiBaseUrl = await FileManageAPIService.baseUrl;
    } catch (_) {}

    if (widget.initialEditorPayload != null) {
      _loadAuditFixPayload(widget.initialEditorPayload!);
    }

    if (widget.initSite != null) {
      _sites = <dynamic>[widget.initSite];
      _selectedSite = widget.initSite;
    }

    if (!mounted) return;
    setState(() => _siteLoading = false);
  }

  void _resetDeletedItemState() {
    _deletedFieldMappings.clear();
    _deletedStructuredItemIndexes.clear();
  }

  bool get _hasPendingItemDeletes =>
      _deletedFieldMappings.isNotEmpty ||
      _deletedStructuredItemIndexes.isNotEmpty;

  void _appendClearedAuditFields(
    List<Map<String, dynamic>> fillData,
    _AuditFieldMapping mapping,
  ) {
    if (mapping.imageBeforeFieldId != null) {
      fillData.add({
        'field_id': '${mapping.imageBeforeFieldId}',
        'new_text': '',
      });
    }
    if (mapping.imageImprovFieldId != null) {
      fillData.add({
        'field_id': '${mapping.imageImprovFieldId}',
        'new_text': '',
      });
    }
    if (mapping.imageAfterFieldId != null) {
      fillData.add({
        'field_id': '${mapping.imageAfterFieldId}',
        'new_text': '',
      });
    }
    if (mapping.descBeforeFieldId != null) {
      fillData.add({
        'field_id': '${mapping.descBeforeFieldId}',
        'new_text': '',
      });
    }
    if (mapping.descImprovFieldId != null) {
      fillData.add({
        'field_id': '${mapping.descImprovFieldId}',
        'new_text': '',
      });
    }
    if (mapping.descAfterFieldId != null) {
      fillData.add({
        'field_id': '${mapping.descAfterFieldId}',
        'new_text': '',
      });
    }
  }

  void _removeItemAt(int idx) {
    if (idx < 0 || idx >= _items.length) return;

    final _FixItem removedItem = _items[idx];
    setState(() {
      if (_isEditMode) {
        if (_usesStructuredEditorPayload) {
          final int? sourceIndex = removedItem.sourceIndex;
          if (sourceIndex != null) {
            _deletedStructuredItemIndexes.add(sourceIndex);
          }
        } else if (idx < _fieldMappings.length) {
          _deletedFieldMappings.add(_fieldMappings.removeAt(idx));
        }
      }
      _items.removeAt(idx);
    });

    removedItem.dispose();
    _draftObservedItems.remove(removedItem);
    _scheduleDraftAutosave();
  }

  /*──────────────── 取得工地清單 ────────────────*/
  Future<void> _fetchSites() async {
    try {
      _sites = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getMySites(token: token),
      );
      // 自動選擇傳入的站點
      if (widget.initSite != null) {
        _selectedSite = _sites.firstWhere(
          (s) => s['id'] == widget.initSite['id'],
          orElse: () => null,
        );
      }
    } catch (e) {
      _siteErr = '讀取工地清單失敗：$e';
    } finally {
      if (mounted) {
        setState(() => _siteLoading = false);
        unawaited(_maybeRestoreLocalDraft());
      }
    }
  }

  Uint8List? _decodeDataUriBytes(String? value) {
    final dataUri = value?.trim() ?? '';
    if (dataUri.isEmpty) return null;

    try {
      return base64Decode(dataUri.split(',').last);
    } catch (_) {
      return null;
    }
  }

  _ImgData? _imgDataFromEditorStage(
    Map<String, dynamic> stagePayload, {
    required String defaultDate,
  }) {
    final Map<String, dynamic> uiState = stagePayload['_ui'] is Map
        ? Map<String, dynamic>.from(stagePayload['_ui'] as Map)
        : <String, dynamic>{};
    final bool showDate = uiState['show_date'] == true;
    final dynamic imageValue =
        stagePayload['image'] ?? stagePayload['image_data_uri'];
    final dateStr = (stagePayload['date'] as String?)?.trim().isNotEmpty == true
        ? (stagePayload['date'] as String).trim()
        : defaultDate;

    if (imageValue is Map) {
      final Map<String, dynamic> imageMap =
          Map<String, dynamic>.from(imageValue);
      final String mode = (imageMap['mode'] as String? ?? '').trim();
      if (mode == 'keep') {
        final String rawUrl = (imageMap['url'] as String? ?? '').trim();
        if (rawUrl.isEmpty) return null;
        final rewritten =
            FileManageAPIService.rewriteServerImageUrl(rawUrl, _apiBaseUrl);
        return _ImgData(null, null, dateStr, showDate: showDate)
          ..imageUrl = rewritten;
      }
      if (mode == 'upload') {
        final String uploadKey =
            (imageMap['upload_key'] as String? ?? '').trim();
        if (uploadKey.isEmpty) return null;
        BundleUploadFile? draftFile;
        for (final BundleUploadFile file in widget.initialDraftFiles) {
          if (file.filename == uploadKey) {
            draftFile = file;
            break;
          }
        }
        if (draftFile == null) return null;

        final Uint8List rawBytes = draftFile.draftBytes ?? draftFile.bytes;
        final _ImgData data = _ImgData(
          rawBytes,
          showDate ? draftFile.bytes : null,
          dateStr,
          showDate: showDate,
        );
        return data;
      }
      return null;
    }

    final String? str = imageValue as String?;
    if (str != null && str.trim().isNotEmpty) {
      if (str.startsWith('http') || str.startsWith('/')) {
        final rewritten =
            FileManageAPIService.rewriteServerImageUrl(str.trim(), _apiBaseUrl);
        return _ImgData(null, null, dateStr, showDate: showDate)
          ..imageUrl = rewritten;
      }
      final bytes = _decodeDataUriBytes(str);
      if (bytes != null) {
        return _ImgData(bytes, showDate ? bytes : null, dateStr,
            showDate: showDate);
      }
    }
    return null;
  }

  bool _loadAuditFixPayload(Map<String, dynamic> editorPayload) {
    if ((editorPayload['type'] as String?)?.trim() != 'audit_fix') {
      return false;
    }

    final String auditDate =
        (editorPayload['audit_date'] as String?)?.trim().isNotEmpty == true
            ? (editorPayload['audit_date'] as String).trim()
            : _todayStr;
    _auditDateCtrl.text = auditDate;

    for (final _FixItem item in _items) {
      item.dispose();
    }
    _items.clear();
    _draftObservedItems.clear();
    _draftObservedImages.clear();
    _fieldMappings.clear();
    _extraFields.clear();
    _resetDeletedItemState();

    final List<dynamic> items =
        (editorPayload['items'] as List<dynamic>?) ?? const <dynamic>[];
    for (int index = 0; index < items.length; index++) {
      final dynamic rawItem = items[index];
      if (rawItem is! Map) continue;

      final Map<String, dynamic> itemPayload =
          Map<String, dynamic>.from(rawItem);
      final _FixItem item = _FixItem(sourceIndex: index);
      bool hasStageData = false;

      void assignStage(_Stage stage, String key) {
        final dynamic rawStage = itemPayload[key];
        if (rawStage is! Map) return;

        final Map<String, dynamic> stagePayload =
            Map<String, dynamic>.from(rawStage);
        final String description =
            (stagePayload['description'] as String?)?.trim() ?? '';
        switch (stage) {
          case _Stage.before:
            item.descBefore.text = description;
          case _Stage.improv:
            item.descImprov.text = description;
          case _Stage.after:
            item.descAfter.text = description;
        }

        final _ImgData? data =
            _imgDataFromEditorStage(stagePayload, defaultDate: auditDate);
        if (data != null) {
          item.setData(stage, data);
        }

        if (description.isNotEmpty || data != null) {
          hasStageData = true;
        }
      }

      assignStage(_Stage.before, 'before');
      assignStage(_Stage.improv, 'improv');
      assignStage(_Stage.after, 'after');

      if (hasStageData) {
        _attachItemDraftListeners(item);
        _items.add(item);
      } else {
        item.dispose();
      }
    }

    _usesStructuredEditorPayload = true;
    return true;
  }

  bool _loadExistingDocFromEditorPayload(Map<String, dynamic> response) {
    final String documentTypeName =
        (response['document_type_name'] as String?)?.trim() ?? '';
    final dynamic rawEditorPayload = response['editor_payload'];
    if (documentTypeName != '缺失稽核改善' || rawEditorPayload is! Map) {
      return false;
    }
    return _loadAuditFixPayload(Map<String, dynamic>.from(rawEditorPayload));
  }

  Map<String, dynamic> _buildStructuredAuditFixPayload() {
    Map<String, dynamic> buildItemPayload(_FixItem item, int groupIndex) {
      return <String, dynamic>{
        'group_index': groupIndex,
        'before': <String, dynamic>{
          'description': item.descBefore.text.trim(),
          'image': item.before == null ? '' : _getFileName(item.before!),
          if (item.before != null && _getBytes(item.before!) != null)
            '_bytes': _getBytes(item.before!)!,
        },
        'improv': <String, dynamic>{
          'description': item.descImprov.text.trim(),
          'image': item.improv == null ? '' : _getFileName(item.improv!),
          if (item.improv != null && _getBytes(item.improv!) != null)
            '_bytes': _getBytes(item.improv!)!,
        },
        'after': <String, dynamic>{
          'description': item.descAfter.text.trim(),
          'image': item.after == null ? '' : _getFileName(item.after!),
          if (item.after != null && _getBytes(item.after!) != null)
            '_bytes': _getBytes(item.after!)!,
        },
      };
    }

    final List<Map<String, dynamic>> orderedItems =
        List<Map<String, dynamic>>.generate(
      _items.length,
      (index) => buildItemPayload(_items[index], index + 1),
    );

    final List<Map<String, dynamic>> clearedItems =
        List<Map<String, dynamic>>.generate(
      _deletedStructuredItemIndexes.length,
      (index) => <String, dynamic>{
        'group_index': _items.length + index + 1,
        'before': <String, dynamic>{
          'description': '',
          'image': '',
        },
        'improv': <String, dynamic>{
          'description': '',
          'image': '',
        },
        'after': <String, dynamic>{
          'description': '',
          'image': '',
        },
      },
    );

    return <String, dynamic>{
      'type': 'audit_fix',
      'audit_date': _auditDateCtrl.text.trim(),
      'items': <Map<String, dynamic>>[
        ...orderedItems,
        ...clearedItems,
      ],
    };
  }

  void _moveItemToIndex(int fromIndex, int toIndex) {
    if (fromIndex == toIndex ||
        fromIndex < 0 ||
        fromIndex >= _items.length ||
        toIndex < 0 ||
        toIndex >= _items.length) {
      return;
    }

    setState(() {
      final _FixItem movedItem = _items.removeAt(fromIndex);
      _items.insert(toIndex, movedItem);
    });
    _scheduleDraftAutosave();
  }

  void _moveItemUp(int index) => _moveItemToIndex(index, index - 1);

  void _moveItemDown(int index) => _moveItemToIndex(index, index + 1);

  _Stage? _previousStage(_Stage stage) => switch (stage) {
        _Stage.before => null,
        _Stage.improv => _Stage.before,
        _Stage.after => _Stage.improv,
      };

  _Stage? _nextStage(_Stage stage) => switch (stage) {
        _Stage.before => _Stage.improv,
        _Stage.improv => _Stage.after,
        _Stage.after => null,
      };

  void _swapStageContent(_FixItem item, _Stage first, _Stage second) {
    if (first == second) return;
    setState(() => item.swapStages(first, second));
    _attachItemDraftListeners(item);
    _scheduleDraftAutosave();
  }

  String? _extractAuditRecordText(String value, int groupNumber) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(
      '(?:^|[\\r\\n]|說明[:：]\\s*)\\s*$groupNumber\\s*[.．、)]\\s*(.*)\$',
      dotAll: true,
    ).firstMatch(trimmed);
    if (match == null) return null;
    return match.group(1)?.trim() ?? '';
  }

  String _formatAuditRecordText(String value, int groupNumber) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final withoutPrefix = trimmed
        .replaceFirst(RegExp(r'^\s*\d+\s*[.．、)]\s*', dotAll: true), '')
        .trim();
    return '$groupNumber. $withoutPrefix';
  }

  void _assignLoadedStageDescription({
    required _FixItem item,
    required _AuditFieldMapping mapping,
    required _Stage stage,
    required int fieldId,
    required String text,
  }) {
    switch (stage) {
      case _Stage.before:
        mapping.descBeforeFieldId ??= fieldId;
        if (item.descBefore.text.trim().isEmpty) {
          item.descBefore.text = text;
        }
      case _Stage.improv:
        mapping.descImprovFieldId ??= fieldId;
        if (item.descImprov.text.trim().isEmpty) {
          item.descImprov.text = text;
        }
      case _Stage.after:
        mapping.descAfterFieldId ??= fieldId;
        if (item.descAfter.text.trim().isEmpty) {
          item.descAfter.text = text;
        }
    }
  }

  /*──────────────── 載入既有文件（編輯模式） ────────────────*/
  Future<void> _loadExistingDoc() async {
    try {
      final docFieldsResp = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getDocumentFields(
          token: token,
          fileId: widget.fileId!,
        ),
      );

      _resetDeletedItemState();
      _usesStructuredEditorPayload = false;
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
      _draftObservedItems.clear();
      _draftObservedImages.clear();
      _fieldMappings.clear();
      _extraFields.clear();
      _apiBaseUrl = await FileManageAPIService.baseUrl;

      if (_loadExistingDocFromEditorPayload(docFieldsResp)) {
        if (!mounted) return;
        setState(() => _siteLoading = false);
        _attachDraftListenersForAllItems();
        unawaited(_maybeRestoreLocalDraft());
        return;
      }

      final fields = (docFieldsResp['fields'] as List<dynamic>?) ?? [];

      // 表格欄位按 seg:table:row 複合鍵分組（不同 segment 的 row_index 可相同）
      final tableFields = fields.where((f) => f['is_table'] == true).toList();
      final byRow = <String, List<dynamic>>{};
      for (final f in tableFields) {
        final seg = (f['seg_index'] as num?)?.toInt() ?? 0;
        final tid = (f['table_index'] as num?)?.toInt() ?? 0;
        final rid = (f['row_index'] as num?)?.toInt() ?? 0;
        final key = '$seg:$tid:$rid';
        byRow.putIfAbsent(key, () => []).add(f);
      }
      final sortedKeys = byRow.keys.toList()..sort();

      // 跳過表頭列（第一列無 base64 圖片即為表頭）
      String? headerKey;
      if (sortedKeys.isNotEmpty) {
        final firstRow = byRow[sortedKeys.first]!;
        final hasImage = firstRow.any((f) {
          final uri = f['image_data_uri'] as String?;
          final t = (f['original_text'] as String?) ?? '';
          return (uri != null && uri.isNotEmpty) ||
              t.startsWith('data:image/') ||
              t.startsWith('http') ||
              t.startsWith('/');
        });
        if (!hasImage) headerKey = sortedKeys.first;
      }

      // 每 3 張圖片一組 → 一個 _FixItem
      _FixItem? current;
      _AuditFieldMapping? currentMapping;
      int imgCount = 0;

      for (final key in sortedKeys) {
        if (key == headerKey) {
          for (final f in byRow[key]!) {
            _extraFields[f['field_id'] as int] =
                (f['original_text'] as String?) ?? '';
          }
          continue;
        }

        final rowFields = byRow[key]!
          ..sort((a, b) => ((a['col_index'] as int?) ?? 0)
              .compareTo((b['col_index'] as int?) ?? 0));

        final bool rowHasImage = rowFields.any((f) {
          final uri = f['image_data_uri'] as String?;
          final t = (f['original_text'] as String?) ?? '';
          return (uri != null && uri.isNotEmpty) ||
              t.startsWith('data:image/') ||
              t.startsWith('http') ||
              t.startsWith('/');
        });

        if (rowHasImage &&
            (current == null || imgCount >= _Stage.values.length)) {
          if (current != null && currentMapping != null) {
            _attachItemDraftListeners(current);
            _items.add(current);
            _fieldMappings.add(currentMapping);
          }
          current = _FixItem();
          currentMapping = _AuditFieldMapping();
          imgCount = 0;
        }

        final _Stage? rowStage = current == null || currentMapping == null
            ? null
            : rowHasImage
                ? _Stage.values[imgCount]
                : imgCount > 0
                    ? _Stage.values[imgCount - 1]
                    : null;

        final int currentGroupNumber =
            current == null ? _items.length : _items.length + 1;

        for (final f in rowFields) {
          final fid = f['field_id'] as int;
          final raw = (f['original_text'] as String?) ?? '';
          final desc = (f['description'] as String? ?? '').toLowerCase();

          final uri = (f['image_data_uri'] as String?)?.trim();
          if (uri != null &&
              uri.isNotEmpty &&
              current != null &&
              currentMapping != null &&
              rowStage != null) {
            final data = _ImgData(null, null, _todayStr, showDate: false);
            final imageUrl =
                FileManageAPIService.rewriteServerImageUrl(uri, _apiBaseUrl);
            data.imageUrl = imageUrl;
            current.setData(rowStage, data);
            switch (rowStage) {
              case _Stage.before:
                currentMapping.imageBeforeFieldId = fid;
              case _Stage.improv:
                currentMapping.imageImprovFieldId = fid;
              case _Stage.after:
                currentMapping.imageAfterFieldId = fid;
            }
            continue;
          }
          if (raw.startsWith('data:image/')) {
            Uint8List? imgBytes;
            try {
              imgBytes = base64Decode(raw.split(',').last);
            } catch (_) {}

            if (imgBytes != null &&
                current != null &&
                currentMapping != null &&
                rowStage != null) {
              final data =
                  _ImgData(imgBytes, imgBytes, _todayStr, showDate: false);
              current.setData(rowStage, data);

              // 記錄 field_id
              switch (rowStage) {
                case _Stage.before:
                  currentMapping.imageBeforeFieldId = fid;
                case _Stage.improv:
                  currentMapping.imageImprovFieldId = fid;
                case _Stage.after:
                  currentMapping.imageAfterFieldId = fid;
              }
            }
            continue;
          }

          final String? extractedText = rowStage == null
              ? null
              : _extractAuditRecordText(raw, currentGroupNumber);

          if (extractedText != null &&
              current != null &&
              currentMapping != null &&
              rowStage != null) {
            _assignLoadedStageDescription(
              item: current,
              mapping: currentMapping,
              stage: rowStage,
              fieldId: fid,
              text: extractedText,
            );
            continue;
          }

          if (desc.contains('前') ||
              desc.contains('before') ||
              desc.contains('缺失')) {
            final String normalized = raw.trim();
            if (current != null &&
                currentMapping != null &&
                normalized.isNotEmpty &&
                !normalized.contains('說明')) {
              _assignLoadedStageDescription(
                item: current,
                mapping: currentMapping,
                stage: _Stage.before,
                fieldId: fid,
                text: normalized,
              );
              continue;
            }
          } else if (desc.contains('中') ||
              desc.contains('改善') ||
              desc.contains('improv')) {
            final String normalized = raw.trim();
            if (current != null &&
                currentMapping != null &&
                normalized.isNotEmpty &&
                !normalized.contains('說明')) {
              _assignLoadedStageDescription(
                item: current,
                mapping: currentMapping,
                stage: _Stage.improv,
                fieldId: fid,
                text: normalized,
              );
              continue;
            }
          } else if (desc.contains('後') || desc.contains('after')) {
            final String normalized = raw.trim();
            if (current != null &&
                currentMapping != null &&
                normalized.isNotEmpty &&
                !normalized.contains('說明')) {
              _assignLoadedStageDescription(
                item: current,
                mapping: currentMapping,
                stage: _Stage.after,
                fieldId: fid,
                text: normalized,
              );
              continue;
            }
          }

          _extraFields[fid] = raw;
        }

        if (rowHasImage && rowStage != null) {
          imgCount = rowStage.index + 1;
        }
      }

      // 將最後一組加入
      if (current != null && currentMapping != null) {
        _attachItemDraftListeners(current);
        _items.add(current);
        _fieldMappings.add(currentMapping);
      }

      // 段落欄位保留
      for (final f in fields.where((x) => x['is_table'] != true)) {
        _extraFields[f['field_id'] as int] =
            (f['original_text'] as String?) ?? '';
      }

      if (!mounted) return;
      setState(() => _siteLoading = false);
      _attachDraftListenersForAllItems();
      unawaited(_maybeRestoreLocalDraft());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _siteErr = '載入文件失敗：$e';
        _siteLoading = false;
      });
    }
  }

  /*───────────────── 日期浮水印 ────────────────*/
  Future<Uint8List> _stampDate(Uint8List rawBytes, String dateText) async {
    return await UnifiedImageService.stampDate(rawBytes, dateText);
  }

  Future<void> _ensureStampedBytes(_ImgData data) async {
    if (data.rawBytes == null) return;
    final String dateText = data.dateCtrl.text.trim();
    if (data.stampedBytes != null && data.stampedDateText == dateText) {
      return;
    }
    data.stampedBytes = await _stampDate(data.rawBytes!, dateText);
    data.stampedDateText = dateText;
  }

  Object _stampCacheKey(_ImgData data) {
    return Object.hash(
      identityHashCode(data.rawBytes),
      data.dateCtrl.text.trim(),
      data.showDate,
    );
  }

  /*────────────────── 新增圖片 (多張) ───────────────────*/
  Future<void> _openCamera() async {
    final shots = await UnifiedImageService.openCameraOrPickMulti(
        context, const CameraCapturePage());
    if (!mounted || shots.isEmpty) return;
    _setBusy(true);
    try {
      final List<_ImgData> nextImages = <_ImgData>[];
      for (final x in shots) {
        final raw = await x.readAsBytes();
        nextImages.add(_buildImageData(raw));
      }
      _addImages(nextImages);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _pickMulti() async {
    final xs = await UnifiedImageService.pickMultiImage(imageQuality: 85);
    if (xs.isEmpty) return;
    _setBusy(true);
    try {
      final List<_ImgData> nextImages = <_ImgData>[];
      for (final x in xs) {
        final raw = await x.readAsBytes();
        nextImages.add(_buildImageData(raw));
      }
      _addImages(nextImages);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _chooseAndReplaceImage(_FixItem it, _Stage stage) async {
    final x = await UnifiedImageService.pickSingleWithDialog(context);
    if (x == null) return;
    final raw = await x.readAsBytes();
    final oldShow = it.dataOf(stage)?.showDate ?? true;
    final defaultDate = it.dataOf(stage)?.dateCtrl.text ?? _todayStr;
    if (!mounted) return;
    final newData = _ImgData(raw, null, defaultDate, showDate: oldShow);
    setState(() => it.setData(stage, newData));
    _attachImageDraftListener(newData);
    _scheduleDraftAutosave();
  }

  _ImgData _buildImageData(Uint8List rawBytes) {
    return _ImgData(rawBytes, null, _todayStr);
  }

  void _addImages(List<_ImgData> images) {
    if (images.isEmpty) return;
    if (!mounted) return;
    setState(() {
      for (final data in images) {
        if (_items.isEmpty || _items.last.isComplete) {
          final item = _FixItem();
          _attachItemDraftListeners(item);
          _items.add(item);
        }
        _items.last.addImage(data);
        _attachImageDraftListener(data);
      }
    });
    _scheduleDraftAutosave();
  }

  /*────────────────── 批量複製說明 + 日期/checkbox ────────────────*/
  Future<void> _copyDescToBelow(int idx) async {
    if (idx < 0 || idx >= _items.length - 1) return;
    final src = _items[idx];

    final bDesc = src.descBefore.text.trim();
    final mDesc = src.descImprov.text.trim();
    final aDesc = src.descAfter.text.trim();

    // 已無任何可複製內容
    bool hasText = bDesc.isNotEmpty || mDesc.isNotEmpty || aDesc.isNotEmpty;
    bool hasImgDate = _Stage.values.any((s) {
      final d = src.dataOf(s);
      return d != null &&
          (d.dateCtrl.text.trim().isNotEmpty || d.showDate == false);
    });
    if (!hasText && !hasImgDate) return;

    _setBusy(true);
    try {
      for (int i = idx + 1; i < _items.length; i++) {
        final dst = _items[i];
        /*── 複製說明文字 ───────────────*/
        if (bDesc.isNotEmpty) dst.descBefore.text = bDesc;
        if (mDesc.isNotEmpty) dst.descImprov.text = mDesc;
        if (aDesc.isNotEmpty) dst.descAfter.text = aDesc;

        /*── 複製顯示日期 + 日期文字 ───────*/
        for (final st in _Stage.values) {
          final srcData = src.dataOf(st);
          final dstData = dst.dataOf(st);
          if (srcData == null || dstData == null) continue;

          final String nextDate = srcData.dateCtrl.text;
          final bool shouldInvalidateStamp =
              dstData.showDate != srcData.showDate ||
                  dstData.dateCtrl.text.trim() != nextDate.trim();
          dstData.dateCtrl.text = nextDate; // 日期文字
          dstData.showDate = srcData.showDate; // checkbox

          if (shouldInvalidateStamp) {
            dstData.stampedBytes = null;
            dstData.stampedDateText = null;
          }
        }
      }
      if (mounted) setState(() {});
      _scheduleDraftAutosave();
    } finally {
      _setBusy(false);
    }
  }

  /*────────────────── 送出 ───────────────────*/
  Future<void> _submit() async {
    if (_isDraftMode || _isEditMode) {
      if (_items.isEmpty && !_hasPendingItemDeletes) return;
    } else {
      if (!_formKey.currentState!.validate() || _items.isEmpty) return;
    }

    if (!_isDraftMode) {
      for (final it in _items) {
        for (final s in _Stage.values) {
          final d = it.dataOf(s);
          if (d != null && d.rawBytes != null && d.showDate) {
            await _ensureStampedBytes(d);
          }
        }
      }
    }

    _setBusy(true);
    try {
      if (_isDraftMode) {
        await _submitDraft();
      } else if (_isEditMode) {
        await _submitEdit();
      } else {
        await _submitCreate();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                AppLocalizations.of(context)!.createFailedWith(e.toString()))));
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _submitDraft() async {
    final List<BundleUploadFile> files = <BundleUploadFile>[];
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    int uploadCounter = 0;

    Future<Map<String, dynamic>> buildStagePayload(
      _ImgData? data,
      TextEditingController descriptionController,
      String stageName,
    ) async {
      if (data != null && data.rawBytes != null && data.showDate) {
        await _ensureStampedBytes(data);
      }

      Map<String, dynamic> imageContract = const <String, dynamic>{
        'mode': 'delete',
      };
      if (data != null) {
        if (data.imageUrl != null) {
          imageContract = <String, dynamic>{
            'mode': 'keep',
            'url': data.imageUrl,
          };
        } else {
          final Uint8List uploadBytes = _getBytes(data)!;
          final Uint8List rawBytes = data.rawBytes!;
          final String uploadKey =
              'audit-$stageName-$timestamp-$uploadCounter.png';
          uploadCounter += 1;
          files.add(
            BundleUploadFile(
              filename: uploadKey,
              bytes: uploadBytes,
              draftBytes: rawBytes,
            ),
          );
          imageContract = <String, dynamic>{
            'mode': 'upload',
            'upload_key': uploadKey,
          };
        }
      }

      return <String, dynamic>{
        'description': descriptionController.text.trim(),
        'date': data?.dateCtrl.text.trim() ?? '',
        'image': imageContract,
        '_ui': <String, dynamic>{
          'show_date': data?.showDate ?? false,
        },
      };
    }

    for (int index = 0; index < _items.length; index++) {
      final _FixItem item = _items[index];
      items.add(<String, dynamic>{
        'group_index': index + 1,
        'before':
            await buildStagePayload(item.before, item.descBefore, 'before'),
        'improv':
            await buildStagePayload(item.improv, item.descImprov, 'improv'),
        'after': await buildStagePayload(item.after, item.descAfter, 'after'),
      });
    }

    for (int index = 0; index < _deletedStructuredItemIndexes.length; index++) {
      items.add(<String, dynamic>{
        'group_index': _items.length + index + 1,
        'before': const <String, dynamic>{
          'description': '',
          'date': '',
          'image': <String, dynamic>{'mode': 'delete'},
          '_ui': <String, dynamic>{'show_date': false},
        },
        'improv': const <String, dynamic>{
          'description': '',
          'date': '',
          'image': <String, dynamic>{'mode': 'delete'},
          '_ui': <String, dynamic>{'show_date': false},
        },
        'after': const <String, dynamic>{
          'description': '',
          'date': '',
          'image': <String, dynamic>{'mode': 'delete'},
          '_ui': <String, dynamic>{'show_date': false},
        },
      });
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      BundleChildDraftResult(
        documentTypeName: '缺失稽核改善',
        payload: <String, dynamic>{
          'type': 'audit_fix',
          'audit_date': _auditDateCtrl.text.trim(),
          'items': items,
        },
        files: files,
      ),
    );
  }

  Future<void> _submitCreate() async {
    final payloadItems = _items
        .map((it) => {
              'desc_before_impr': it.descBefore.text.trim(),
              'improv_desc': it.descImprov.text.trim(),
              'impr_desc': it.descAfter.text.trim(),
              'image_before': it.before == null ? '' : _getFileName(it.before!),
              if (it.before != null && _getBytes(it.before!) != null)
                '_bytes_before': _getBytes(it.before!)!,
              'image_improv': it.improv == null ? '' : _getFileName(it.improv!),
              if (it.improv != null && _getBytes(it.improv!) != null)
                '_bytes_improv': _getBytes(it.improv!)!,
              'image_after': it.after == null ? '' : _getFileName(it.after!),
              if (it.after != null && _getBytes(it.after!) != null)
                '_bytes_after': _getBytes(it.after!)!,
            })
        .toList();

    if (!mounted) return;
    await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.createAuditFixDoc(
        token: token,
        siteId: _selectedSiteId!,
        auditDate: _auditDateCtrl.text.trim(),
        items: payloadItems,
      ),
    );

    if (!mounted) return;
    if (!_isDraftMode) {
      await _draftAutosaver.delete();
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  int? _extractLatestVersionId(Map<String, dynamic> detail) {
    final dynamic latestVersionId = detail['latest_version_id'];
    if (latestVersionId is num) return latestVersionId.toInt();

    final dynamic versionId = detail['version_id'];
    if (versionId is num) return versionId.toInt();

    final dynamic latestVersion = detail['latest_version'];
    if (latestVersion is Map && latestVersion['id'] is num) {
      return (latestVersion['id'] as num).toInt();
    }

    return null;
  }

  Future<void> _goToLatestPreview() async {
    final GoRouter router = GoRouter.of(context);
    final fileDetail = await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.getFileById(
        token: token,
        fileId: widget.fileId!,
      ),
    );

    if (!mounted) return;
    final int? latestVersionId = _extractLatestVersionId(fileDetail);
    final String? docRef = documentRouteRefFromMap(fileDetail);
    if (docRef == null || docRef.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件缺少公開代碼，無法開啟連結')),
      );
      router.go(fileListLocation());
      return;
    }

    if (latestVersionId != null) {
      router.go(
        filePreviewLocation(
          docRef: docRef,
          versionId: latestVersionId,
        ),
      );
      return;
    }

    router.go(filePreviewLocation(docRef: docRef));
  }

  Future<void> _submitEdit() async {
    if (_usesStructuredEditorPayload) {
      await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.fillDocumentStructured(
          token: token,
          fileId: widget.fileId!,
          payload: _buildStructuredAuditFixPayload(),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.saveSuccess)),
      );
      if (!_isDraftMode) {
        await _draftAutosaver.delete();
      }
      await _goToLatestPreview();
      return;
    }

    final fillData = <Map<String, dynamic>>[];

    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      final mapping = i < _fieldMappings.length ? _fieldMappings[i] : null;
      if (mapping == null) continue;

      // 圖片
      if (mapping.imageBeforeFieldId != null) {
        final bBytes = it.before == null ? null : _getBytes(it.before!);
        fillData.add({
          'field_id': '${mapping.imageBeforeFieldId}',
          'new_text': it.before == null ? '' : _getFileName(it.before!),
          if (bBytes != null) '_bytes': bBytes,
        });
      }
      if (mapping.imageImprovFieldId != null) {
        final iBytes = it.improv == null ? null : _getBytes(it.improv!);
        fillData.add({
          'field_id': '${mapping.imageImprovFieldId}',
          'new_text': it.improv == null ? '' : _getFileName(it.improv!),
          if (iBytes != null) '_bytes': iBytes,
        });
      }
      if (mapping.imageAfterFieldId != null) {
        final aBytes = it.after == null ? null : _getBytes(it.after!);
        fillData.add({
          'field_id': '${mapping.imageAfterFieldId}',
          'new_text': it.after == null ? '' : _getFileName(it.after!),
          if (aBytes != null) '_bytes': aBytes,
        });
      }

      // 說明
      if (mapping.descBeforeFieldId != null) {
        fillData.add({
          'field_id': '${mapping.descBeforeFieldId}',
          'new_text': _formatAuditRecordText(it.descBefore.text, i + 1),
        });
      }
      if (mapping.descImprovFieldId != null) {
        fillData.add({
          'field_id': '${mapping.descImprovFieldId}',
          'new_text': _formatAuditRecordText(it.descImprov.text, i + 1),
        });
      }
      if (mapping.descAfterFieldId != null) {
        fillData.add({
          'field_id': '${mapping.descAfterFieldId}',
          'new_text': _formatAuditRecordText(it.descAfter.text, i + 1),
        });
      }
    }

    for (final mapping in _deletedFieldMappings) {
      _appendClearedAuditFields(fillData, mapping);
    }

    // 回寫 extra fields
    _extraFields.forEach((fid, text) {
      fillData.add({'field_id': '$fid', 'new_text': text});
    });

    if (!mounted) return;
    if (fillData.isNotEmpty) {
      await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.fillDocumentFields(
          token: token,
          fileId: widget.fileId!,
          fillData: fillData,
        ),
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.saveSuccess)),
    );
    if (!_isDraftMode) {
      await _draftAutosaver.delete();
    }
    await _goToLatestPreview();
  }

  String _getFileName(_ImgData d) => d.imageUrl ?? 'img_${d.hashCode}.png';

  Uint8List? _getBytes(_ImgData d) =>
      d.imageUrl != null ? null : (d.showDate ? d.stampedBytes : d.rawBytes);

  /*────────────────── UI ───────────────────*/
  @override
  Widget build(BuildContext context) {
    final body = _siteLoading
        ? const Center(child: CircularProgressIndicator())
        : _siteErr != null
            ? Center(child: Text(_siteErr!))
            : _buildForm();

    return ResponsiveScaffold(
      title: _isEditMode
          ? AppLocalizations.of(context)!.editAuditFixDocTitle
          : AppLocalizations.of(context)!.addAuditFixDocTitle,
      isFullscreen: true,
      onBackPressed: () {
        if (_isDraftMode) {
          Navigator.of(context).maybePop();
          return;
        }
        unawaited(_draftAutosaver.flush());
        if (_isEditMode) {
          _goToLatestPreview();
          return;
        }
        // Create mode: opened via Navigator.push — use imperative Navigator
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(false);
        } else {
          context.go(fileListLocation());
        }
      },
      body: BusyOverlay(
        busy: _busy,
        child: body,
      ),
    );
  }

  Widget _buildForm() => Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final AppLocalizations l = AppLocalizations.of(context)!;
            final ThemeData theme = Theme.of(context);
            final bool compactToolbar = constraints.maxWidth < 760;
            final List<Widget> toolbarButtons = <Widget>[
              ElevatedButton.icon(
                onPressed: _openCamera,
                icon: const Icon(Icons.camera_alt),
                label: Text(l.takePhoto),
              ),
              ElevatedButton.icon(
                onPressed: _pickMulti,
                icon: const Icon(Icons.collections),
                label: Text(l.multiSelectAlbum),
              ),
            ];

            return Column(
              children: [
                if (!_isEditMode && !_isDraftMode)
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        LabeledTextField(
                          controller: _auditDateCtrl,
                          label: l.auditDateLabel,
                          validator: (v) =>
                              v == null || v.isEmpty ? l.requiredField : null,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (compactToolbar) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: toolbarButtons,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      l.todayLabel(_todayStr),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      ...toolbarButtons.expand(
                          (widget) => [widget, const SizedBox(width: 8)]),
                      const Spacer(),
                      Text(l.todayLabel(_todayStr)),
                    ]..removeLast(),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 48,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l.addPhotoViaCamera,
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _itemCard(i),
                        ),
                ),
                ElevatedButton.icon(
                  onPressed: _submit,
                  icon: Icon((_isEditMode || _isDraftMode)
                      ? Icons.save
                      : Icons.upload),
                  label: Text(
                      (_isEditMode || _isDraftMode) ? l.save : l.createDocx),
                ),
              ],
            );
          },
        ),
      );

  int _panelColumnsForWidth(double maxWidth) {
    if (maxWidth >= 920) return 3;
    if (maxWidth >= 640) return 2;
    return 1;
  }

  double _panelWidthForIndex({
    required double maxWidth,
    required int columns,
    required int index,
    required int total,
    double spacing = 12,
  }) {
    if (columns <= 1) return maxWidth;
    final double baseWidth = (maxWidth - spacing * (columns - 1)) / columns;
    if (columns == 2 && total.isOdd && index == total - 1) {
      return maxWidth;
    }
    return baseWidth;
  }

  double _imageHeightForWidth(double width) =>
      (width * 0.62).clamp(180.0, 300.0).toDouble();

  Widget _stagePanel(
    BuildContext context, {
    required _FixItem item,
    required _Stage stage,
    required String title,
    required TextEditingController descController,
    required List<Widget> descActions,
    required double width,
    required double imageHeight,
    required bool useVerticalMoveControls,
    required VoidCallback? onMoveBackward,
    required VoidCallback? onMoveForward,
    required VoidCallback onRestamp,
  }) {
    final AppLocalizations l = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final _ImgData? data = item.dataOf(stage);
    final bool canStamp = data?.rawBytes != null;
    const double panelPadding = 12;
    final double imageWidth = width - panelPadding * 2;

    return Container(
      width: width,
      padding: const EdgeInsets.all(panelPadding),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  useVerticalMoveControls
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_left,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: onMoveBackward,
              ),
              IconButton(
                icon: Icon(
                  useVerticalMoveControls
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: onMoveForward,
              ),
              if (data != null)
                IconButton(
                  tooltip: l.delete,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() => item.clearData(stage));
                    _scheduleDraftAutosave();
                  },
                ),
            ],
          ),
          if (data != null)
            Row(
              children: [
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  value: data.showDate,
                  onChanged: canStamp
                      ? (v) {
                          final bool nextValue = v ?? true;
                          setState(() => data.showDate = nextValue);
                          _scheduleDraftAutosave();
                          if (nextValue) {
                            onRestamp();
                          }
                        }
                      : null,
                ),
                Expanded(
                  child: Text(
                    l.showDateLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: canStamp ? cs.onSurfaceVariant : cs.outline,
                    ),
                  ),
                ),
              ],
            )
          else
            const SizedBox(height: 8),
          if (data == null)
            Tooltip(
              message: l.takePhoto,
              child: InkWell(
                onTap: () => _chooseAndReplaceImage(item, stage),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: imageWidth,
                  height: imageHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                    color: cs.surface,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.add_a_photo_outlined,
                      size: 32,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            )
          else
            ImageBox(
              rawBytes: data.rawBytes,
              stampedBytes: data.stampedBytes,
              imageUrl: data.imageUrl,
              showDate: data.showDate,
              stampedBytesBuilder: data.rawBytes == null
                  ? null
                  : () async {
                      await _ensureStampedBytes(data);
                      return data.stampedBytes!;
                    },
              stampCacheKey: _stampCacheKey(data),
              showCheckbox: false,
              onDelete: null,
              onTap: () => _chooseAndReplaceImage(item, stage),
              tag: null,
              width: imageWidth,
              height: imageHeight,
            ),
          if (data != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: imageWidth,
              child: LabeledTextField(
                controller: data.dateCtrl,
                label: l.dateLabel,
                dense: true,
                onChanged: (_) {
                  _scheduleDraftAutosave();
                  if (data.rawBytes != null) {
                    onRestamp();
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 12),
          SizedBox(
            width: imageWidth,
            child: LabeledTextField(
              controller: descController,
              label: l.descriptionLabel,
              maxLines: 2,
              trailingIcons: descActions,
            ),
          ),
        ],
      ),
    );
  }

  /*────────────────── 卡片 (單組) ────────────────*/
  Widget _itemCard(int idx) {
    final it = _items[idx];
    final no = '${idx + 1}'.padLeft(3, '0');
    final AppLocalizations l = AppLocalizations.of(context)!;

    /*── Local cut / copy / paste helpers ─*/
    void cut(TextEditingController c) {
      UnifiedImageService.cutText(c);
    }

    void copy(TextEditingController c) {
      UnifiedImageService.copyTextFromController(c);
    }

    Future<void> paste(TextEditingController c) async {
      await UnifiedImageService.pasteText(c);
    }

    Future<void> restamp(_Stage s) async {
      final data = it.dataOf(s);
      if (data == null || data.rawBytes == null) return;
      await _ensureStampedBytes(data);
      if (mounted) setState(() {});
    }

    List<Widget> descActions(TextEditingController ctrl) => <Widget>[
          IconButton(icon: const Icon(Icons.cut), onPressed: () => cut(ctrl)),
          IconButton(icon: const Icon(Icons.copy), onPressed: () => copy(ctrl)),
          IconButton(
            icon: const Icon(Icons.paste),
            onPressed: () => paste(ctrl),
          ),
        ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double spacing = 12;
            final int columns = _panelColumnsForWidth(constraints.maxWidth);
            final bool useVerticalStageMoves = columns == 1;
            final List<_Stage> stages = <_Stage>[
              _Stage.before,
              _Stage.improv,
              _Stage.after,
            ];
            final List<String> stageLabels = <String>[
              l.descBeforeLabel,
              l.descDuringLabel,
              l.descAfterLabel,
            ];
            final List<TextEditingController> descControllers =
                <TextEditingController>[
              it.descBefore,
              it.descImprov,
              it.descAfter,
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l.groupNumberLabel(no.toString()),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      tooltip: l.applyDescriptionToAllGroups,
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () => _copyDescToBelow(idx),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: WidgetsLocalizations.of(context).reorderItemUp,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: idx == 0 ? null : () => _moveItemUp(idx),
                    ),
                    IconButton(
                      tooltip: WidgetsLocalizations.of(context).reorderItemDown,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: idx == _items.length - 1
                          ? null
                          : () => _moveItemDown(idx),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeItemAt(idx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: List<Widget>.generate(stages.length, (index) {
                    final _Stage stage = stages[index];
                    final _Stage? previousStage = _previousStage(stage);
                    final _Stage? nextStage = _nextStage(stage);
                    final double panelWidth = _panelWidthForIndex(
                      maxWidth: constraints.maxWidth,
                      columns: columns,
                      index: index,
                      total: stages.length,
                      spacing: spacing,
                    );
                    return _stagePanel(
                      context,
                      item: it,
                      stage: stage,
                      title: stageLabels[index],
                      descController: descControllers[index],
                      descActions: descActions(descControllers[index]),
                      width: panelWidth,
                      imageHeight: _imageHeightForWidth(panelWidth - 24),
                      useVerticalMoveControls: useVerticalStageMoves,
                      onMoveBackward: previousStage == null
                          ? null
                          : () => _swapStageContent(it, stage, previousStage),
                      onMoveForward: nextStage == null
                          ? null
                          : () => _swapStageContent(it, stage, nextStage),
                      onRestamp: () => restamp(stage),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
