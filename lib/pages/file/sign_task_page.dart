// lib/pages/sign_task_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:signature/signature.dart';

import '../../services/file_manage_api_service.dart';
import '../../theme/app_motion.dart';
import '../../widgets/pdf_page_image_view.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../utils/auth_utils.dart';
import '../../utils/signature_task_status.dart';
import '../../l10n/app_localizations.dart';

class SignTaskPage extends StatefulWidget {
  const SignTaskPage({
    super.key,
    required this.taskId,
    required this.versionId,
    required this.documentId,
    required this.initialStatus, // 'pending' | 'commented' | 'rejected' | 'skipped'
    required this.initialComment,
  });

  final int taskId;
  final int versionId;
  final int documentId;
  final String initialStatus;
  final String initialComment;

  @override
  State<SignTaskPage> createState() => _SignTaskPageState();
}

class _SignTaskPageState extends State<SignTaskPage> {
  /* ───── PDF 狀態 ───── */
  bool _loadingPdf = true;
  String? _pdfError;
  PdfDocument? _pdfDoc;
  int _pagesCount = 0;
  int _currentPage = 0;
  late final PageController _pageController;

  /* ───── 簽名 / 留言 / 狀態 ───── */
  late final SignatureController _sigCtrl;
  Uint8List? _signedPng;
  final TextEditingController _commentCtrl = TextEditingController();
  late String _selectedStatus;
  late int _taskId;
  late int _versionId;
  bool _submitting = false;

