import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/document_draft_remote_store.dart';
import '../../services/document_draft_service.dart';
import '../../services/file_manage_api_service.dart';
import '../../utils/app_navigation.dart';
import '../../utils/auth_utils.dart';
import '../../utils/file_routes.dart';
import '../../utils/signature_task_status.dart';
import '../../utils/user_display_name.dart';
import 'photo_doc_create_page.dart';
import 'audit_fix_doc_create_page.dart';
import 'file_bundle_create_page.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/choose_doc_type_sheet.dart';
import '../../widgets/app_transitions.dart';
import 'my_tasks_page.dart';

class _DocumentRevisionHint {
  const _DocumentRevisionHint({
    required this.status,
    required this.comment,
    required this.signerName,
  });

  final String status;
  final String comment;
  final String signerName;
}

class _PendingSignatureTaskSummary {
  const _PendingSignatureTaskSummary({
    required this.count,
    required this.documentIds,
  });

  final int count;
  final Set<int> documentIds;
}

enum _FileWorkflowFilter {
  all,
  pendingMine,
  rejected,
  locked,
  recent,
}

class _FileWorkflowBadge {
  const _FileWorkflowBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

class FileListPage extends StatefulWidget {
  const FileListPage({super.key});

  @override
  State<FileListPage> createState() => _FileListPageState();
}

class _FileListPageState extends State<FileListPage> {
  static const double _desktopWebBreakpoint = 900;

  /*──────── 篩選條件 ────────*/
  String? _lastSeenLocation;
  List<dynamic> _mySites = [];
  int? _siteId;
  DateTime? _startTime;
  DateTime? _endTime;
  String _keyword = '';
  final _kwCtrl = TextEditingController();
  Timer? _keywordDebounce;
  List<Map<String, dynamic>> _members = [];
  int? _creatorId;
  int? _editorId;
  int? _signerId;
  bool _loadingMembers = false;
  String? _memberLoadError;
  int _memberLoadRequestId = 0;

  /*──────── 清單 / 分頁 ────────*/
  final List<dynamic> _files = [];
  final _scroll = ScrollController();
  int _total = 0, _offset = 0;
  final int _limit = 20;
  bool _loading = true, _fetchingMore = false;
  String? _error;
  int _fileFetchRequestId = 0;
  _FileWorkflowFilter _workflowFilter = _FileWorkflowFilter.all;
  int _pendingSignTaskCount = 0;
  Set<int> _pendingSignTaskDocumentIds = <int>{};
  final Map<int, _DocumentRevisionHint> _revisionHintsByDocumentId =
      <int, _DocumentRevisionHint>{};
  int _revisionHintGeneration = 0;

  bool _useDesktopWebLayout(BuildContext context) {
    return foundation.kIsWeb &&
        MediaQuery.sizeOf(context).width >= _desktopWebBreakpoint;
  }

