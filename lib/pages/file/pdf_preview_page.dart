// lib/pages/pdf_preview_page.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/document_draft_remote_store.dart';
import '../../services/document_draft_service.dart';
import '../../services/file_manage_api_service.dart';
import '../../widgets/pdf_page_image_view.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/web_selectable_content.dart';
import '../../utils/auth_utils.dart';
import '../../utils/app_navigation.dart';
import '../../utils/file_routes.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/signature_task_status.dart';
import '../../utils/user_display_name.dart';

class PdfPreviewPage extends StatefulWidget {
  const PdfPreviewPage({
    super.key,
    required this.docId,
    required this.docRef,
    this.docName,
    this.initialVersionId,
    this.autoDownload,
  });

  final int docId;
  final String docRef;
  final String? docName;
  final int? initialVersionId;
  final String? autoDownload;

  @override
  State<PdfPreviewPage> createState() => _PdfPreviewPageState();
}

class _PdfPreviewPageState extends State<PdfPreviewPage> {
  static const Duration _pendingPdfRetryInterval = Duration(seconds: 2);

  bool _loading = true;
  String? _error;
  bool _waitingForPdf = false;
  PdfDocument? _pdfDocument;
  int _pagesCount = 0;
  int _currentPage = 0;
  late final PageController _pageController;
  Timer? _pendingPdfTimer;
  Map<String, dynamic>? _docInfo;
  Map<String, dynamic>? _activeVersion;
  bool _didAutoDownload = false;
  // Sorted actionable signer comments.
  List<_RevisionHint> _revisionHints = const <_RevisionHint>[];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(() {
      final int page = (_pageController.page ?? 0).round();
      if (page != _currentPage && mounted) {
        setState(() => _currentPage = page);
      }
    });
    _preparePdf();
  }

  @override
  void didUpdateWidget(covariant PdfPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool shouldReload = oldWidget.docId != widget.docId ||
        oldWidget.initialVersionId != widget.initialVersionId ||
        oldWidget.autoDownload != widget.autoDownload;
    if (!shouldReload) return;

    _cancelPendingPdfPolling();
    _didAutoDownload = false;
    _preparePdf();
  }

  void _cancelPendingPdfPolling() {
    _pendingPdfTimer?.cancel();
    _pendingPdfTimer = null;
  }

  void _schedulePendingPdfPolling() {
    _cancelPendingPdfPolling();
    if (!mounted) {
      return;
    }

    _pendingPdfTimer = Timer(_pendingPdfRetryInterval, () {
      if (!mounted) return;
      _preparePdf(preservePendingState: true);
    });
  }

  void _setPendingPdfState({
    required Map<String, dynamic> docInfo,
    required Map<String, dynamic>? activeVersion,
  }) {
    _pdfDocument?.close();
    _pdfDocument = null;
    if (!mounted) return;

    setState(() {
      _docInfo = docInfo;
      _activeVersion = activeVersion;
      _pagesCount = 0;
      _currentPage = 0;
      _loading = false;
      _waitingForPdf = true;
      _error = null;
    });
    _schedulePendingPdfPolling();
  }

  Future<void> _preparePdf({bool preservePendingState = false}) async {
    _cancelPendingPdfPolling();
    if (mounted) {
      setState(() {
        _loading = !preservePendingState;
        _error = null;
        _waitingForPdf = preservePendingState;
        if (!preservePendingState) {
          _activeVersion = null;
        }
        _revisionHints = const <_RevisionHint>[];
      });
    }

    try {
      final docInfo = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getFileById(
          token: token,
          fileId: widget.docId,
        ),
      );
      final Map<String, dynamic>? latestVersion =
          _asVersionMap(docInfo['latest_version']);
      _docInfo = docInfo;

      final Map<String, dynamic>? previewVersion =
          await _resolvePreviewVersion(latestVersion);
      final Map<String, dynamic>? activeVersion =
          previewVersion ?? latestVersion;

      if (widget.initialVersionId != null && activeVersion == null) {
        _cancelPendingPdfPolling();
        setState(() {
          _error = AppLocalizations.of(context)!
              .loadFailedError('Requested version not found');
          _waitingForPdf = false;
          _loading = false;
        });
        return;
      }

      if (activeVersion == null || activeVersion['pdf_path'] == null) {
        _setPendingPdfState(docInfo: docInfo, activeVersion: activeVersion);
        return;
      }

      if (!mounted) return;
      final url = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.generateTempUrl(
          token: token,
          versionId: _versionId(activeVersion)!,
          kind: 'pdf',
        ),
      );

      final bytes = await _downloadPdfBytes(url);

      final document = await PdfDocument.openData(bytes);
      _cancelPendingPdfPolling();
      _pdfDocument?.close();
      setState(() {
        _docInfo = docInfo;
        _activeVersion = activeVersion;
        _pdfDocument = document;
        _pagesCount = document.pagesCount;
        _currentPage = 0;
        _loading = false;
        _waitingForPdf = false;
        _error = null;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      // Load signer comments in the background after PDF is ready.
      final int? vid = _versionId(activeVersion);
      if (vid != null) _loadRevisionHints(vid);
      if (!_didAutoDownload) _maybeAutoDownload(activeVersion);
    } catch (e) {
      if (!mounted) return;
      _cancelPendingPdfPolling();
      // If the document no longer exists (deleted or never committed), redirect
      // to the file list gracefully instead of showing a dead error screen.
      if (e is FileManageApiException && e.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件已不存在，已跳回列表')),
        );
        context.go('/files');
        return;
      }
      setState(() {
        _error = AppLocalizations.of(context)!.loadFailedError(e.toString());
        _loading = false;
        _waitingForPdf = false;
      });
    }
  }

  Future<Uint8List> _downloadPdfBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Map<String, dynamic>? _asVersionMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  int? _versionId(Map<String, dynamic>? version) {
    return (version?['id'] as num?)?.toInt();
  }

  Future<Map<String, dynamic>?> _resolvePreviewVersion(
    Map<String, dynamic>? latestVersion,
  ) async {
    final int? requestedVersionId = widget.initialVersionId;
    if (requestedVersionId == null) {
      return latestVersion;
    }
    if (_versionId(latestVersion) == requestedVersionId) {
      return latestVersion;
    }

    final List<dynamic> versions = await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.getDocumentVersions(
        token: token,
        docId: widget.docId,
      ),
    );

    for (final dynamic version in versions) {
      final Map<String, dynamic>? versionMap = _asVersionMap(version);
      if (_versionId(versionMap) == requestedVersionId) {
        return versionMap;
      }
    }
    return null;
  }

  String _pageTitle(AppLocalizations l) {
    final String docCode =
        (_docInfo?['full_file_code'] as String? ?? '').trim();
    final String docType =
        (_docInfo?['document_type_name'] as String? ?? '').trim();
    final String resolvedTitle = '$docCode $docType'.trim();
    if (resolvedTitle.isNotEmpty) {
      return resolvedTitle;
    }

    final String initialTitle = (widget.docName ?? '').trim();
    if (initialTitle.isNotEmpty) {
      return initialTitle;
    }

    return l.documentListTitle;
  }

  Future<void> _maybeAutoDownload(Map<String, dynamic> version) async {
    final String? kind = widget.autoDownload;
    final int? versionId = _versionId(version);
    if (_didAutoDownload || kind == null || versionId == null) {
      return;
    }

    _didAutoDownload = true;
    if (kind == 'pdf' && version['pdf_path'] == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pdfNotReady)),
      );
      return;
    }

    try {
      final String url = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.generateTempUrl(
          token: token,
          versionId: versionId,
          kind: kind,
        ),
      );
      if (!mounted) return;

      final bool launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!mounted) return;
      if (!launched) {
        throw Exception('Unable to launch download');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            foundation.kIsWeb
                ? AppLocalizations.of(context)!.browserDownloadStarted
                : AppLocalizations.of(context)!.downloadComplete,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.downloadFailedError(e.toString()),
          ),
        ),
      );
    }
  }

  bool get _isLocked => _docInfo?['is_locked'] as bool? ?? false;

  // ── Bundle export ──────────────────────────────────────────────────────────

  bool _exportingBundle = false;
  String? _exportStatus;

  Future<void> _exportBundle(String kind) async {
    if (_exportingBundle) return;
    setState(() {
      _exportingBundle = true;
      _exportStatus = '建立整包 ${kind.toUpperCase()} 工作中...';
    });

    try {
      final int? latestVersionId =
          (_docInfo?['latest_version_id'] as num?)?.toInt() ??
              (_versionId(_activeVersion));

      final Map<String, dynamic> job = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.createFileExportJob(
          token: token,
          fileId: widget.docId,
          payload: <String, dynamic>{
            'output_kind': kind,
            'include_linked_children': true,
            if (latestVersionId != null) 'main_version_id': latestVersionId,
          },
        ),
      );
      final int jobId = (job['job_id'] as num).toInt();

      while (mounted) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final Map<String, dynamic> currentJob = await AuthUtils.withAuthRetry(
          context,
          (token) => FileManageAPIService.getExportJob(
            token: token,
            jobId: jobId,
          ),
        );
        final String status =
            (currentJob['status'] as String? ?? '').trim().toLowerCase();
        if (!mounted) return;
        setState(() {
          _exportStatus = switch (status) {
            'pending' => '排隊中...',
            'processing' => '整包檔案產生中...',
            'completed' => '完成，準備下載...',
            'failed' => currentJob['error_message'] as String? ?? '匯出失敗',
            _ => '狀態：$status',
          };
        });
        if (status == 'completed') {
          final String url = await AuthUtils.withAuthRetry(
            context,
            (token) => FileManageAPIService.generateExportTempUrl(
              token: token,
              jobId: jobId,
            ),
          );
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('匯出完成，已開啟下載')),
            );
          }
          break;
        }
        if (status == 'failed') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_exportStatus ?? '匯出失敗')),
            );
          }
          break;
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯出失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _exportingBundle = false);
    }
  }

  Future<void> _loadRevisionHints(int versionId) async {
    try {
      final MapEntry<List<Map<String, dynamic>>, Map<int, Map<String, dynamic>>>
          revisionData = await AuthUtils.withAuthRetry(
        context,
        (token) async {
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
          return MapEntry<List<Map<String, dynamic>>,
              Map<int, Map<String, dynamic>>>(assignments, signerLookup);
        },
      );
      if (!mounted) return;
      setState(
        () => _revisionHints = _pickHints(
          revisionData.key,
          signerLookup: revisionData.value,
        ),
      );
    } catch (_) {
      // Non-critical — ignore silently.
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
          '[PdfPreviewPage] Failed to load revision signer lookup '
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
      final int? signerId = _intFromValue(signer['id'] ?? signer['user_id']);
      if (signerId == null) continue;
      lookup[signerId] = signer;
    }
    return lookup;
  }

  List<_RevisionHint> _pickHints(
    List<Map<String, dynamic>> assignments, {
    Map<int, Map<String, dynamic>> signerLookup =
        const <int, Map<String, dynamic>>{},
  }) {
    final candidates = assignments.where((t) {
      final status = normalizeSignatureTaskStatus(t['status'] as String?);
      final comment = (t['comment'] as String? ?? '').trim();
      return signatureTaskStatusRequiresComment(status) && comment.isNotEmpty;
    }).toList()
      ..sort((a, b) {
        final int pa = _hintPriority(a['status'] as String?);
        final int pb = _hintPriority(b['status'] as String?);
        if (pa != pb) return pa.compareTo(pb);
        final DateTime? da =
            DateTime.tryParse(a['updated_at'] as String? ?? '');
        final DateTime? db =
            DateTime.tryParse(b['updated_at'] as String? ?? '');
        if (da != null && db != null) return db.compareTo(da);
        return 0;
      });

    return candidates.map((best) {
      return _RevisionHint(
        status: normalizeSignatureTaskStatus(best['status'] as String?),
        comment: (best['comment'] as String? ?? '').trim(),
        signerName: _signerDisplayName(best, signerLookup: signerLookup),
      );
    }).toList(growable: false);
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

  int? _intFromValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _debugMissingRevisionSignerName(
    Map<String, dynamic> assignment,
    Map<String, dynamic>? signer,
  ) {
    if (!foundation.kDebugMode) return;
    foundation.debugPrint(
      '[PdfPreviewPage] Missing revision signer display name. '
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

  int _hintPriority(String? status) {
    switch (normalizeSignatureTaskStatus(status)) {
      case 'rejected':
        return 0;
      case 'commented':
        return 1;
      default:
        return 2;
    }
  }

  void _closePreview() {
    appBackOrGo(context, '/files');
  }

  Future<void> _handleAction(String value) async {
    switch (value) {
      case 'edit':
        await _openEditPage();
        break;
      case 'versions':
        await _openVersionsPage();
        break;
      case 'export_docx':
        await _exportBundle('docx');
        break;
      case 'export_pdf':
        await _exportBundle('pdf');
        break;
      case 'delete':
        await _deleteDocument();
        break;
    }
  }

  Future<void> _openEditPage() async {
    context.go(
      fileEditLocation(
        docRef: widget.docRef,
      ),
    );
  }

  Future<void> _openVersionsPage() async {
    appPushOrGo(
      context,
      fileVersionsLocation(
        docRef: widget.docRef,
      ),
    );
  }

  Future<void> _deleteDocument() async {
    final AppLocalizations l = AppLocalizations.of(context)!;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.confirmDeleteFile),
        content: Text(l.confirmDeleteFileMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final auth = context.read<UnifiedAuthProvider>();
    final draftRemoteStore = DocumentDraftRemoteStore(auth: auth);

    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.deleteDocument(
            token: token, docId: widget.docId),
      );
      await DocumentDraftService.deleteFileDrafts(
        userId: auth.userId,
        fileId: widget.docId,
        remoteDeleter: draftRemoteStore.delete,
        waitForRemote: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.fileDeleted)),
      );
      context.go(fileListLocation());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.deleteFailed}：$e')),
      );
    }
  }

  List<Widget>? _buildActions() {
    if (_docInfo == null) return null;

    return <Widget>[
      if (_exportingBundle)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      PopupMenuButton<String>(
        onSelected: _handleAction,
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          if (!_isLocked)
            PopupMenuItem<String>(
              value: 'edit',
              child: Text(AppLocalizations.of(context)!.edit),
            ),
          PopupMenuItem<String>(
            value: 'versions',
            child: Text(AppLocalizations.of(context)!.versions),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'export_docx',
            enabled: !_exportingBundle,
            child: const Text('整包匯出 DOCX'),
          ),
          PopupMenuItem<String>(
            value: 'export_pdf',
            enabled: !_exportingBundle,
            child: const Text('整包匯出 PDF'),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    ];
  }

  @override
  void dispose() {
    _cancelPendingPdfPolling();
    _pageController.dispose();
    _pdfDocument?.close();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, dynamic result) {
              if (didPop) return;
              _closePreview();
            },
            child: _buildWideLayout(context),
          );
        }
        return _buildNarrowLayout(context);
      },
    );
  }

  /// Narrow layout (< 800 px): full-screen PDF + popup menu in AppBar.
  Widget _buildNarrowLayout(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context)!;
    final Widget bodyContent = _revisionHints.isNotEmpty
        ? Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _buildRevisionCard(context, _revisionHints),
              ),
              Expanded(child: _buildBody()),
            ],
          )
        : _buildBody();
    return ResponsiveScaffold(
      title: _pageTitle(l),
      isFullscreen: true,
      onBackPressed: _closePreview,
      actions: _buildActions(),
      body: bodyContent,
    );
  }

  /// Wide layout (≥ 800 px): PDF viewer on the left, action sidebar on the right.
  Widget _buildWideLayout(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle(l)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closePreview,
        ),
      ),
      body: WebSelectableContent(
        child: Row(
          children: [
            Expanded(child: _buildBody()),
            _buildSidebar(context),
          ],
        ),
      ),
    );
  }

  /// Shared body: loading / error / PDF viewer with page indicator.
  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_waitingForPdf) return _buildPendingPdfState();
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    return Stack(
      children: [
        _buildPdfViewer(),
        if (_pagesCount > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(child: _buildPageChip()),
          ),
      ],
    );
  }

  Widget _buildPendingPdfState() {
    final AppLocalizations l = AppLocalizations.of(context)!;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
    final Map<String, dynamic>? activeVersion =
        _activeVersion ?? _asVersionMap(_docInfo?['latest_version']);
    final String versionNum = activeVersion?['version_num']?.toString() ?? '';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l.pdfNotReady,
                textAlign: TextAlign.center,
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.loading,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (versionNum.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l.versionNumber(versionNum),
                    style: tt.labelLarge?.copyWith(color: cs.onSurface),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${_currentPage + 1} / $_pagesCount',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      padEnds: false,
      itemCount: _pagesCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.0),
        child: PdfPageImageView(
          pdfDocument: _pdfDocument!,
          pageNumber: index + 1,
          renderBackgroundColor: '#FFFFFF',
          wrapInCenter: true,
        ),
      ),
    );
  }

  // ── Wide-screen sidebar ────────────────────────────────────────────────────

  Widget _buildSidebar(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(left: BorderSide(color: cs.outlineVariant)),
      ),
      child: _docInfo == null
          ? const Center(child: CircularProgressIndicator())
          : _buildSidebarContent(context),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required Widget child,
    Color? color,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: color ?? cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    );
  }

  Widget _buildRevisionCard(BuildContext context, List<_RevisionHint> hints) {
    final AppLocalizations l = AppLocalizations.of(context)!;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
    return _buildSectionCard(
      context: context,
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int index = 0; index < hints.length; index++) ...[
            if (index > 0) const Divider(height: 16),
            _buildRevisionRow(
              context,
              hints[index],
              tt,
              l,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRevisionRow(
    BuildContext context,
    _RevisionHint hint,
    TextTheme tt,
    AppLocalizations l,
  ) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isRejected = hint.status == 'rejected';
    final Color pillBg = isRejected ? cs.errorContainer : cs.tertiaryContainer;
    final Color pillFg =
        isRejected ? cs.onErrorContainer : cs.onTertiaryContainer;
    final String commentText = hint.signerName.isNotEmpty
        ? '${hint.signerName} ${l.commentLabel(hint.comment)}'
        : l.commentLabel(hint.comment);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            signatureTaskStatusLabel(hint.status, l),
            style: tt.labelSmall?.copyWith(
              color: pillFg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            commentText,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarContent(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context)!;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;

    // ── Extract doc info ──────────────────────────────────────────────────
    final String docCode = _docInfo?['full_file_code'] as String? ?? '';
    final String docType = _docInfo?['document_type_name'] as String? ?? '';
    final String site = _docInfo?['site_name'] as String? ?? '';
    final Map<String, dynamic>? activeVersion =
        _activeVersion ?? _asVersionMap(_docInfo?['latest_version']);
    final String versionNum = activeVersion?['version_num']?.toString() ?? '';
    final String creator = _firstNonEmpty([
      _docInfo?['creator_name'],
      _docInfo?['creator_username'],
    ]);
    final String updatedStr = _firstNonEmpty([
      activeVersion?['updated_at'],
      activeVersion?['created_at'],
      _docInfo?['updated_at'],
      _docInfo?['created_at'],
    ]);
    final DateTime? updatedAt = DateTime.tryParse(updatedStr);
    final String dateText = updatedAt != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(updatedAt)
        : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Document header ───────────────────────────────────────────
          if (docCode.isNotEmpty)
            Text(
              docCode,
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          if (docCode.isNotEmpty) const SizedBox(height: 4),
          Row(
            children: [
              if (docType.isNotEmpty)
                Expanded(
                  child: Text(
                    docType,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              if (_isLocked)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 12, color: cs.onErrorContainer),
                      const SizedBox(width: 4),
                      Text(
                        l.documentLocked,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Info card ─────────────────────────────────────────────────
          _buildSectionCard(
            context: context,
            color: cs.surfaceContainerLow,
            child: Column(
              children: [
                if (site.isNotEmpty)
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: l.site,
                    value: site,
                  ),
                if (versionNum.isNotEmpty) ...[
                  if (site.isNotEmpty) const Divider(height: 16, indent: 28),
                  _InfoRow(
                    icon: Icons.bookmark_outline,
                    label: '',
                    value: l.versionNumber(versionNum),
                  ),
                ],
                if (creator.isNotEmpty) ...[
                  const Divider(height: 16, indent: 28),
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: l.creatorLabel,
                    value: creator,
                  ),
                ],
                if (dateText.isNotEmpty) ...[
                  const Divider(height: 16, indent: 28),
                  _InfoRow(
                    icon: Icons.schedule_outlined,
                    label: l.lastUpdated,
                    value: dateText,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Revision hint (signer comment) ────────────────────────────
          if (_revisionHints.isNotEmpty) ...[
            _buildRevisionCard(context, _revisionHints),
            const SizedBox(height: 16),
          ],

          // ── Action buttons ────────────────────────────────────────────
          if (!_isLocked) ...[
            FilledButton.icon(
              onPressed: _openEditPage,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l.edit),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _openVersionsPage,
            icon: const Icon(Icons.history, size: 18),
            label: Text(l.versions),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _deleteDocument,
            icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
            label: Text(l.delete),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the first non-empty string from a list of nullable values.
  String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }
}

// ── Data class ─────────────────────────────────────────────────────────────

class _RevisionHint {
  const _RevisionHint({
    required this.status,
    required this.comment,
    required this.signerName,
  });

  final String status;
  final String comment;
  final String signerName;
}

// ── Helper widget ──────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Text(
                  label,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              if (label.isNotEmpty) const SizedBox(height: 1),
              Text(
                value,
                style: tt.bodyMedium?.copyWith(color: cs.onSurface),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
