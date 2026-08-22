import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/document_draft.dart';
import '../../services/file_manage_api_service.dart';
import '../../models/img_meta.dart';
import '../../providers/unified_auth_provider.dart';
import '../../services/document_draft_attachment_store.dart';
import '../../services/document_draft_remote_store.dart';
import '../../services/document_draft_service.dart';
import '../../services/unified_image_service.dart';
import '../../widgets/responsive_scaffold.dart';
import 'camera_capture_page.dart';
import '../../widgets/busy_overlay.dart';
import '../../widgets/image_box.dart';
import '../../widgets/labeled_text_field.dart';
import '../../utils/auth_utils.dart';
import '../../utils/file_routes.dart';

/*───────────────────────────────────────────*/
/*  PhotoDocCreatePage                       */
/*───────────────────────────────────────────*/
class PhotoDocCreatePage extends StatefulWidget {
  const PhotoDocCreatePage({
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
  State<PhotoDocCreatePage> createState() => _PhotoDocCreatePageState();
}

/// Maps an [ImgMeta] back to the document field IDs for edit-mode saving.
class _PhotoFieldMapping {
  int? imageFieldId;
  int? dateFieldId;
  int? locationFieldId;
  int? descriptionFieldId;
  int? numberFieldId;
}

class _PhotoDocCreatePageState extends State<PhotoDocCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _projectNameCtrl = TextEditingController();

  bool get _isEditMode => widget.fileId != null;
  bool get _isDraftMode => widget.draftMode;

  int? get _selectedSiteId => (_selectedSite?['id'] as num?)?.toInt();

  /*── 站點清單 ───────────────────────────*/
  List<dynamic> _sites = [];
  dynamic _selectedSite;
  bool _siteLoading = true;
  String? _siteErr;

  /*── 圖片清單 ───────────────────────────*/
  final List<ImgMeta> _images = [];
  late final String _todayStr;
  late final DocumentDraftRemoteStore _draftRemoteStore;
  late final DocumentDraftAutosaver _draftAutosaver;
  int? _draftUserId;
  late final String _clientDraftId;
  bool _draftRestoreChecked = false;
  bool _suppressDraftAutosave = false;
  final Set<ImgMeta> _draftObservedImages = <ImgMeta>{};

  /*── 編輯模式的欄位映射 ──────────────────*/
  final List<_PhotoFieldMapping> _fieldMappings = [];
  final List<_PhotoFieldMapping> _deletedFieldMappings = [];
  final Set<int> _deletedStructuredItemIndexes = <int>{};

  /// 不在圖片列裡但也需要回寫的欄位 (field_id → original_text)
  final Map<int, String> _extraFields = {};

  bool _usesStructuredEditorPayload = false;
  String _apiBaseUrl = '';

  /*── Busy overlay ──────────────────────*/
  bool _busy = false;
  void _setBusy(bool v) {
    if (!mounted) return;
    setState(() => _busy = v);
  }

  @override
  void initState() {
    super.initState();
    _todayStr = DateFormat('yyyy/MM/dd').format(DateTime.now());
    final auth = context.read<UnifiedAuthProvider>();
    _draftUserId = auth.userId;
    _clientDraftId = DocumentDraftService.createClientDraftId();
    _draftRemoteStore = DocumentDraftRemoteStore(
      auth: auth,
      enabled: !_isDraftMode,
    );
    _draftAutosaver = DocumentDraftAutosaver(
      type: 'photo_doc',
      keyProvider: _draftKey,
      payloadProvider: _buildLocalDraftPayload,
      remoteLoader: _draftRemoteStore.load,
      remoteSaver: _draftRemoteStore.save,
      remoteDeleter: _draftRemoteStore.delete,
    );
    _projectNameCtrl.addListener(_scheduleDraftAutosave);
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
    _projectNameCtrl.dispose();
    for (final i in _images) {
      i.locCtrl.dispose();
      i.descCtrl.dispose();
      i.dateCtrl.dispose();
    }
    super.dispose();
  }

  int? get _initSiteId => (widget.initSite?['id'] as num?)?.toInt();

  String _draftKey() {
    if (!_isEditMode) {
      return DocumentDraftService.buildCreateKey(
        draftType: 'photo_doc',
        clientDraftId: _clientDraftId,
      );
    }
    return DocumentDraftService.buildKey(
      draftType: 'photo_doc',
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

  void _attachDraftListeners(ImgMeta image) {
    if (!_draftObservedImages.add(image)) return;
    image.locCtrl.addListener(_scheduleDraftAutosave);
    image.descCtrl.addListener(_scheduleDraftAutosave);
    image.dateCtrl.addListener(_scheduleDraftAutosave);
  }

  void _attachDraftListenersForAllImages() {
    for (final image in _images) {
      _attachDraftListeners(image);
    }
  }

  Future<Map<String, dynamic>?> _buildLocalDraftPayload() async {
    if (_isDraftMode) return null;
    final String draftKey = _draftKey();
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    for (int index = 0; index < _images.length; index++) {
      final ImgMeta img = _images[index];
      String source = 'unavailable';
      String? attachmentRef;
      String? imageUrl;

      if (img.isNetworkImage) {
        source = 'network';
        imageUrl = img.name;
      } else if (img.rawBytes != null) {
        attachmentRef = await DocumentDraftAttachmentStore.saveBytes(
          draftKey: draftKey,
          attachmentId: 'image_$index${_normalizeUploadExtension(img.name)}',
          bytes: img.rawBytes!,
        );
        if (attachmentRef != null) {
          source = 'attachment';
        }
      }

      items.add(<String, dynamic>{
        'name': img.name,
        'source': source,
        if (attachmentRef != null) 'attachment_ref': attachmentRef,
        if (imageUrl != null) 'url': imageUrl,
        'location': img.locCtrl.text,
        'description': img.descCtrl.text,
        'date': img.dateCtrl.text,
        'show_date': img.showDate,
        'use_today_date': img.useTodayDate,
      });
    }

    if (_projectNameCtrl.text.trim().isEmpty &&
        _selectedSite == null &&
        items.isEmpty) {
      return null;
    }

    return <String, dynamic>{
      'project_name': _projectNameCtrl.text,
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
      _disposeImageControllers();
      _draftObservedImages.clear();

      final payload = draft.payload;
      _projectNameCtrl.text = (payload['project_name'] as String?) ?? '';

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

      final List<dynamic> items =
          payload['items'] as List<dynamic>? ?? const <dynamic>[];
      for (final dynamic rawItem in items) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final source = (item['source'] as String?) ?? '';
        Uint8List? rawBytes;
        String name = (item['name'] as String?) ?? 'draft-image.jpg';

        if (source == 'attachment') {
          final reference = item['attachment_ref'] as String?;
          if (reference == null) continue;
          rawBytes = await DocumentDraftAttachmentStore.readBytes(reference);
          if (rawBytes == null) continue;
        } else if (source == 'network') {
          name = (item['url'] as String?) ?? name;
        } else {
          continue;
        }

        final meta = ImgMeta(
          rawBytes: rawBytes,
          name: name,
          defaultDate: (item['date'] as String?) ?? _todayStr,
          useTodayDate: item['use_today_date'] == true,
        );
        meta.locCtrl.text = (item['location'] as String?) ?? '';
        meta.descCtrl.text = (item['description'] as String?) ?? '';
        meta.showDate = item['show_date'] != false;
        meta.useTodayDate = item['use_today_date'] == true;
        _attachDraftListeners(meta);
        _images.add(meta);
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
      _loadPhotoDocPayload(widget.initialEditorPayload!);
    }

    if (widget.initSite != null) {
      _sites = <dynamic>[widget.initSite];
      _selectedSite = widget.initSite;
      if (_projectNameCtrl.text.trim().isEmpty) {
        _projectNameCtrl.text =
            (widget.initSite['name'] as String? ?? '').trim();
      }
    }

    if (!mounted) return;
    setState(() => _siteLoading = false);
  }

  /*──────────────── 取得工地清單 ────────────────*/
  Future<void> _fetchSites() async {
    try {
      final sites = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getMySites(token: token),
      );
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _siteLoading = false;
        // 自動選擇傳入的站點
        if (widget.initSite != null) {
          _selectedSite = _sites.firstWhere(
            (s) => s['id'] == widget.initSite['id'],
            orElse: () => null,
          );
        }
      });
      _attachDraftListenersForAllImages();
      unawaited(_maybeRestoreLocalDraft());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _siteErr = '讀取工地清單失敗：$e';
        _siteLoading = false;
      });
    }
  }

  void _disposeImageControllers() {
    for (final image in _images) {
      _disposeImageMeta(image);
    }
    _images.clear();
    _draftObservedImages.clear();
  }

  void _disposeImageMeta(ImgMeta image) {
    image.locCtrl.dispose();
    image.descCtrl.dispose();
    image.dateCtrl.dispose();
  }

  void _resetDeletedImageState() {
    _deletedFieldMappings.clear();
    _deletedStructuredItemIndexes.clear();
  }

  bool get _hasPendingImageDeletes =>
      _deletedFieldMappings.isNotEmpty ||
      _deletedStructuredItemIndexes.isNotEmpty;

  Uint8List? _getUploadBytes(ImgMeta img) {
    if (img.rawBytes == null) return null;
    return img.showDate ? (img.stampedBytes ?? img.rawBytes) : img.rawBytes;
  }

  Map<String, dynamic> _buildPhotoDocItem(ImgMeta img) {
    final Uint8List? bytes = _getUploadBytes(img);
    return <String, dynamic>{
      'location': img.locCtrl.text.trim(),
      'date': img.dateCtrl.text.trim(),
      'description': img.descCtrl.text.trim(),
      'image': img.name,
      if (bytes != null) '_bytes': bytes,
    };
  }

  Map<String, dynamic> _buildClearedPhotoDocItem() {
    return <String, dynamic>{
      'location': '',
      'date': '',
      'description': '',
      'image': '',
    };
  }

  void _removeImageAt(int idx) {
    if (idx < 0 || idx >= _images.length) return;

    final ImgMeta removedImage = _images[idx];
    setState(() {
      if (_isEditMode) {
        if (_usesStructuredEditorPayload) {
          final int? sourceIndex = removedImage.sourceIndex;
          if (sourceIndex != null) {
            _deletedStructuredItemIndexes.add(sourceIndex);
          }
        } else if (idx < _fieldMappings.length) {
          _deletedFieldMappings.add(_fieldMappings.removeAt(idx));
        }
      }
      _images.removeAt(idx);
    });

    _disposeImageMeta(removedImage);
    _draftObservedImages.remove(removedImage);
    _scheduleDraftAutosave();
  }

  String? _parseImageString(String? value) {
    final str = value?.trim() ?? '';
    if (str.isEmpty) return null;
    return FileManageAPIService.rewriteServerImageUrl(str, _apiBaseUrl);
  }

  String _normalizeUploadExtension(String name) {
    final String ext = p.extension(name).trim().toLowerCase();
    if (ext.isEmpty || ext.length > 5) {
      return '.jpg';
    }
    return ext;
  }

  BundleUploadFile? _findDraftFile(String uploadKey) {
    for (final BundleUploadFile file in widget.initialDraftFiles) {
      if (file.filename == uploadKey) {
        return file;
      }
    }
    return null;
  }

  ImgMeta? _imageMetaFromPayload({
    required dynamic imageValue,
    required int sourceIndex,
    required String dateText,
    required bool showDate,
    required bool useTodayDate,
  }) {
    if (imageValue is Map) {
      final Map<String, dynamic> imageMap =
          Map<String, dynamic>.from(imageValue);
      final String mode = (imageMap['mode'] as String? ?? '').trim();
      if (mode == 'keep') {
        final String? networkUrl =
            _parseImageString(imageMap['url'] as String? ?? '');
        if (networkUrl == null) return null;

        final ImgMeta meta = ImgMeta(
          name: networkUrl,
          sourceIndex: sourceIndex,
          defaultDate: dateText,
          useTodayDate: useTodayDate,
        );
        meta.showDate = showDate;
        return meta;
      }
      if (mode == 'upload') {
        final String uploadKey =
            (imageMap['upload_key'] as String? ?? '').trim();
        if (uploadKey.isEmpty) return null;
        final BundleUploadFile? file = _findDraftFile(uploadKey);
        if (file == null) return null;

        final Uint8List rawBytes = file.draftBytes ?? file.bytes;
        final ImgMeta meta = ImgMeta(
          rawBytes: rawBytes,
          stampedBytes: showDate ? file.bytes : null,
          name: uploadKey,
          sourceIndex: sourceIndex,
          defaultDate: dateText,
          useTodayDate: useTodayDate,
        );
        meta.showDate = showDate;
        meta.stampedDateText = showDate ? dateText : null;
        return meta;
      }
      return null;
    }

    final String? networkUrl = _parseImageString(
      imageValue as String?,
    );
    if (networkUrl == null) return null;

    final ImgMeta meta = ImgMeta(
      name: networkUrl,
      sourceIndex: sourceIndex,
      defaultDate: dateText,
      useTodayDate: useTodayDate,
    );
    meta.showDate = showDate;
    return meta;
  }

  bool _loadPhotoDocPayload(Map<String, dynamic> editorPayload) {
    if ((editorPayload['type'] as String?)?.trim() != 'photo_doc') {
      return false;
    }

    _disposeImageControllers();
    _fieldMappings.clear();
    _extraFields.clear();
    _projectNameCtrl.text =
        (editorPayload['project_name'] as String?)?.trim() ?? '';
    _resetDeletedImageState();

    final List<dynamic> items =
        (editorPayload['items'] as List<dynamic>?) ?? const <dynamic>[];
    for (int index = 0; index < items.length; index++) {
      final dynamic rawItem = items[index];
      if (rawItem is! Map) continue;

      final Map<String, dynamic> item = Map<String, dynamic>.from(rawItem);
      final Map<String, dynamic> uiState = item['_ui'] is Map
          ? Map<String, dynamic>.from(item['_ui'] as Map)
          : <String, dynamic>{};
      final String dateText =
          (item['date'] as String?)?.trim().isNotEmpty == true
              ? (item['date'] as String).trim()
              : _todayStr;
      final bool showDate = uiState['show_date'] == true;
      final bool useTodayDate = uiState['use_today_date'] == true ||
          (!uiState.containsKey('use_today_date') && dateText == _todayStr);

      final ImgMeta? meta = _imageMetaFromPayload(
        imageValue: item['image'] ??
            item['image_data_uri'] ??
            item['data_uri'] ??
            item['url'] ??
            item['original_text'],
        sourceIndex: index,
        dateText: dateText,
        showDate: showDate,
        useTodayDate: useTodayDate,
      );
      if (meta == null) continue;

      meta.locCtrl.text = (item['location'] as String?)?.trim() ?? '';
      meta.descCtrl.text = (item['description'] as String?)?.trim() ?? '';
      meta.showDate = showDate;
      meta.useTodayDate = useTodayDate;
      _attachDraftListeners(meta);
      _images.add(meta);
    }

    _usesStructuredEditorPayload = true;
    return true;
  }

  bool _loadExistingDocFromEditorPayload(Map<String, dynamic> response) {
    final String documentTypeName =
        (response['document_type_name'] as String?)?.trim() ?? '';
    final dynamic rawEditorPayload = response['editor_payload'];
    if (documentTypeName != '圖片表格列' || rawEditorPayload is! Map) {
      return false;
    }
    return _loadPhotoDocPayload(Map<String, dynamic>.from(rawEditorPayload));
  }

  Map<String, dynamic> _buildStructuredPhotoDocPayload() {
    return <String, dynamic>{
      'type': 'photo_doc',
      'project_name': _projectNameCtrl.text.trim(),
      'items': <Map<String, dynamic>>[
        ..._images.map(_buildPhotoDocItem),
        for (int i = 0; i < _deletedStructuredItemIndexes.length; i++)
          _buildClearedPhotoDocItem(),
      ],
    };
  }

  void _moveImageToIndex(int fromIndex, int toIndex) {
    if (fromIndex == toIndex ||
        fromIndex < 0 ||
        fromIndex >= _images.length ||
        toIndex < 0 ||
        toIndex >= _images.length) {
      return;
    }

    setState(() {
      // Keep field mappings anchored to document row slots so the reordered
      // list writes back into the new visible order on save.
      final ImgMeta movedImage = _images.removeAt(fromIndex);
      _images.insert(toIndex, movedImage);
    });
    _scheduleDraftAutosave();
  }

  void _moveImageUp(int index) => _moveImageToIndex(index, index - 1);

  void _moveImageDown(int index) => _moveImageToIndex(index, index + 1);

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

      _resetDeletedImageState();
      _usesStructuredEditorPayload = false;
      _disposeImageControllers();
      _fieldMappings.clear();
      _extraFields.clear();
      _apiBaseUrl = await FileManageAPIService.baseUrl;

      if (_loadExistingDocFromEditorPayload(docFieldsResp)) {
        if (!mounted) return;
        setState(() => _siteLoading = false);
        _attachDraftListenersForAllImages();
        unawaited(_maybeRestoreLocalDraft());
        return;
      }

      final fields = (docFieldsResp['fields'] as List<dynamic>?) ?? [];

      // 將表格欄位按 seg:table 分組（同一張照片的所有列歸為同一組）
      final tableFields = fields.where((f) => f['is_table'] == true).toList();
      final bySegTable = <String, List<dynamic>>{};
      for (final f in tableFields) {
        final seg = (f['seg_index'] as num?)?.toInt() ?? 0;
        final tid = (f['table_index'] as num?)?.toInt() ?? 0;
        final key = '$seg:$tid';
        bySegTable.putIfAbsent(key, () => []).add(f);
      }
      final sortedKeys = bySegTable.keys.toList()..sort();

      // 已知的欄位標籤 → 類型映射
      const dateLabels = {'日期', 'date'};
      const numberLabels = {'編號', 'number', '序號'};
      const locationLabels = {'位置', '地點', 'location'};
      const descLabels = {'說明', '描述', 'description', '備註'};

      for (final key in sortedKeys) {
        final groupFields = bySegTable[key]!;

        // 判斷此 group 是否包含圖片
        final hasImage = groupFields.any((f) {
          if ((f['image_data_uri'] as String?)?.isNotEmpty == true) return true;
          final t = (f['original_text'] as String?) ?? '';
          return t.startsWith('data:image/') ||
              t.startsWith('http') ||
              t.startsWith('/');
        });
        if (!hasImage) {
          // 無圖片的 group（如公用的表頭列）→ 全部保留到 extra
          for (final f in groupFields) {
            _extraFields[f['field_id'] as int] =
                (f['original_text'] as String?) ?? '';
          }
          continue;
        }

        // 按 row → col 排序，方便找 "label | value" 配對
        final byRow = <int, List<dynamic>>{};
        for (final f in groupFields) {
          byRow
              .putIfAbsent((f['row_index'] as num?)?.toInt() ?? 0, () => [])
              .add(f);
        }
        for (final list in byRow.values) {
          list.sort((a, b) => ((a['col_index'] as int?) ?? 0)
              .compareTo((b['col_index'] as int?) ?? 0));
        }

        final mapping = _PhotoFieldMapping();
        String? imgUrl;
        String dateText = _todayStr;
        String locText = '';
        String descText = '';

        for (final row in (byRow.keys.toList()..sort())) {
          final cells = byRow[row]!;
          for (int i = 0; i < cells.length; i++) {
            final f = cells[i];
            final fid = f['field_id'] as int;
            final raw = (f['original_text'] as String?) ?? '';

            // 圖片欄位
            final uri = (f['image_data_uri'] as String?)?.trim();
            if (uri != null && uri.isNotEmpty) {
              mapping.imageFieldId = fid;
              imgUrl = uri;
              continue;
            }
            if (raw.startsWith('data:image/') ||
                raw.startsWith('http') ||
                raw.startsWith('/')) {
              mapping.imageFieldId = fid;
              imgUrl = raw; // HTTP url or data URI
              continue;
            }

            // 檢查此格是否為「標籤格」：文字完全符合已知標籤
            final rawLower = raw.toLowerCase().trim();
            bool isLabel(Set<String> labels) =>
                labels.any((l) => rawLower == l);

            // 若此格為標籤，下一格就是值
            if (i + 1 < cells.length) {
              final nextF = cells[i + 1];
              final nextFid = nextF['field_id'] as int;
              final nextRaw = (nextF['original_text'] as String?) ?? '';

              if (isLabel(dateLabels) && mapping.dateFieldId == null) {
                mapping.dateFieldId = nextFid;
                if (nextRaw.isNotEmpty) dateText = nextRaw;
                // 本標籤格記入 extra
                _extraFields[fid] = raw;
                i++; // 跳過值格
                continue;
              }
              if (isLabel(numberLabels) && mapping.numberFieldId == null) {
                mapping.numberFieldId = nextFid;
                _extraFields[fid] = raw;
                i++;
                continue;
              }
              if (isLabel(locationLabels) && mapping.locationFieldId == null) {
                mapping.locationFieldId = nextFid;
                locText = nextRaw;
                _extraFields[fid] = raw;
                i++;
                continue;
              }
              if (isLabel(descLabels) && mapping.descriptionFieldId == null) {
                mapping.descriptionFieldId = nextFid;
                descText = nextRaw;
                _extraFields[fid] = raw;
                i++;
                continue;
              }
            }

            // 若此格本身就是標籤但沒有下一格（說明可能跨欄到最右）
            // 或不是已知標籤 → 記入 extra
            _extraFields[fid] = raw;
          }
        }

        if (imgUrl != null) {
          final meta = ImgMeta(
            name: imgUrl,
            defaultDate: dateText,
            useTodayDate: dateText == _todayStr,
          );
          meta.locCtrl.text = locText;
          meta.descCtrl.text = descText;
          meta.showDate = false; // 編輯模式圖片已含浮水印，預設不再蓋
          _attachDraftListeners(meta);
          _images.add(meta);
          _fieldMappings.add(mapping);
        }
      }

      // 段落欄位也需保留
      for (final f in fields.where((x) => x['is_table'] != true)) {
        _extraFields[f['field_id'] as int] =
            (f['original_text'] as String?) ?? '';
      }

      if (!mounted) return;
      setState(() => _siteLoading = false);
      _attachDraftListenersForAllImages();
      unawaited(_maybeRestoreLocalDraft());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _siteErr = '載入文件失敗：$e';
        _siteLoading = false;
      });
    }
  }

  /*──────────────── 對圖片加日期 ────────────────*/
  Future<Uint8List> _stampDate(Uint8List srcBytes, String dateText) async {
    return await UnifiedImageService.stampDate(srcBytes, dateText);
  }

  Future<void> _ensureStampedBytes(ImgMeta img) async {
    if (img.rawBytes == null) return;

    final String dateText = img.dateCtrl.text.trim();
    if (img.stampedBytes != null && img.stampedDateText == dateText) {
      return;
    }

    img.stampedBytes = await _stampDate(img.rawBytes!, dateText);
    img.stampedDateText = dateText;
  }

  Object _stampCacheKey(ImgMeta img) {
    return Object.hash(
      identityHashCode(img.rawBytes),
      img.dateCtrl.text.trim(),
      img.showDate,
    );
  }

  /*──────────────── 開相機（失敗自動轉多選） ────────────────*/
  Future<void> _openCamera() async {
    final shots = await UnifiedImageService.openCameraOrPickMulti(
        context, const CameraCapturePage());
    if (!mounted || shots.isEmpty) return;
    _setBusy(true);
    try {
      final List<ImgMeta> nextImages = <ImgMeta>[];
      for (final x in shots) {
        final raw = await x.readAsBytes();
        nextImages.add(
          ImgMeta(
            rawBytes: raw,
            name: p.basename(x.path),
            defaultDate: _todayStr,
            useTodayDate: true,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _images.addAll(nextImages);
      });
      for (final image in nextImages) {
        _attachDraftListeners(image);
      }
      _scheduleDraftAutosave();
    } finally {
      _setBusy(false);
    }
  }

  /*──────────────── 多選相簿 ────────────────*/
  Future<void> _pickMulti() async {
    final xs = await UnifiedImageService.pickMultiImage(imageQuality: 85);
    if (xs.isEmpty) return;
    _setBusy(true);
    try {
      final List<ImgMeta> nextImages = <ImgMeta>[];
      for (final x in xs) {
        final raw = await x.readAsBytes();
        nextImages.add(
          ImgMeta(
            rawBytes: raw,
            name: p.basename(x.path),
            defaultDate: _todayStr,
            useTodayDate: true,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _images.addAll(nextImages);
      });
      for (final image in nextImages) {
        _attachDraftListeners(image);
      }
      _scheduleDraftAutosave();
    } finally {
      _setBusy(false);
    }
  }

  /*──────────────── 將 idx 之後的圖片欄位批量貼上 ────────────────*/
  Future<void> _copyMetaToBelow(int idx) async {
    if (idx < 0 || idx >= _images.length - 1) return;
    final src = _images[idx];

    final srcDate = src.dateCtrl.text.trim();
    final srcLoc = src.locCtrl.text.trim();
    final srcDesc = src.descCtrl.text.trim();
    final srcShowDate = src.showDate;
    final srcUseTodayDate = src.useTodayDate;

    if (srcDate.isEmpty &&
        srcLoc.isEmpty &&
        srcDesc.isEmpty &&
        srcShowDate == false) {
      return;
    }

    _setBusy(true);
    try {
      for (int i = idx + 1; i < _images.length; i++) {
        final dst = _images[i];
        bool shouldInvalidateStamp = false;

        if (srcDate.isNotEmpty) {
          dst.dateCtrl.text = srcDate;
          dst.useTodayDate = srcUseTodayDate;
          shouldInvalidateStamp = true;
        }
        if (srcLoc.isNotEmpty) dst.locCtrl.text = srcLoc;
        if (srcDesc.isNotEmpty) dst.descCtrl.text = srcDesc;

        if (dst.showDate != srcShowDate) {
          dst.showDate = srcShowDate;
          shouldInvalidateStamp = true;
        }

        if (shouldInvalidateStamp) {
          dst.stampedBytes = null;
          dst.stampedDateText = null;
        }
      }
      if (mounted) setState(() {});
      _scheduleDraftAutosave();
    } finally {
      _setBusy(false);
    }
  }

  /*──────────────── 上傳 / 儲存 ────────────────*/
  Future<void> _submit() async {
    if (_isDraftMode || _isEditMode) {
      if (_images.isEmpty && !_hasPendingImageDeletes) return;
    } else {
      if (!_formKey.currentState!.validate() || _images.isEmpty) return;
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

    for (int index = 0; index < _images.length; index++) {
      final ImgMeta img = _images[index];
      if (img.showDate && img.rawBytes != null) {
        await _ensureStampedBytes(img);
      }

      Map<String, dynamic> imageContract;
      if (img.rawBytes != null) {
        final Uint8List uploadBytes = _getUploadBytes(img)!;
        final Uint8List rawBytes = img.rawBytes!;
        final String uploadKey =
            'photo-$timestamp-$uploadCounter${_normalizeUploadExtension(img.name)}';
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
      } else {
        imageContract = <String, dynamic>{
          'mode': 'keep',
          'url': img.name,
        };
      }

      items.add(<String, dynamic>{
        'index': index + 1,
        'number': '${index + 1}',
        'location': img.locCtrl.text.trim(),
        'date': img.dateCtrl.text.trim(),
        'description': img.descCtrl.text.trim(),
        'image': imageContract,
        '_ui': <String, dynamic>{
          'show_date': img.showDate,
          'use_today_date': img.useTodayDate,
        },
      });
    }

    for (int i = 0; i < _deletedStructuredItemIndexes.length; i++) {
      items.add(<String, dynamic>{
        'index': _images.length + i + 1,
        'number': '',
        'location': '',
        'date': '',
        'description': '',
        'image': const <String, dynamic>{'mode': 'delete'},
        '_ui': const <String, dynamic>{
          'show_date': false,
          'use_today_date': false,
        },
      });
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      BundleChildDraftResult(
        documentTypeName: '圖片表格列',
        payload: <String, dynamic>{
          'type': 'photo_doc',
          'project_name': _projectNameCtrl.text.trim(),
          'items': items,
        },
        files: files,
      ),
    );
  }

  Future<void> _submitCreate() async {
    final List<Map<String, dynamic>> imgPayload = [];
    for (var i = 0; i < _images.length; i++) {
      final img = _images[i];
      Uint8List? bytes;
      if (img.isNetworkImage) {
        bytes = null;
      } else if (img.showDate && img.rawBytes != null) {
        await _ensureStampedBytes(img);
        bytes = img.stampedBytes;
      } else {
        bytes = img.rawBytes;
      }
      imgPayload.add({
        'filename': img.name,
        'data_uri': img.name,
        'location': img.locCtrl.text.trim(),
        'description': img.descCtrl.text.trim(),
        'number': '${i + 1}',
        'date': img.dateCtrl.text.trim(),
        if (bytes != null) '_bytes': bytes,
      });
    }

    if (!mounted) return;
    await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.createPhotoDoc(
        token: token,
        siteId: _selectedSiteId!,
        images: imgPayload,
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
      for (final img in _images) {
        if (img.showDate && img.rawBytes != null) {
          await _ensureStampedBytes(img);
        }
      }

      if (!mounted) return;

      await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.fillDocumentStructured(
          token: token,
          fileId: widget.fileId!,
          payload: _buildStructuredPhotoDocPayload(),
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

    // 回寫圖片列對應欄位
    for (var i = 0; i < _images.length; i++) {
      final img = _images[i];
      final mapping = i < _fieldMappings.length ? _fieldMappings[i] : null;
      if (mapping == null) continue;

      Uint8List? bytes = _getUploadBytes(img);
      if (!img.isNetworkImage && img.showDate && img.rawBytes != null) {
        await _ensureStampedBytes(img);
        bytes = img.stampedBytes;
      }

      if (mapping.imageFieldId != null) {
        fillData.add({
          'field_id': '${mapping.imageFieldId}',
          'new_text': img.name,
          if (bytes != null) '_bytes': bytes,
        });
      }
      if (mapping.dateFieldId != null) {
        fillData.add({
          'field_id': '${mapping.dateFieldId}',
          'new_text': img.dateCtrl.text.trim(),
        });
      }
      if (mapping.locationFieldId != null) {
        fillData.add({
          'field_id': '${mapping.locationFieldId}',
          'new_text': img.locCtrl.text.trim(),
        });
      }
      if (mapping.descriptionFieldId != null) {
        fillData.add({
          'field_id': '${mapping.descriptionFieldId}',
          'new_text': img.descCtrl.text.trim(),
        });
      }
      if (mapping.numberFieldId != null) {
        fillData.add({
          'field_id': '${mapping.numberFieldId}',
          'new_text': '${i + 1}',
        });
      }
    }

    for (final mapping in _deletedFieldMappings) {
      if (mapping.imageFieldId != null) {
        fillData.add({
          'field_id': '${mapping.imageFieldId}',
          'new_text': '',
        });
      }
      if (mapping.dateFieldId != null) {
        fillData.add({
          'field_id': '${mapping.dateFieldId}',
          'new_text': '',
        });
      }
      if (mapping.locationFieldId != null) {
        fillData.add({
          'field_id': '${mapping.locationFieldId}',
          'new_text': '',
        });
      }
      if (mapping.descriptionFieldId != null) {
        fillData.add({
          'field_id': '${mapping.descriptionFieldId}',
          'new_text': '',
        });
      }
      if (mapping.numberFieldId != null) {
        fillData.add({
          'field_id': '${mapping.numberFieldId}',
          'new_text': '',
        });
      }
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

  /*────────────────── UI ──────────────────*/
  @override
  Widget build(BuildContext context) {
    final body = _siteLoading
        ? const Center(child: CircularProgressIndicator())
        : _siteErr != null
            ? Center(child: Text(_siteErr!))
            : _buildForm();

    return ResponsiveScaffold(
      title: _isDraftMode
          ? (_isEditMode
              ? AppLocalizations.of(context)!.editPhotoDocTitle
              : AppLocalizations.of(context)!.addPhotoDocTitle)
          : (_isEditMode
              ? AppLocalizations.of(context)!.editPhotoDocTitle
              : AppLocalizations.of(context)!.addPhotoDocTitle),
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

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        if (!_isEditMode && !_isDraftMode)
          Form(
            key: _formKey,
            child: Column(
              children: [
                /*── 工地 ─*/
                LabeledDropdownField<dynamic>(
                  label: AppLocalizations.of(context)!.siteName,
                  items: _sites
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s['name'])))
                      .toList(),
                  value: _selectedSite,
                  onChanged: (v) {
                    setState(() => _selectedSite = v);
                    _scheduleDraftAutosave();
                  },
                  validator: (v) => v == null
                      ? AppLocalizations.of(context)!.requiredSelect
                      : null,
                ),
              ],
            ),
          ),
        if (_isDraftMode || (_isEditMode && _usesStructuredEditorPayload)) ...[
          LabeledTextField(
            controller: _projectNameCtrl,
            label: AppLocalizations.of(context)!.projectNameLabel,
            outlined: true,
            enabled: !(_isDraftMode && widget.initSite != null),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 16),
        Row(children: [
          ElevatedButton.icon(
            onPressed: _openCamera,
            icon: const Icon(Icons.camera_alt),
            label: Text(AppLocalizations.of(context)!.takePhoto),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _pickMulti,
            icon: const Icon(Icons.collections),
            label: Text(AppLocalizations.of(context)!.multiSelectAlbum),
          ),
          const Spacer(),
          Text(AppLocalizations.of(context)!.todayLabel(_todayStr)),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: _images.isEmpty
              ? Center(child: Text(AppLocalizations.of(context)!.addPhotosHint))
              : ListView.builder(
                  itemCount: _images.length,
                  itemBuilder: (_, i) => _imageCard(i),
                ),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: Icon((_isEditMode || _isDraftMode) ? Icons.save : Icons.upload),
          label: Text((_isEditMode || _isDraftMode)
              ? AppLocalizations.of(context)!.save
              : AppLocalizations.of(context)!.createDocx),
        ),
      ]),
    );
  }

  /*── 圖片卡片 ─────────────────────────────*/
  Widget _imageCard(int idx) {
    final img = _images[idx];
    final no = '${idx + 1}'.padLeft(3, '0');
    final AppLocalizations l = AppLocalizations.of(context)!;

    String compactShowDateLabel() {
      switch (Localizations.localeOf(context).languageCode) {
        case 'zh':
          return '日期戳記';
        case 'ja':
          return '日付戳記';
        case 'fr':
          return 'Tampon date';
        case 'vi':
          return 'Dấu ngày';
        case 'id':
          return 'Cap tanggal';
        case 'th':
          return 'ตราวันที่';
        default:
          return 'Date stamp';
      }
    }

    String todayDateButtonLabel() {
      switch (Localizations.localeOf(context).languageCode) {
        case 'zh':
          return '今日日期';
        case 'ja':
          return '今日';
        case 'fr':
          return 'Aujourd\'hui';
        case 'vi':
          return 'Hôm nay';
        case 'id':
          return 'Hari ini';
        case 'th':
          return 'วันนี้';
        default:
          return 'Today';
      }
    }

    void syncTodayDateState() {
      img.useTodayDate = img.dateCtrl.text.trim() == _todayStr;
    }

    /*── 刷新蓋章 ──────────────────────────*/
    Future<void> refreshStamp() async {
      if (!img.showDate || img.rawBytes == null) {
        return;
      }

      await _ensureStampedBytes(img);
      if (!mounted) return;
      setState(() {});
    }

    /*── 剪貼機制 (整欄位) ─────────────────*/
    void cut(TextEditingController c, {bool isDate = false}) {
      UnifiedImageService.cutText(c);
      if (isDate) {
        if (!mounted) return;
        setState(syncTodayDateState);
        refreshStamp();
      }
    }

    void copy(TextEditingController c) {
      UnifiedImageService.copyTextFromController(c);
    }

    Future<void> paste(TextEditingController c, {bool isDate = false}) async {
      await UnifiedImageService.pasteText(c);
      if (isDate) {
        if (!mounted) return;
        setState(syncTodayDateState);
        await refreshStamp();
      }
    }

    List<Widget> buildClipboardActions(
      TextEditingController controller, {
      bool isDate = false,
    }) {
      return <Widget>[
        IconButton(
          icon: const Icon(Icons.cut),
          onPressed: () => cut(controller, isDate: isDate),
        ),
        IconButton(
          icon: const Icon(Icons.copy),
          onPressed: () => copy(controller),
        ),
        IconButton(
          icon: const Icon(Icons.paste),
          onPressed: () => paste(controller, isDate: isDate),
        ),
      ];
    }

    Future<void> replaceImage() async {
      final fromCamera = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(AppLocalizations.of(ctx)!.takePhoto),
                onTap: () => Navigator.pop(ctx, true),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(AppLocalizations.of(ctx)!.multiSelectAlbum),
                onTap: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      );
      if (fromCamera == null) return;

      final xFile = await UnifiedImageService.pickSingleImage(
        fromCamera: fromCamera,
      );
      if (xFile == null) return;

      _setBusy(true);
      try {
        final raw = await xFile.readAsBytes();
        if (!mounted) return;
        setState(() {
          img.rawBytes = raw;
          img.stampedBytes = null;
          img.stampedDateText = null;
          img.name =
              p.basename(xFile.path); // Removes the network image URL switch
        });
        _scheduleDraftAutosave();
      } finally {
        _setBusy(false);
      }
    }

    return Card(
      key: ObjectKey(img),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ThemeData theme = Theme.of(context);
            final ColorScheme cs = theme.colorScheme;
            final TextTheme tt = theme.textTheme;
            final double maxWidth = constraints.maxWidth;
            final bool useSplitLayout = maxWidth >= 920;
            final double contentSpacing = useSplitLayout ? 18 : 10;
            final double detailPanelWidth =
                useSplitLayout ? (maxWidth >= 1180 ? 364.0 : 324.0) : maxWidth;
            final double imageWidth = useSplitLayout
                ? (maxWidth - detailPanelWidth - contentSpacing)
                    .clamp(320.0, 720.0)
                    .toDouble()
                : maxWidth.clamp(280.0, 720.0).toDouble();
            final double imageHeight =
                (imageWidth * (useSplitLayout ? 0.66 : 0.62))
                    .clamp(220.0, 420.0)
                    .toDouble();
            final bool canStamp = img.rawBytes != null;

            Widget buildActionButton({
              required IconData icon,
              required VoidCallback? onPressed,
              required String tooltip,
            }) {
              return IconButton(
                tooltip: tooltip,
                onPressed: onPressed,
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHigh,
                  foregroundColor:
                      onPressed == null ? cs.outline : cs.onSurfaceVariant,
                  minimumSize: const Size(36, 36),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(icon, size: 18),
              );
            }

            final Widget dateSettings = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text(compactShowDateLabel()),
                      selected: img.showDate,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: canStamp
                          ? (selected) {
                              setState(() => img.showDate = selected);
                              _scheduleDraftAutosave();
                              if (selected) {
                                refreshStamp();
                              }
                            }
                          : null,
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (img.useTodayDate &&
                            img.dateCtrl.text.trim() == _todayStr) {
                          return;
                        }
                        setState(() {
                          img.useTodayDate = true;
                          img.dateCtrl.text = _todayStr;
                        });
                        _scheduleDraftAutosave();
                        refreshStamp();
                      },
                      icon: const Icon(Icons.today_outlined, size: 16),
                      label: Text(todayDateButtonLabel()),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: img.useTodayDate
                            ? cs.secondaryContainer
                            : cs.surface,
                        foregroundColor: img.useTodayDate
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant,
                        side: BorderSide(
                          color: img.useTodayDate
                              ? cs.secondaryContainer
                              : cs.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LabeledTextField(
                  controller: img.dateCtrl,
                  label: l.dateLabel,
                  outlined: true,
                  onChanged: (value) {
                    setState(syncTodayDateState);
                    _scheduleDraftAutosave();
                    refreshStamp();
                  },
                  trailingIcons: buildClipboardActions(
                    img.dateCtrl,
                    isDate: true,
                  ),
                ),
              ],
            );

            final Widget metadataFields = Container(
              width: double.infinity,
              padding: EdgeInsets.all(useSplitLayout ? 16 : 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  dateSettings,
                  const SizedBox(height: 12),
                  LabeledTextField(
                    controller: img.locCtrl,
                    label: l.locationLabel,
                    outlined: true,
                    trailingIcons: buildClipboardActions(img.locCtrl),
                  ),
                  const SizedBox(height: 10),
                  LabeledTextField(
                    controller: img.descCtrl,
                    label: l.descriptionLabel,
                    outlined: true,
                    maxLines: useSplitLayout ? 5 : 3,
                    trailingIcons: buildClipboardActions(img.descCtrl),
                  ),
                ],
              ),
            );

            final Widget imageSection = Container(
              width: double.infinity,
              padding: EdgeInsets.all(useSplitLayout ? 10 : 6),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ImageBox(
                  rawBytes: img.rawBytes,
                  stampedBytes: img.stampedBytes,
                  imageUrl: img.isNetworkImage ? img.name : null,
                  showDate: img.showDate,
                  stampedBytesBuilder: img.rawBytes == null
                      ? null
                      : () async {
                          await _ensureStampedBytes(img);
                          return img.stampedBytes!;
                        },
                  stampCacheKey: _stampCacheKey(img),
                  showCheckbox: false,
                  onDelete: null,
                  onTap: replaceImage,
                  tag: l.groupNumberLabel(no),
                  width: imageWidth,
                  height: imageHeight,
                ),
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l.groupNumberLabel(no),
                      style: tt.labelLarge?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      buildActionButton(
                        icon: Icons.arrow_downward,
                        tooltip: l.applyImageDataToAll,
                        onPressed: () => _copyMetaToBelow(idx),
                      ),
                      buildActionButton(
                        icon: Icons.keyboard_arrow_up,
                        tooltip: WidgetsLocalizations.of(context).reorderItemUp,
                        onPressed: idx == 0 ? null : () => _moveImageUp(idx),
                      ),
                      buildActionButton(
                        icon: Icons.keyboard_arrow_down,
                        tooltip:
                            WidgetsLocalizations.of(context).reorderItemDown,
                        onPressed: idx == _images.length - 1
                            ? null
                            : () => _moveImageDown(idx),
                      ),
                      buildActionButton(
                        icon: Icons.close,
                        tooltip: l.delete,
                        onPressed: () => _removeImageAt(idx),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 14),
                if (useSplitLayout)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: imageSection),
                      SizedBox(width: contentSpacing),
                      SizedBox(
                        width: detailPanelWidth,
                        child: metadataFields,
                      ),
                    ],
                  )
                else ...[
                  imageSection,
                  const SizedBox(height: 8),
                  metadataFields,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