  String _copy(String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  /*──────── 生命週期 ────────*/
  @override
  void initState() {
    super.initState();
    _initData();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-fetch when go_router navigates back to this page (e.g., after
    // delete-on-back from FileEditPage). initState only fires on first mount.
    final String location = GoRouterState.of(context).uri.toString();
    if (_lastSeenLocation != null && _lastSeenLocation != location) {
      _fetchFiles(initial: true);
    }
    _lastSeenLocation = location;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _keywordDebounce?.cancel();
    _kwCtrl.dispose();
    super.dispose();
  }

  /*────────────────── 初始資料 ──────────────────*/
  Future<void> _initData() async {
    try {
      final results = await AuthUtils.withAuthRetry(
        context,
        (token) => Future.wait<dynamic>([
          FileManageAPIService.getMySites(token: token),
          FileManageAPIService.getMySignTasks(token: token),
        ]),
      );
      _mySites = List<dynamic>.from(results[0] as List<dynamic>);
      final List<Map<String, dynamic>> signTasks =
          List<Map<String, dynamic>>.from(results[1] as List<dynamic>);
      final _PendingSignatureTaskSummary pendingTasks =
          _summarizePendingSignTasks(signTasks);
      _pendingSignTaskCount = pendingTasks.count;
      _pendingSignTaskDocumentIds = pendingTasks.documentIds;
      if (!mounted) return;
      await _fetchFiles(initial: true);
      if (!mounted) return;
      await _loadMembers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshPendingSignTaskCount() async {
    try {
      final tasks = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getMySignTasks(token: token),
      );
      if (!mounted) return;
      final _PendingSignatureTaskSummary pendingTasks =
          _summarizePendingSignTasks(tasks);
      setState(() {
        _pendingSignTaskCount = pendingTasks.count;
        _pendingSignTaskDocumentIds = pendingTasks.documentIds;
      });
    } catch (_) {
      // Keep the existing badge count if the refresh fails.
    }
  }

  _PendingSignatureTaskSummary _summarizePendingSignTasks(
    Iterable<Map<String, dynamic>> tasks,
  ) {
    int count = 0;
    final Set<int> documentIds = <int>{};
    for (final Map<String, dynamic> task in tasks) {
      if (!countsAsPendingSignatureTask(task['status'] as String?)) continue;
      count += 1;
      final int? documentId = _documentIdFromTask(task);
      if (documentId != null) documentIds.add(documentId);
    }
    return _PendingSignatureTaskSummary(
      count: count,
      documentIds: documentIds,
    );
  }

  int? _documentIdFromTask(Map<String, dynamic> task) {
    final int? direct = _intFromValue(
      task['document_id'] ?? task['doc_id'] ?? task['file_id'],
    );
    if (direct != null) return direct;

    final dynamic document = task['document'] ?? task['file'];
    if (document is Map) {
      return _intFromValue(
        document['id'] ?? document['document_id'] ?? document['file_id'],
      );
    }
    return null;
  }

  void _scheduleRevisionHintLoad(
    List<dynamic> files, {
    required bool reset,
  }) {
    if (reset) {
      _revisionHintGeneration += 1;
      if (mounted) {
        setState(() => _revisionHintsByDocumentId.clear());
      } else {
        _revisionHintsByDocumentId.clear();
      }
    }

    if (files.isEmpty) return;

    unawaited(
      _loadRevisionHintsForFiles(
        files,
        generation: _revisionHintGeneration,
      ),
    );
  }

  Future<void> _loadRevisionHintsForFiles(
    List<dynamic> files, {
    required int generation,
  }) async {
    final Map<int, Map<dynamic, dynamic>> targetFiles =
        <int, Map<dynamic, dynamic>>{};

    for (final dynamic file in files) {
      if (file is! Map) continue;
      final int? docId = _intFromValue(file['id']);
      if (docId == null) continue;
      targetFiles.putIfAbsent(docId, () => file);
    }

    if (targetFiles.isEmpty) return;
    if (!mounted || generation != _revisionHintGeneration) return;

    try {
      final Map<int, _DocumentRevisionHint?> results =
          <int, _DocumentRevisionHint?>{};
      await AuthUtils.withAuthRetry(
        context,
        (String token) => Future.wait<void>(
          targetFiles.entries.map((MapEntry<int, Map<dynamic, dynamic>> entry) {
            return _fetchRevisionHintForFile(token, entry.key, entry.value)
                .then((hint) => results[entry.key] = hint);
          }),
        ),
      );

      if (!mounted || generation != _revisionHintGeneration) return;

      setState(() {
        for (final MapEntry<int, _DocumentRevisionHint?> result
            in results.entries) {
          if (result.value == null) {
            _revisionHintsByDocumentId.remove(result.key);
          } else {
            _revisionHintsByDocumentId[result.key] = result.value!;
          }
        }
      });
    } catch (_) {
      // Ignore revision hint failures so the document list remains usable.
    }
  }

  Future<_DocumentRevisionHint?> _fetchRevisionHintForFile(
    String token,
    int docId,
    Map<dynamic, dynamic> file,
  ) async {
    try {
      int? versionId =
          _intFromValue(file['latest_version_id'] ?? file['version_id']);
      if (versionId == null) {
        final Map<String, dynamic> detail =
            await FileManageAPIService.getFileById(
          token: token,
          fileId: docId,
        );
        versionId =
            _intFromValue(detail['latest_version_id'] ?? detail['version_id']);
      }
      if (versionId == null) {
        return null;
      }

      final List<Map<String, dynamic>> assignments =
          await FileManageAPIService.getSignatureAssignments(
        token: token,
        versionId: versionId,
      );
      final Map<int, Map<String, dynamic>> signerLookup =
          await _loadRevisionSignerLookupIfNeeded(
        token,
        versionId: versionId,
        assignments: assignments,
      );

      return _pickDocumentRevisionHint(
        assignments,
        signerLookup: signerLookup,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<int, Map<String, dynamic>>> _loadRevisionSignerLookupIfNeeded(
    String token, {
    required int versionId,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final bool needsLookup = assignments.any((assignment) {
      final String status =
          normalizeSignatureTaskStatus(assignment['status'] as String?);
      final String comment = (assignment['comment'] as String? ?? '').trim();
      if (!signatureTaskStatusRequiresComment(status) || comment.isEmpty) {
        return false;
      }
      if (userDisplayName(assignment, includeAccountFallback: false)
          .isNotEmpty) {
        return false;
      }
      return _assignmentSignerId(assignment) != null;
    });
    if (!needsLookup) return const <int, Map<String, dynamic>>{};

    try {
      final Map<String, dynamic> signerPayload =
          await FileManageAPIService.getSigners(
        token: token,
        versionId: versionId,
        limit: 500,
      );
      final List<dynamic> items =
          signerPayload['items'] as List<dynamic>? ?? const <dynamic>[];
      return _signerLookupFromItems(items);
    } catch (e) {
      if (foundation.kDebugMode) {
        foundation.debugPrint(
          '[FileListPage] Failed to load revision signer lookup '
          'versionId=$versionId: $e',
        );
      }
      return const <int, Map<String, dynamic>>{};
    }
  }

  Map<int, Map<String, dynamic>> _signerLookupFromItems(List<dynamic> items) {
    final Map<int, Map<String, dynamic>> lookup = <int, Map<String, dynamic>>{};
    for (final dynamic item in items) {
      if (item is! Map) continue;
      final Map<String, dynamic> signer = Map<String, dynamic>.from(item);
      final int? signerId = _memberId(signer);
      if (signerId == null) continue;
      lookup[signerId] = signer;
    }
    return lookup;
  }

  _DocumentRevisionHint? _pickDocumentRevisionHint(
    List<Map<String, dynamic>> assignments, {
    Map<int, Map<String, dynamic>> signerLookup =
        const <int, Map<String, dynamic>>{},
  }) {
    Map<String, dynamic>? best;
    for (final Map<String, dynamic> task in assignments) {
      final String status =
          normalizeSignatureTaskStatus(task['status'] as String?);
      final String comment = (task['comment'] as String? ?? '').trim();
      if (!signatureTaskStatusRequiresComment(status) || comment.isEmpty) {
        continue;
      }
      if (best == null || _compareRevisionHints(task, best) < 0) {
        best = task;
      }
    }

    if (best == null) return null;

    return _DocumentRevisionHint(
      status: normalizeSignatureTaskStatus(best['status'] as String?),
      comment: (best['comment'] as String? ?? '').trim(),
      signerName: _signerDisplayName(best, signerLookup: signerLookup),
    );
  }

  int _compareRevisionHints(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final int byPriority = _revisionHintPriority(a['status'] as String?)
        .compareTo(_revisionHintPriority(b['status'] as String?));
    if (byPriority != 0) return byPriority;

    final DateTime? updatedA =
        _dateTimeFromValue(a['updated_at'] ?? a['created_at']);
    final DateTime? updatedB =
        _dateTimeFromValue(b['updated_at'] ?? b['created_at']);
    if (updatedA != null && updatedB != null) {
      final int byUpdatedAt = updatedB.compareTo(updatedA);
      if (byUpdatedAt != 0) return byUpdatedAt;
    } else if (updatedA != null) {
      return -1;
    } else if (updatedB != null) {
      return 1;
    }

    final int taskIdA = _intFromValue(a['task_id']) ?? 0;
    final int taskIdB = _intFromValue(b['task_id']) ?? 0;
    return taskIdB.compareTo(taskIdA);
  }

  String _signerDisplayName(
    Map<String, dynamic> assignment, {
    Map<int, Map<String, dynamic>> signerLookup =
        const <int, Map<String, dynamic>>{},
  }) {
    final String directName =
        userDisplayName(assignment, includeAccountFallback: false);
    if (directName.isNotEmpty) return directName;

    final int? signerId = _assignmentSignerId(assignment);
    final Map<String, dynamic>? signer =
        signerId == null ? null : signerLookup[signerId];
    if (signer != null) {
      final String lookupName =
          userDisplayName(signer, includeAccountFallback: false);
      if (lookupName.isNotEmpty) return lookupName;
    }

    _debugMissingRevisionSignerName(assignment, signer);
    return '';
  }

  int? _assignmentSignerId(Map<String, dynamic> assignment) {
    return _intFromValue(assignment['signer_id'] ?? assignment['user_id']);
  }

  void _debugMissingRevisionSignerName(
    Map<String, dynamic> assignment,
    Map<String, dynamic>? signer,
  ) {
    if (!foundation.kDebugMode) return;
    foundation.debugPrint(
      '[FileListPage] Missing revision signer display name. '
      'signerId=${_assignmentSignerId(assignment)}, '
      'assignmentKeys=${assignment.keys.toList()}, '
      'assignmentNameFields=${_debugNameFields(assignment)}, '
      'lookupKeys=${signer?.keys.toList()}, '
      'lookupNameFields=${signer == null ? null : _debugNameFields(signer)}',
    );
  }

  Map<String, dynamic> _debugNameFields(Map<String, dynamic> source) {
    const List<String> keys = <String>[
      'signer_id',
      'user_id',
      'signer_name',
      'signer_username',
      'username',
      'family_name',
      'given_name',
      'signer_family_name',
      'signer_given_name',
      'full_name',
      'display_name',
      'name',
      'profile',
      'signer',
      'user',
    ];
    return <String, dynamic>{
      for (final String key in keys)
        if (source.containsKey(key)) key: source[key],
    };
  }

  int _revisionHintPriority(String? status) {
    switch (normalizeSignatureTaskStatus(status)) {
      case 'rejected':
        return 0;
      case 'commented':
        return 1;
      default:
        return 2;
    }
  }

  int? _intFromValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  DateTime? _dateTimeFromValue(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /*──────── 載入成員清單（用於建立人 / 編輯人 / 簽名人下拉選單） ────────*/
  Future<void> _loadMembers() async {
    if (!mounted) return;
    if (_siteId == null) {
      if (mounted) {
        setState(() {
          _members = [];
          _memberLoadError = null;
          _loadingMembers = false;
        });
      }
      return;
    }

    final int requestId = ++_memberLoadRequestId;
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final int? scopedGroupId = auth.isSuperAdmin ? null : auth.groupId;

    if (!mounted) return;
    setState(() {
      _loadingMembers = true;
      _memberLoadError = null;
      _members = [];
    });

    try {
      Map<String, dynamic> res = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getSigners(
          token: token,
          groupId: scopedGroupId,
          siteId: _siteId,
          limit: 200,
        ),
      );

      final List<Map<String, dynamic>> scopedMembers = _normalizeMembers(
          res['items'] as List<dynamic>? ?? const <dynamic>[]);

      if (scopedMembers.isEmpty && scopedGroupId != null) {
        if (!mounted) return;
        res = await AuthUtils.withAuthRetry(
          context,
          (token) => FileManageAPIService.getSigners(
            token: token,
            siteId: _siteId,
            limit: 200,
          ),
        );
      }

      if (!mounted) return;
      if (requestId != _memberLoadRequestId) return;

      setState(() {
        _members = _normalizeMembers(
          res['items'] as List<dynamic>? ?? const <dynamic>[],
        );
        _loadingMembers = false;
        _memberLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (requestId != _memberLoadRequestId) return;

      setState(() {
        _members = [];
        _loadingMembers = false;
        _memberLoadError = '$e';
      });
    }
  }

  List<Map<String, dynamic>> _normalizeMembers(List<dynamic> rawItems) {
    final Map<int, Map<String, dynamic>> deduped =
        <int, Map<String, dynamic>>{};

    for (final dynamic item in rawItems) {
      if (item is! Map) continue;
      final Map<String, dynamic> user = Map<String, dynamic>.from(item);
      final int? userId = _memberId(user);
      if (userId == null) continue;
      deduped[userId] = user;
    }

    final List<Map<String, dynamic>> members = deduped.values.toList()
      ..sort((a, b) => _memberDisplayName(a).compareTo(_memberDisplayName(b)));
    return members;
  }

  int? _memberId(Map<String, dynamic> user) {
    final dynamic raw = user['id'] ?? user['user_id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String _memberDisplayName(Map<String, dynamic> user) {
    return userDisplayName(user, fallback: '?');
  }

  /*──────── 滾動載入更多 ────────*/
  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _fetchFiles(initial: false);
    }
  }

  /*────────────────── 讀取文件清單 ──────────────────*/
  Future<void> _fetchFiles({required bool initial}) async {
    if (!mounted) return;
    if (!initial && _fetchingMore) return;
    if (!initial && _offset >= _total) return;

    final int requestId = initial ? ++_fileFetchRequestId : _fileFetchRequestId;

    if (initial) {
      setState(() {
        _files.clear();
        _offset = 0;
        _loading = true;
        _fetchingMore = false;
        _error = null;
      });
    } else {
      setState(() => _fetchingMore = true);
    }

    try {
      final res = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getFiles(
          token: token,
          keyword: _keyword,
          siteId: _siteId,
          startTime: _startTime,
          endTime: _endTime,
          creatorId: _creatorId,
          editorId: _editorId,
          signerId: _signerId,
          limit: _limit,
          offset: _offset,
        ),
      );
      if (!mounted || requestId != _fileFetchRequestId) return;
      final List<dynamic> fetchedFiles = List<dynamic>.from(
          res['files'] as List<dynamic>? ?? const <dynamic>[]);
      setState(() {
        _total = res['total'] ?? 0;
        _files.addAll(fetchedFiles);
        _offset += _limit;
      });
      _scheduleRevisionHintLoad(fetchedFiles, reset: initial);
    } catch (e) {
      if (!mounted || requestId != _fileFetchRequestId) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted && requestId == _fileFetchRequestId) {
        setState(() {
          _loading = false;
          _fetchingMore = false;
        });
      }
    }
  }

  /*────────────────── 站點選單 → 選檔 → 上傳 ──────────────────*/
  Future<void> _pickAndUpload() async {
    final site = await _pickSiteDialog();
    if (site == null) return;
    final int siteId = site['id'];

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );
    if (result?.files.single.bytes == null) return;
    if (!mounted) return;

    final bytes = result!.files.single.bytes!;
    final name = result.files.single.name;

    try {
      final created = await AuthUtils.withAuthRetry(
          context,
          (token) => FileManageAPIService.uploadDocument(
                token: token,
                fileName: name,
                bytes: bytes,
                siteId: siteId,
              ));
      if (!mounted) return;
      context.go(
        fileEditLocation(
          docRef: created.fullFileCode,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context)!.uploadFailed(e.toString()))));
    }
  }

  /*──────── 站點挑選對話框 ────────*/
  Future<Map<String, dynamic>?> _pickSiteDialog() async {
    if (!mounted) return null;
    if (_mySites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.sitesNotLoaded)));
      return null;
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          AppLocalizations.of(dialogContext)!.selectConstructionSite,
        ),
        content: SizedBox(
          width: 300,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final s in _mySites)
                ListTile(
                  title: Text(s['name']),
                  onTap: () => Navigator.pop(
                    dialogContext,
                    {'id': s['id'], 'name': s['name'], 'site': s},
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /*──────── 刪除文件 ────────*/
  Future<void> _deleteDoc(int docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final local = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(local.confirmDeleteFile),
          content: Text(local.confirmDeleteFileMessage),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(local.cancel)),
            ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(local.delete)),
          ],
        );
      },
    );
    if (ok != true) return;
    if (!mounted) return;
    final auth = context.read<UnifiedAuthProvider>();
    final draftRemoteStore = DocumentDraftRemoteStore(auth: auth);

    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) =>
            FileManageAPIService.deleteDocument(token: token, docId: docId),
      );
      await DocumentDraftService.deleteFileDrafts(
        userId: auth.userId,
        fileId: docId,
        remoteDeleter: draftRemoteStore.delete,
        waitForRemote: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.fileDeleted)));
        _fetchFiles(initial: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${AppLocalizations.of(context)!.deleteFailed}：$e')));
      }
    }
  }

  List<dynamic> get _workflowFilteredFiles {
    if (_workflowFilter == _FileWorkflowFilter.all) {
      return _files;
    }
    return _files
        .where((dynamic file) => _matchesWorkflowFilter(file, _workflowFilter))
        .toList(growable: false);
  }

  bool _matchesWorkflowFilter(
    dynamic file,
    _FileWorkflowFilter filter,
  ) {
    switch (filter) {
      case _FileWorkflowFilter.all:
        return true;
      case _FileWorkflowFilter.pendingMine:
        return _needsMySignature(file);
      case _FileWorkflowFilter.rejected:
        return _wasReturnedOrRejected(file);
      case _FileWorkflowFilter.locked:
        return _isFileLocked(file);
      case _FileWorkflowFilter.recent:
        return _isRecentlyEdited(file);
    }
  }

  int? _documentIdFromFile(dynamic file) {
    if (file is! Map) return null;
    return _intFromValue(file['id'] ?? file['document_id'] ?? file['file_id']);
  }

  bool _isFileLocked(dynamic file) {
    if (file is! Map) return false;
    return _boolFromValue(file['is_locked'] ?? file['locked']) ||
        _truthyWorkflowFlag(file, const <String>[
          'is_locked',
          'locked',
          'document_locked',
        ]);
  }

  bool _needsMySignature(dynamic file) {
    final int? documentId = _documentIdFromFile(file);
    if (documentId != null &&
        _pendingSignTaskDocumentIds.contains(documentId)) {
      return true;
    }
    if (file is! Map) return false;

    final dynamic task =
        file['my_signature_task'] ?? file['pending_signature_task'];
    if (task is Map &&
        countsAsPendingSignatureTask(_stringFromValue(task['status']))) {
      return true;
    }

    return _truthyWorkflowFlag(file, const <String>[
      'needs_my_signature',
      'pending_mine',
      'pending_my_signature',
      'assigned_to_me',
      'awaiting_my_signature',
    ]);
  }

  bool _wasReturnedOrRejected(dynamic file) {
    final int? documentId = _documentIdFromFile(file);
    final _DocumentRevisionHint? hint =
        documentId == null ? null : _revisionHintsByDocumentId[documentId];
    if (hint != null && signatureTaskStatusRequiresComment(hint.status)) {
      return true;
    }
    if (file is! Map) return false;

    if (_truthyWorkflowFlag(file, const <String>[
      'returned',
      'rejected',
      'needs_revision',
      'has_revision_comment',
    ])) {
      return true;
    }

    final Iterable<String> statuses = <dynamic>[
      file['workflow_status'],
      file['revision_status'],
      file['latest_signature_status'],
      file['signature_status'],
      file['status'],
      _workflowMap(file)?['status'],
      _workflowMap(file)?['revision_status'],
      _workflowMap(file)?['latest_signature_status'],
    ]
        .map(_stringFromValue)
        .whereType<String>()
        .map((String status) => status.trim().toLowerCase());

    return statuses.any((String status) {
      return status == 'rejected' ||
          status == 'returned' ||
          status == 'needs_revision' ||
          status == 'commented';
    });
  }

  bool _isRecentlyEdited(dynamic file) {
    if (file is! Map) return false;
    final DateTime? updatedAt =
        _dateTimeFromValue(file['updated_at'] ?? file['created_at']);
    if (updatedAt == null) return false;
    final DateTime cutoff = DateTime.now().subtract(const Duration(days: 7));
    return updatedAt.toLocal().isAfter(cutoff);
  }

  Map<dynamic, dynamic>? _workflowMap(dynamic file) {
    if (file is! Map) return null;
    final dynamic workflow = file['workflow'] ?? file['workflow_state'];
    return workflow is Map ? workflow : null;
  }

  bool _truthyWorkflowFlag(
    Map<dynamic, dynamic> file,
    List<String> keys,
  ) {
    final Map<dynamic, dynamic>? workflow = _workflowMap(file);
    for (final String key in keys) {
      if (_boolFromValue(file[key])) return true;
      if (workflow != null && _boolFromValue(workflow[key])) return true;
    }
    return false;
  }

  bool _boolFromValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
        case 'y':
          return true;
      }
    }
    return false;
  }

  String? _stringFromValue(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  String _workflowFilterLabel(_FileWorkflowFilter filter) {
    final bool isZh = Localizations.localeOf(context).languageCode == 'zh';
    switch (filter) {
      case _FileWorkflowFilter.all:
        return isZh ? '全部' : 'All';
      case _FileWorkflowFilter.pendingMine:
        return isZh ? '待我簽核' : 'My Tasks';
      case _FileWorkflowFilter.rejected:
        return isZh ? '被退回' : 'Returned';
      case _FileWorkflowFilter.locked:
        return isZh ? '鎖定' : 'Locked';
      case _FileWorkflowFilter.recent:
        return isZh ? '最近編輯' : 'Recent';
    }
  }

  String _workflowFilterTitle() {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '文件狀態'
        : 'Document status';
  }

  String _workflowEmptyMessage() {
    final bool isZh = Localizations.localeOf(context).languageCode == 'zh';
    return isZh ? '沒有符合目前條件的文件' : 'No documents match the current filters';
  }

  IconData _workflowFilterIcon(_FileWorkflowFilter filter) {
    switch (filter) {
      case _FileWorkflowFilter.all:
        return Icons.view_list_outlined;
      case _FileWorkflowFilter.pendingMine:
        return Icons.assignment_turned_in_outlined;
      case _FileWorkflowFilter.rejected:
        return Icons.assignment_return_outlined;
      case _FileWorkflowFilter.locked:
        return Icons.lock_outline;
      case _FileWorkflowFilter.recent:
        return Icons.update_outlined;
    }
  }

  int _workflowFilterBadgeCount(_FileWorkflowFilter filter) {
    switch (filter) {
      case _FileWorkflowFilter.pendingMine:
        return _pendingSignTaskCount;
      case _FileWorkflowFilter.all:
      case _FileWorkflowFilter.rejected:
      case _FileWorkflowFilter.locked:
      case _FileWorkflowFilter.recent:
        return 0;
    }
  }

  String _formatCountBadge(int count) {
    return count > 99 ? '99+' : count.toString();
  }

  void _selectWorkflowFilter(_FileWorkflowFilter filter) {
    if (_workflowFilter == filter) return;
    setState(() => _workflowFilter = filter);
    unawaited(_applyFilters());
  }

  Future<void> _applyFilters() async {
    _keywordDebounce?.cancel();
    _keywordDebounce = null;
    _keyword = _kwCtrl.text.trim();
    await _fetchFiles(initial: true);
  }

  void _scheduleKeywordFilter() {
    _keywordDebounce?.cancel();
    _keywordDebounce = Timer(const Duration(milliseconds: 600), () {
      _keywordDebounce = null;
      if (!mounted) return;
      unawaited(_applyFilters());
    });
  }

  /*──────── UI ────────*/
  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final List<dynamic> visibleFiles = _workflowFilteredFiles;
    final bool showWorkflowEmptyState = !_fetchingMore && visibleFiles.isEmpty;
    final bool desktopWeb = _useDesktopWebLayout(context);
    final int itemCount = visibleFiles.length +
        1 +
        (showWorkflowEmptyState ? 1 : 0) +
        (_fetchingMore ? 1 : 0);

    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.documentListTitle,
      actions: [
        _buildSignTaskAction(),
        const SizedBox(width: 8),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child:
                      Text(AppLocalizations.of(context)!.errorPrefix(_error!)))
              : RefreshIndicator(
                  onRefresh: () => _fetchFiles(initial: true),
                  child: desktopWeb
                      ? _buildDesktopFileList(
                          fmt,
                          visibleFiles,
                          showWorkflowEmptyState,
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(8),
                          itemCount: itemCount,
                          itemBuilder: (context, index) {
                            if (index == 0) return _buildFilterCard(fmt);
                            if (showWorkflowEmptyState && index == 1) {
                              return _buildWorkflowEmptyState();
                            }
                            final int fileIndex =
                                index - 1 - (showWorkflowEmptyState ? 1 : 0);
                            if (fileIndex >= 0 &&
                                fileIndex < visibleFiles.length) {
                              return _buildItem(visibleFiles[fileIndex], fmt);
                            }
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                        ),
                ),
    );
  }

  Widget _buildDesktopFileList(
    DateFormat fmt,
    List<dynamic> visibleFiles,
    bool showWorkflowEmptyState,
  ) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
      children: [
        _buildFilterCard(fmt),
        const SizedBox(height: 18),
        if (showWorkflowEmptyState) _buildWorkflowEmptyState(),
        if (visibleFiles.isNotEmpty)
          _buildDesktopDocumentTable(visibleFiles, fmt),
        if (_fetchingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  /*──────── 篩選卡片 ────────*/
  Widget _buildFilterCard(DateFormat fmt) {
    if (_useDesktopWebLayout(context)) {
      return _buildDesktopFilterPanel(fmt);
    }

    final ColorScheme cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            DropdownButton<int?>(
              isExpanded: true,
              value: _siteId,
              items: [
                DropdownMenuItem<int?>(
                    value: null,
                    child: Text(AppLocalizations.of(context)!.allSites)),
                ..._mySites.map((s) => DropdownMenuItem<int?>(
                    value: s['id'], child: Text(s['name']))),
              ],
              onChanged: (v) {
                setState(() {
                  _siteId = v;
                  _creatorId = null;
                  _editorId = null;
                  _signerId = null;
                  _members = [];
                  _memberLoadError = null;
                });
                unawaited(_loadMembers());
                unawaited(_applyFilters());
              },
            ),
            const SizedBox(height: 8),
            _buildUserDropdown(
              label: AppLocalizations.of(context)!.creatorLabel,
              value: _creatorId,
              onChanged: (v) {
                setState(() => _creatorId = v);
                unawaited(_applyFilters());
              },
            ),
            const SizedBox(height: 8),
            _buildUserDropdown(
              label: AppLocalizations.of(context)!.editorLabel,
              value: _editorId,
              onChanged: (v) {
                setState(() => _editorId = v);
                unawaited(_applyFilters());
              },
            ),
            const SizedBox(height: 8),
            _buildUserDropdown(
              label: AppLocalizations.of(context)!.signerLabel,
              value: _signerId,
              onChanged: (v) {
                setState(() => _signerId = v);
                unawaited(_applyFilters());
              },
            ),
            const SizedBox(height: 10),
            _buildWorkflowFilterRow(),
            if (_siteId == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppLocalizations.of(context)!.selectSiteFirstHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else if (_loadingMembers)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppLocalizations.of(context)!.loadingMemberList,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else if (_memberLoadError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppLocalizations.of(context)!
                        .memberLoadFailed(_memberLoadError!),
                    style: TextStyle(fontSize: 12, color: cs.error),
                  ),
                ),
              )
            else if (_members.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppLocalizations.of(context)!.noMemberListForSite,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _kwCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.keyword,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _scheduleKeywordFilter(),
              onSubmitted: (_) {
                unawaited(_applyFilters());
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text(AppLocalizations.of(context)!.startDate),
                    subtitle: Text(_startTime != null
                        ? fmt.format(_startTime!)
                        : AppLocalizations.of(context)!.notSelected),
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: Text(AppLocalizations.of(context)!.endDate),
                    subtitle: Text(_endTime != null
                        ? fmt.format(_endTime!)
                        : AppLocalizations.of(context)!.notSelected),
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final local = AppLocalizations.of(context)!;
                // Switch to icon-only when the available width is too small
                // to fit 2 labelled action buttons without overflow.
                final bool iconOnly = constraints.maxWidth < 320;

                Widget btn({
                  required IconData icon,
                  required String label,
                  required VoidCallback onPressed,
                }) {
                  return Expanded(
                    child: Tooltip(
                      message: label,
                      child: FilledButton.tonal(
                        onPressed: onPressed,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: iconOnly ? 0 : 8,
                          ),
                        ),
                        child: iconOnly
                            ? Icon(icon, size: 20)
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(icon, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      label,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  );
                }

                return Row(
                  children: [
                    btn(
                      icon: Icons.add,
                      label: local.add,
                      onPressed: _showChooseTypeSheet,
                    ),
                    const SizedBox(width: 8),
                    btn(
                      icon: Icons.upload_file,
                      label: local.uploadButton,
                      onPressed: _pickAndUpload,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopFilterPanel(DateFormat fmt) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;
    final Widget? memberStatus = _buildMemberStatusHint();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .72)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _copy('查詢條件', 'Filters'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _copy('依工地、成員、狀態與時間篩選文件',
                          'Filter documents by site, members, status and dates'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _pickAndUpload,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(local.uploadButton),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _showChooseTypeSheet,
                icon: const Icon(Icons.add, size: 18),
                label: Text(local.add),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildDesktopSiteSelector(local),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _kwCtrl,
                  decoration: _desktopInputDecoration(
                    label: local.keyword,
                    icon: Icons.search,
                  ),
                  onChanged: (_) => _scheduleKeywordFilter(),
                  onSubmitted: (_) => unawaited(_applyFilters()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDesktopUserDropdown(
                  label: local.creatorLabel,
                  icon: Icons.person_outline,
                  value: _creatorId,
                  onChanged: (v) {
                    setState(() => _creatorId = v);
                    unawaited(_applyFilters());
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDesktopUserDropdown(
                  label: local.editorLabel,
                  icon: Icons.edit_outlined,
                  value: _editorId,
                  onChanged: (v) {
                    setState(() => _editorId = v);
                    unawaited(_applyFilters());
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDesktopUserDropdown(
                  label: local.signerLabel,
                  icon: Icons.assignment_ind_outlined,
                  value: _signerId,
                  onChanged: (v) {
                    setState(() => _signerId = v);
                    unawaited(_applyFilters());
                  },
                ),
              ),
            ],
          ),
          if (memberStatus != null) ...[
            const SizedBox(height: 8),
            memberStatus,
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDesktopDateField(
                  label: local.startDate,
                  value: _startTime,
                  fmt: fmt,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDesktopDateField(
                  label: local.endDate,
                  value: _endTime,
                  fmt: fmt,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildWorkflowFilterRow(),
        ],
      ),
    );
  }

  InputDecoration _desktopInputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Widget _buildDesktopSiteSelector(AppLocalizations local) {
    final List<DropdownMenuItem<int?>> items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(local.allSites),
      ),
      ..._mySites.map((dynamic site) {
        final int? id = site is Map ? _intFromValue(site['id']) : null;
        if (id == null) return null;
        return DropdownMenuItem<int?>(
          value: id,
          child: Text('${site['name'] ?? id}'),
        );
      }).whereType<DropdownMenuItem<int?>>(),
    ];

    return DropdownButtonFormField<int?>(
      key: ValueKey<String>('file-site-${_siteId ?? 'all'}-${items.length}'),
      initialValue: _siteId,
      isExpanded: true,
      decoration: _desktopInputDecoration(
        label: _copy('工地', 'Site'),
        icon: Icons.location_on_outlined,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          _siteId = v;
          _creatorId = null;
          _editorId = null;
          _signerId = null;
          _members = [];
          _memberLoadError = null;
        });
        unawaited(_loadMembers());
        unawaited(_applyFilters());
      },
    );
  }

  Widget _buildDesktopUserDropdown({
    required String label,
    required IconData icon,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final bool enabled = _siteId != null && !_loadingMembers;
    final Set<int> memberIds = _members.map(_memberId).whereType<int>().toSet();
    final int? effectiveValue =
        value != null && memberIds.contains(value) ? value : null;

    return DropdownButtonFormField<int?>(
      key: ValueKey<String>(
        'file-user-$label-${effectiveValue ?? 'all'}-${_members.length}',
      ),
      initialValue: effectiveValue,
      isExpanded: true,
      decoration: _desktopInputDecoration(label: label, icon: icon),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text(local.allFilter(label)),
        ),
        ..._members.map((Map<String, dynamic> user) {
          final int? id = _memberId(user);
          if (id == null) return null;
          return DropdownMenuItem<int?>(
            value: id,
            child: Text(_memberDisplayName(user)),
          );
        }).whereType<DropdownMenuItem<int?>>(),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }

  Widget _buildDesktopDateField({
    required String label,
    required DateTime? value,
    required DateFormat fmt,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String text = value == null
        ? AppLocalizations.of(context)!.notSelected
        : fmt.format(value);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: InputDecorator(
        decoration: _desktopInputDecoration(
          label: label,
          icon: Icons.calendar_today_outlined,
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: value == null ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
      ),
    );
  }

  Widget? _buildMemberStatusHint() {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final ColorScheme cs = Theme.of(context).colorScheme;
    String? message;
    Color color = cs.onSurfaceVariant;

    if (_siteId == null) {
      message = local.selectSiteFirstHint;
    } else if (_loadingMembers) {
      message = local.loadingMemberList;
    } else if (_memberLoadError != null) {
      message = local.memberLoadFailed(_memberLoadError!);
      color = cs.error;
    } else if (_members.isEmpty) {
      message = local.noMemberListForSite;
    }

    if (message == null) return null;

    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowFilterRow() {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _workflowFilterTitle(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final _FileWorkflowFilter filter
                  in _FileWorkflowFilter.values)
                _buildWorkflowChoiceChip(filter, cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowChoiceChip(
    _FileWorkflowFilter filter,
    ColorScheme cs,
  ) {
    final bool selected = _workflowFilter == filter;
    final int badgeCount = _workflowFilterBadgeCount(filter);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ChoiceChip(
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          avatar: Icon(
            _workflowFilterIcon(filter),
            size: 16,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
          label: Text(_workflowFilterLabel(filter)),
          selectedColor: cs.primary.withValues(alpha: 0.14),
          backgroundColor: Colors.transparent,
          side: BorderSide(color: selected ? cs.primary : cs.outlineVariant),
          labelStyle: TextStyle(
            color: selected ? cs.primary : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          onSelected: (_) => _selectWorkflowFilter(filter),
        ),
        if (badgeCount > 0)
          Positioned(
            top: -6,
            right: -6,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.error,
                  shape: badgeCount > 9 ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius:
                      badgeCount > 9 ? BorderRadius.circular(999) : null,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  _formatCountBadge(badgeCount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWorkflowEmptyState() {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: [
            Icon(
              _workflowFilterIcon(_workflowFilter),
              size: 42,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _workflowEmptyMessage(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /*──────── 成員下拉選單 ────────*/
  Widget _buildUserDropdown({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    final bool enabled = _siteId != null && !_loadingMembers;

    return DropdownButton<int?>(
      isExpanded: true,
      value: value,
      items: [
        DropdownMenuItem<int?>(
            value: null,
            child: Text(AppLocalizations.of(context)!.allFilter(label))),
        ..._members.map(
          (u) => DropdownMenuItem<int?>(
            value: _memberId(u),
            child: Text(_memberDisplayName(u)),
          ),
        ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }

  /*──────── 列表 item ────────*/
  void _showMissingDocumentRouteRef() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文件缺少公開代碼，無法開啟連結')),
    );
  }

  void _goToDocumentPreview(String? docRef) {
    final normalized = docRef?.trim();
    if (normalized == null || normalized.isEmpty) {
      _showMissingDocumentRouteRef();
      return;
    }
    appPushOrGo(context, filePreviewLocation(docRef: normalized));
  }

  void _goToDocumentEdit(String? docRef) {
    final normalized = docRef?.trim();
    if (normalized == null || normalized.isEmpty) {
      _showMissingDocumentRouteRef();
      return;
    }
    context.go(fileEditLocation(docRef: normalized));
  }

  void _goToDocumentVersions(String? docRef) {
    final normalized = docRef?.trim();
    if (normalized == null || normalized.isEmpty) {
      _showMissingDocumentRouteRef();
      return;
    }
    appPushOrGo(context, fileVersionsLocation(docRef: normalized));
  }

  Widget _buildDesktopDocumentTable(List<dynamic> files, DateFormat fmt) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String countText =
        _total > 0 ? '${files.length} / $_total' : '${files.length}';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .72)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Text(
                  _copy('文件', 'Documents'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    countText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildDesktopDocumentHeader(),
          for (int i = 0; i < files.length; i += 1)
            _buildDesktopDocumentRow(
              files[i],
              fmt,
              isLast: i == files.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopDocumentHeader() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: .72)),
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .72)),
        ),
      ),
      child: Row(
        children: [
          _buildDesktopHeaderCell(_copy('文件名稱', 'Document'), flex: 5),
          _buildDesktopHeaderCell(_copy('工地', 'Site'), flex: 3),
          _buildDesktopHeaderCell(_copy('更新時間', 'Updated'), flex: 2),
          _buildDesktopHeaderCell(_workflowFilterTitle(), flex: 3),
          SizedBox(
            width: 52,
            child: Text(
              _copy('操作', 'Actions'),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeaderCell(String text, {required int flex}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildDesktopDocumentRow(
    dynamic rawFile,
    DateFormat fmt, {
    required bool isLast,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;
    final Map<dynamic, dynamic> file =
        rawFile is Map ? rawFile : const <dynamic, dynamic>{};
    final int? docId = _intFromValue(file['id']);
    final String? docRef = documentRouteRefFromMap(file);
    final String site =
        _stringFromValue(file['site_name']) ?? local.unclassified;
    final String code = _stringFromValue(file['full_file_code']) ?? '';
    final String docType = _stringFromValue(file['document_type_name']) ?? '';
    final String display = '$code $docType'.trim().isEmpty
        ? _copy('未命名文件', 'Untitled document')
        : '$code $docType'.trim();
    final bool isLocked = _boolFromValue(file['is_locked']);
    final String updatedStr =
        _stringFromValue(file['updated_at'] ?? file['created_at']) ?? '';
    final DateTime? updatedAt = DateTime.tryParse(updatedStr);
    final String dateText = updatedAt == null ? '—' : fmt.format(updatedAt);
    final _DocumentRevisionHint? revisionHint =
        docId == null ? null : _revisionHintsByDocumentId[docId];
    final List<_FileWorkflowBadge> workflowBadges =
        _workflowBadgesForFile(rawFile);

    return InkWell(
      onTap: () => _goToDocumentPreview(docRef),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(color: cs.outlineVariant.withValues(alpha: .55)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  if (isLocked) ...[
                    Tooltip(
                      message: local.documentLocked,
                      child: Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      display,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                site,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: _buildDesktopStatusCell(
                workflowBadges: workflowBadges,
                revisionHint: revisionHint,
              ),
            ),
            SizedBox(
              width: 52,
              child: Align(
                alignment: Alignment.center,
                child: _buildFileActionMenu(
                  docId: docId,
                  docRef: docRef,
                  isLocked: isLocked,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopStatusCell({
    required List<_FileWorkflowBadge> workflowBadges,
    required _DocumentRevisionHint? revisionHint,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    if (workflowBadges.isEmpty && revisionHint == null) {
      return Text(
        _copy('一般', 'Normal'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (workflowBadges.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final _FileWorkflowBadge badge in workflowBadges)
                _buildWorkflowBadge(badge),
            ],
          ),
        if (revisionHint != null) ...[
          if (workflowBadges.isNotEmpty) const SizedBox(height: 8),
          _buildRevisionHintBanner(revisionHint),
        ],
      ],
    );
  }

  Widget _buildFileActionMenu({
    required int? docId,
    required String? docRef,
    required bool isLocked,
  }) {
    final AppLocalizations local = AppLocalizations.of(context)!;

    return PopupMenuButton<String>(
      tooltip: _copy('更多操作', 'More actions'),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            _goToDocumentEdit(docRef);
            break;
          case 'versions':
            _goToDocumentVersions(docRef);
            break;
          case 'delete':
            if (docId != null) {
              unawaited(_deleteDoc(docId));
            }
            break;
        }
      },
      itemBuilder: (_) => [
        if (!isLocked)
          PopupMenuItem(
            value: 'edit',
            child: Text(local.edit),
          ),
        PopupMenuItem(
          value: 'versions',
          child: Text(local.versions),
        ),
        if (docId != null)
          PopupMenuItem(
            value: 'delete',
            child: Text(local.delete),
          ),
      ],
    );
  }

  Widget _buildItem(dynamic f, DateFormat fmt) {
    final docId = f['id'] as int;
    final docRef = f is Map ? documentRouteRefFromMap(f) : null;
    final site =
        f['site_name'] as String? ?? AppLocalizations.of(context)!.unclassified;
    final code = f['full_file_code'] ?? '';
    final docType = f['document_type_name'] ?? '';
    final display = '$code $docType'.trim();
    final isLocked = f['is_locked'] as bool? ?? false;

    final updatedStr = f['updated_at'] ?? f['created_at'] ?? '';
    final updatedAt = DateTime.tryParse(updatedStr);
    final dateText = updatedAt != null ? fmt.format(updatedAt) : '';
    final _DocumentRevisionHint? revisionHint =
        _revisionHintsByDocumentId[docId];
    final List<_FileWorkflowBadge> workflowBadges = _workflowBadgesForFile(f);
    final Widget? subtitle = (dateText.isEmpty && revisionHint == null)
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (dateText.isNotEmpty) Text(dateText),
              if (revisionHint != null) ...[
                if (dateText.isNotEmpty) const SizedBox(height: 8),
                _buildRevisionHintBanner(revisionHint),
              ],
            ],
          );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        isThreeLine: revisionHint != null || workflowBadges.isNotEmpty,
        onTap: () {
          _goToDocumentPreview(docRef);
        },
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('[$site] $display'),
            if (workflowBadges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final _FileWorkflowBadge badge in workflowBadges)
                    _buildWorkflowBadge(badge),
                ],
              ),
            ],
          ],
        ),
        subtitle: subtitle,
        leading: isLocked
            ? Tooltip(
                message: AppLocalizations.of(context)!.documentLocked,
                child: Icon(
                  Icons.lock,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: _buildFileActionMenu(
          docId: docId,
          docRef: docRef,
          isLocked: isLocked,
        ),
      ),
    );
  }

  List<_FileWorkflowBadge> _workflowBadgesForFile(dynamic file) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<_FileWorkflowBadge> badges = <_FileWorkflowBadge>[];

    if (_needsMySignature(file)) {
      badges.add(
        _FileWorkflowBadge(
          label: _workflowFilterLabel(_FileWorkflowFilter.pendingMine),
          icon: Icons.assignment_turned_in_outlined,
          color: cs.primary,
        ),
      );
    }
    if (_wasReturnedOrRejected(file)) {
      badges.add(
        _FileWorkflowBadge(
          label: _workflowFilterLabel(_FileWorkflowFilter.rejected),
          icon: Icons.assignment_return_outlined,
          color: cs.error,
        ),
      );
    }
    if (_isFileLocked(file)) {
      badges.add(
        _FileWorkflowBadge(
          label: _workflowFilterLabel(_FileWorkflowFilter.locked),
          icon: Icons.lock_outline,
          color: cs.onSurfaceVariant,
        ),
      );
    }
    if (_isRecentlyEdited(file)) {
      badges.add(
        _FileWorkflowBadge(
          label: _workflowFilterLabel(_FileWorkflowFilter.recent),
          icon: Icons.update_outlined,
          color: cs.tertiary,
        ),
      );
    }

    return badges;
  }

  Widget _buildWorkflowBadge(_FileWorkflowBadge badge) {
    final Color background = badge.color.withValues(alpha: 0.12);
    final Color border = badge.color.withValues(alpha: 0.36);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 14, color: badge.color),
          const SizedBox(width: 4),
          Text(
            badge.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: badge.color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevisionHintBanner(_DocumentRevisionHint hint) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isRejected =
        normalizeSignatureTaskStatus(hint.status) == 'rejected';
    final Color backgroundColor =
        isRejected ? cs.errorContainer : cs.tertiaryContainer;
    final Color foregroundColor =
        isRejected ? cs.onErrorContainer : cs.onTertiaryContainer;
    final IconData icon =
        isRejected ? Icons.error_outline : Icons.feedback_outlined;
    final String signerCommentText = hint.signerName.isNotEmpty
        ? '${hint.signerName} ${local.commentLabel(hint.comment)}'
        : local.commentLabel(hint.comment);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${signatureTaskStatusLabel(hint.status, local)}  ',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  TextSpan(
                    text: signerCommentText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: foregroundColor,
                          height: 1.3,
                        ),
                  ),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMySignTasks() async {
    await pushAppPage<void>(
      context,
      builder: (_) => const MyTasksPage(),
    );
    if (!mounted) return;
    await _refreshPendingSignTaskCount();
    if (!mounted) return;
    _scheduleRevisionHintLoad(_files, reset: true);
  }

  /*──────── 簽核任務入口（含紅點） ────────*/
  Widget _buildSignTaskAction() {
    final cs = Theme.of(context).colorScheme;
    final local = AppLocalizations.of(context)!;
    final bool compact = MediaQuery.sizeOf(context).width < 640;
    final countText = _formatCountBadge(_pendingSignTaskCount);

    final Widget action = compact
        ? IconButton(
            tooltip: local.mySignTasks,
            icon: const Icon(Icons.assignment_turned_in_outlined),
            onPressed: _openMySignTasks,
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Tooltip(
              message: local.mySignTasks,
              child: TextButton.icon(
                onPressed: _openMySignTasks,
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 20),
                label: Text(
                  local.mySignTasks,
                  overflow: TextOverflow.ellipsis,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        action,
        if (_pendingSignTaskCount > 0)
          Positioned(
            top: compact ? 6 : 4,
            right: compact ? 6 : 2,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.error,
                  shape: _pendingSignTaskCount > 9
                      ? BoxShape.rectangle
                      : BoxShape.circle,
                  borderRadius: _pendingSignTaskCount > 9
                      ? BorderRadius.circular(999)
                      : null,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  countText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /*──────── 直接使用 bottom-sheet 選類型 ────────*/
  Future<void> _showChooseTypeSheet() async {
    final sel = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ChooseDocTypeSheet(),
    );
    if (sel == null) return;
    if (!mounted) return;

    final typeName = sel['type']['type_name'] as String;
    final filePrefix = sel['type']['file_prefix'] as String? ?? '';

    if (typeName == '圖片表格列') {
      // 先選站點
      final site = await _pickSiteDialog();
      if (site == null) return;
      final siteObj = site['site'];
      if (!mounted) return;
      final ok = await pushAppPage<bool>(
        context,
        builder: (_) => PhotoDocCreatePage(initSite: siteObj),
      );
      if (!mounted) return;
      if (ok == true) _fetchFiles(initial: true);
    } else if (typeName == '缺失稽核改善') {
      final site = await _pickSiteDialog();
      if (site == null) return;
      final siteObj = site['site'];
      if (!mounted) return;
      final ok = await pushAppPage<bool>(
        context,
        builder: (_) => AuditFixDocCreatePage(initSite: siteObj),
      );
      if (!mounted) return;
      if (ok == true) _fetchFiles(initial: true);
    } else {
      // 其餘類型 → 進入 bundle 建立頁
      if (filePrefix.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.fileTypeNotConfigured)),
        );
        return;
      }

      final site = await _pickSiteDialog();
      if (site == null) return;
      final dynamic siteObj = site['site'];
      if (!mounted) return;
      await pushAppPage<void>(
        context,
        builder: (_) => FileBundleCreatePage(
          site: Map<String, dynamic>.from(siteObj as Map),
          documentTypeName: typeName,
          filePrefix: filePrefix,
        ),
      );
      if (!mounted) return;
      _fetchFiles(initial: true);
    }
  }

  /*──────── 日期選擇 ────────*/
  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startTime : _endTime) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      if (isStart) {
        _startTime = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
      } else {
        _endTime = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
    unawaited(_applyFilters());
  }
}