  bool get _needSign => signatureTaskStatusRequiresSignature(_selectedStatus);
  bool get _needComment => signatureTaskStatusRequiresComment(_selectedStatus);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _sigCtrl = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
    _taskId = widget.taskId;
    _versionId = widget.versionId;
    final String initialStatus =
        normalizeSignatureTaskStatus(widget.initialStatus);
    _selectedStatus = initialStatus == 'pending' ? 'signed' : initialStatus;
    _commentCtrl.text = widget.initialComment;
    _loadTaskAndPdf();
  }

  int _taskVersion(Map<String, dynamic> task) {
    return (task['version_id'] as num?)?.toInt() ?? 0;
  }

  int _taskIdentifier(Map<String, dynamic> task) {
    return (task['task_id'] as num?)?.toInt() ?? 0;
  }

  String _taskStatus(Map<String, dynamic> task) {
    return normalizeSignatureTaskStatus(task['status'] as String?);
  }

  bool _isActiveTask(Map<String, dynamic> task) {
    return isActionableSignatureTaskStatus(_taskStatus(task));
  }

  Map<String, dynamic>? _pickLatestTaskForDocument(
    List<Map<String, dynamic>> tasks,
  ) {
    final List<Map<String, dynamic>> candidates = tasks.where((task) {
      final int? taskDocumentId = (task['document_id'] as num?)?.toInt();
      return taskDocumentId == widget.documentId && _isActiveTask(task);
    }).toList()
      ..sort((a, b) {
        final int byVersion = _taskVersion(b).compareTo(_taskVersion(a));
        if (byVersion != 0) {
          return byVersion;
        }
        return _taskIdentifier(b).compareTo(_taskIdentifier(a));
      });

    return candidates.isEmpty ? null : candidates.first;
  }

  Future<bool> _refreshActiveTask() async {
    final int previousTaskId = _taskId;
    final int previousVersionId = _versionId;

    final List<Map<String, dynamic>> tasks = await AuthUtils.withAuthRetry(
      context,
      (token) => FileManageAPIService.getMySignTasks(token: token),
    );
    final Map<String, dynamic>? latestTask = _pickLatestTaskForDocument(tasks);
    if (latestTask == null) {
      return false;
    }

    final int nextTaskId = _taskIdentifier(latestTask);
    final int nextVersionId = _taskVersion(latestTask);
    final bool changed =
        nextTaskId != previousTaskId || nextVersionId != previousVersionId;

    _taskId = nextTaskId;
    _versionId = nextVersionId;
    return changed;
  }

  Future<void> _loadTaskAndPdf() async {
    setState(() {
      _loadingPdf = true;
      _pdfError = null;
    });

    try {
      await _refreshActiveTask();
      await _loadPdf();
    } catch (e) {
      if (!mounted) return;
      final String msg =
          AppLocalizations.of(context)!.signTaskLoadFailed(e.toString());
      setState(() {
        _pdfError = msg;
        _loadingPdf = false;
      });
    }
  }

  /* ═══ 1. 下載並開啟 PDF ═══════════════════ */
  Future<void> _loadPdf() async {
    try {
      if (!mounted) return;
      final url = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.generateTempUrl(
          token: token,
          versionId: _versionId,
          kind: 'pdf',
        ),
      );

      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final doc = await PdfDocument.openData(resp.bodyBytes);

      setState(() {
        _pdfDoc = doc;
        _pagesCount = doc.pagesCount;
        _loadingPdf = false;
      });
    } catch (e) {
      if (!mounted) return;
      final String msg =
          AppLocalizations.of(context)!.pdfLoadFailed(e.toString());
      setState(() {
        _pdfError = msg;
        _loadingPdf = false;
      });
    }
  }

  /* ═══ 2. 確認簽名 → 畫布轉 png ════════════════ */
  Future<void> _captureSignature(StateSetter setSheetState) async {
    if (_sigCtrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.signatureHint)),
      );
      return;
    }
    final png = await _sigCtrl.toPngBytes();
    setState(() => _signedPng = png);
    setSheetState(() {});
  }

  /* ═══ 3. 提交 ══════════════════════════════ */
  Future<void> _submit(StateSetter setSheetState) async {
    final AppLocalizations l = AppLocalizations.of(context)!;
    final String trimmedComment = _commentCtrl.text.trim();
    if (_needSign && _signedPng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.pleaseSignFirst)),
      );
      return;
    }

    if (_needComment && trimmedComment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.commentRequired)),
      );
      return;
    }

    setState(() => _submitting = true);
    setSheetState(() {});

    try {
      final bool taskChanged = await _refreshActiveTask();
      if (taskChanged) {
        _sigCtrl.clear();
        _signedPng = null;
        _selectedStatus = 'signed';
        _commentCtrl.clear();
        await _loadPdf();
        if (!mounted) return;
        final NavigatorState navigator = Navigator.of(context);
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(l.documentVersionUpdated),
          ),
        );
        setState(() => _submitting = false);
        return;
      }

      if (!mounted) return;
      final res = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.submitSignature(
          token: token,
          taskId: _taskId,
          status: _selectedStatus,
          pngBytes: _needSign ? _signedPng : null,
          comment: _needComment ? trimmedComment : '',
        ),
      );

      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      final ColorScheme colors = Theme.of(context).colorScheme;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res['message'] as String? ?? l.submitted,
            style: TextStyle(color: colors.onSecondary),
          ),
          backgroundColor: colors.secondary,
        ),
      );
      if (navigator.canPop()) {
        navigator.pop(true);
        return;
      }
      final GoRouter goRouter = GoRouter.of(context);
      goRouter.go('/files');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      setSheetState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context)!.submitFailed(e.toString()))));
    }
  }

  ({String label, String hint, bool required})? _commentFieldConfig(
    AppLocalizations l,
  ) {
    switch (normalizeSignatureTaskStatus(_selectedStatus)) {
      case 'commented':
        return (
          label: l.revisionCommentLabel,
          hint: l.revisionCommentHint,
          required: true,
        );
      case 'rejected':
        return (
          label: l.rejectionReasonLabel,
          hint: l.rejectionReasonHint,
          required: true,
        );
      default:
        return null;
    }
  }

  /* ═══ 4. 開啟簽署底部彈出面板 ══════════════════ */
  void _openSignSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (_, setSheetState) {
          final cs = Theme.of(context).colorScheme;
          final l = AppLocalizations.of(context)!;
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          final commentField = _commentFieldConfig(l);
          final List<
              ({
                String value,
                IconData icon,
                String label,
                String description,
                Color bg,
                Color fg,
              })> statusOptions = <({
            String value,
            IconData icon,
            String label,
            String description,
            Color bg,
            Color fg,
          })>[
            (
              value: 'signed',
              icon: Icons.draw_outlined,
              label: l.signAction,
              description: l.signedStatusDescription,
              bg: cs.primaryContainer,
              fg: cs.onPrimaryContainer,
            ),
            (
              value: 'commented',
              icon: Icons.mode_comment_outlined,
              label: l.commentAction,
              description: l.commentedStatusDescription,
              bg: cs.tertiaryContainer,
              fg: cs.onTertiaryContainer,
            ),
            (
              value: 'skipped',
              icon: Icons.skip_next_outlined,
              label: l.skipAction,
              description: l.skippedStatusDescription,
              bg: cs.secondaryContainer,
              fg: cs.onSecondaryContainer,
            ),
            (
              value: 'rejected',
              icon: Icons.cancel_outlined,
              label: l.rejectAction,
              description: l.rejectedStatusDescription,
              bg: cs.errorContainer,
              fg: cs.onErrorContainer,
            ),
          ];
          final currentSelection = statusOptions.firstWhere(
            (option) => option.value == _selectedStatus,
            orElse: () => statusOptions.first,
          );
          final String? commentLabel = commentField == null
              ? null
              : commentField.required
                  ? '${commentField.label} *'
                  : commentField.label;

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /* ── 拖曳把手 ── */
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.signDocument,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: currentSelection.bg.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color:
                                  currentSelection.fg.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(currentSelection.icon,
                                color: currentSelection.fg),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentSelection.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: currentSelection.fg,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  currentSelection.description,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: currentSelection.fg
                                            .withValues(alpha: 0.9),
                                        height: 1.35,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    /* ── 簽署結果選擇 ── */
                    Text(
                      l.signResult,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                        const double spacing = 12;
                        final double itemWidth =
                            (constraints.maxWidth - spacing) / 2;

                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: statusOptions.map((option) {
                            final bool selected =
                                option.value == _selectedStatus;
                            return SizedBox(
                              width: itemWidth,
                              child: _StatusOptionCard(
                                icon: option.icon,
                                label: option.label,
                                description: option.description,
                                selected: selected,
                                backgroundColor: option.bg,
                                foregroundColor: option.fg,
                                onTap: () {
                                  setState(() {
                                    _selectedStatus = option.value;
                                    if (!_needSign) {
                                      _sigCtrl.clear();
                                      _signedPng = null;
                                    }
                                  });
                                  setSheetState(() {});
                                },
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),

                    /* ── 簽名區（僅 signed 時顯示） ── */
                    AnimatedSize(
                      duration: AppMotion.maybeZero(context, AppMotion.sheet),
                      curve: AppMotion.standardCurve,
                      child: _needSign
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 20),
                                Text(
                                  l.handwrittenSignature,
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant, fontSize: 13),
                                ),
                                const SizedBox(height: 8),

                                /* 簽名畫布 */
                                Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                      color: _signedPng != null
                                          ? cs.primary
                                          : cs.outlineVariant,
                                      width: _signedPng != null ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: ListenableBuilder(
                                      listenable: _sigCtrl,
                                      builder: (_, __) => Stack(
                                        children: [
                                          Signature(
                                            controller: _sigCtrl,
                                            backgroundColor: Colors.transparent,
                                          ),
                                          if (_sigCtrl.isEmpty)
                                            Center(
                                              child: Text(
                                                l.signatureHint,
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        _sigCtrl.clear();
                                        setState(() => _signedPng = null);
                                        setSheetState(() {});
                                      },
                                      icon: const Icon(Icons.refresh, size: 16),
                                      label: Text(l.resignature),
                                    ),
                                    const Spacer(),
                                    if (_signedPng != null)
                                      Row(
                                        children: [
                                          Icon(Icons.check_circle,
                                              color: cs.primary, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            l.signatureConfirmed,
                                            style: TextStyle(
                                                color: cs.primary,
                                                fontSize: 13),
                                          ),
                                        ],
                                      )
                                    else
                                      FilledButton.tonal(
                                        onPressed: () =>
                                            _captureSignature(setSheetState),
                                        child: Text(l.confirmSignature),
                                      ),
                                  ],
                                ),

                                /* 簽名預覽 */
                                if (_signedPng != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer
                                          .withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: cs.primary
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Image.memory(
                                            _signedPng!,
                                            height: 52,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          l.signaturePreview,
                                          style: TextStyle(
                                              color: cs.onSurfaceVariant,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (commentField != null) ...[
                      const SizedBox(height: 20),

                      /* ── 留言 ── */
                      Text(
                        commentLabel!,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: commentField.hint,
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: cs.primary),
                          ),
                        ),
                      ),
                      if (_needComment) ...[
                        const SizedBox(height: 8),
                        Text(
                          l.commentRequired,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.error,
                                  ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),

                    /* ── 送出 ── */
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            _submitting ? null : () => _submit(setSheetState),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: _submitting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(l.confirmSubmit,
                                  style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _sigCtrl.dispose();
    _commentCtrl.dispose();
    _pdfDoc?.close();
    super.dispose();
  }

  /* ═════════════════ build ═════════════════════ */
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    return ResponsiveScaffold(
      title: l.signDocument,
      isFullscreen: true,
      appBarBackgroundColor: cs.surface,
      appBarForegroundColor: cs.onSurface,
      appBarElevation: 0.5,
      body: Stack(
        children: [
          /* ─── 全螢幕 PDF ─── */
          _buildPdfViewer(cs),

          /* ─── 頁碼指示器 ─── */
          if (!_loadingPdf && _pdfError == null && _pagesCount > 1)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentPage + 1} / $_pagesCount',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),

          /* ─── 底部操作列 ─── */
          if (!_loadingPdf && _pdfError == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      /* 目前狀態標籤 */
                      if (_signedPng != null ||
                          _selectedStatus != 'signed') ...[
                        _StatusChip(status: _selectedStatus, cs: cs),
                        const SizedBox(width: 12),
                      ],
                      const Spacer(),

                      /* 簽署 FAB */
                      FloatingActionButton.extended(
                        heroTag: null,
                        onPressed: _openSignSheet,
                        icon: const Icon(Icons.draw_outlined),
                        label: Text(l.startSign),
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                        elevation: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /* ═══ PDF Viewer widget ═════════════════════ */
  Widget _buildPdfViewer(ColorScheme cs) {
    if (_loadingPdf) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pdfError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 48),
            const SizedBox(height: 8),
            Text(_pdfError!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _loadingPdf = true;
                  _pdfError = null;
                });
                _loadPdf();
              },
              child: Text(AppLocalizations.of(context)!.reload),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        padEnds: false,
        itemCount: _pagesCount,
        onPageChanged: (idx) => setState(() => _currentPage = idx),
        itemBuilder: (_, idx) => PdfPageImageView(
          pdfDocument: _pdfDoc!,
          pageNumber: idx + 1,
          minScale: 0.8,
          imageFit: BoxFit.contain,
          wrapInCenter: true,
        ),
      ),
    );
  }
}

/* ═══ 狀態標籤元件 ═══════════════════════════════ */
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.cs});

  final String status;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (icon, label, bgColor, fgColor) = switch (status) {
      'commented' => (
          Icons.mode_comment_outlined,
          l.commentedStatus,
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
        ),
      'signed' => (
          Icons.check_circle_outline,
          l.signedStatus,
          cs.primaryContainer,
          cs.onPrimaryContainer,
        ),
      'rejected' => (
          Icons.cancel_outlined,
          l.rejectAction,
          cs.errorContainer,
          cs.onErrorContainer,
        ),
      'skipped' => (
          Icons.skip_next_outlined,
          l.skippedStatus,
          cs.secondaryContainer,
          cs.onSecondaryContainer,
        ),
      _ => (
          Icons.pending_actions_outlined,
          l.pendingSignStatus,
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fgColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fgColor, fontSize: 13)),
        ],
      ),
    );
  }
}

class _StatusOptionCard extends StatelessWidget {
  const _StatusOptionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.maybeZero(context, AppMotion.fast),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? backgroundColor : cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? foregroundColor : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? foregroundColor : cs.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected ? foregroundColor : cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected
                          ? foregroundColor.withValues(alpha: 0.9)
                          : cs.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
