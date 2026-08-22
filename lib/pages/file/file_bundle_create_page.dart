import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/file_manage_api_service.dart';
import '../../services/document_draft_service.dart';
import '../../utils/auth_utils.dart';
import '../../utils/file_routes.dart';
import '../../widgets/busy_overlay.dart';
import '../../widgets/responsive_scaffold.dart';

class FileBundleCreatePage extends StatefulWidget {
  const FileBundleCreatePage({
    super.key,
    required this.site,
    required this.documentTypeName,
    required this.filePrefix,
  });

  final Map<String, dynamic> site;
  final String documentTypeName;
  final String filePrefix;

  @override
  State<FileBundleCreatePage> createState() => _FileBundleCreatePageState();
}

class _FileBundleCreatePageState extends State<FileBundleCreatePage> {
  bool _busy = true;
  String? _error;

  int get _siteId => (widget.site['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _initializeMainDocument();
  }

  Future<void> _initializeMainDocument() async {
    final String filePrefix = widget.filePrefix.trim();
    final String clientDraftId = DocumentDraftService.createClientDraftId();
    if (filePrefix.isEmpty) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '這個文件類型沒有可用的模板前綴，無法直接從模板建立。';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }

    try {
      final Map<String, dynamic> response = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.createFileBundle(
          token: token,
          metadata: <String, dynamic>{
            'main_document': <String, dynamic>{
              'mode': 'template',
              'site_id': _siteId,
              'file_prefix': filePrefix,
            },
            'photo_documents': const <Map<String, dynamic>>[],
            'audit_fix_documents': const <Map<String, dynamic>>[],
            'link_existing_children': const <Map<String, dynamic>>[],
          },
        ),
      );

      final int? documentId = (response['main_document_id'] as num?)?.toInt();
      if (documentId == null) {
        throw const FormatException('建立主文件成功，但回傳缺少 main_document_id');
      }

      if (!mounted) return;
      final String? docRef = documentRouteRefFromMap(response);
      if (docRef == null || docRef.trim().isEmpty) {
        throw const FormatException('建立主文件成功，但回傳缺少公開文件代碼');
      }

      // Pop this page off the imperative Navigator stack before routing,
      // so the user won't land back here when pressing back in the edit page.
      Navigator.of(context).pop();
      context.go(
        fileEditLocation(
          docRef: docRef,
          freshlyCreated: true,
          clientDraftId: clientDraftId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '初始化主文件失敗：$e';
      });
    }
  }

  Widget _buildLoadingState(ThemeData theme) {
    final ColorScheme cs = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 18),
              Text(
                '正在從模板建立母文件',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '建立完成後會直接進入母文件編輯頁，子文件與掛載管理會在同一頁面底部。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                '工地：${widget.site['name'] ?? ''}',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    final ColorScheme cs = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                color: cs.error,
                size: 30,
              ),
              const SizedBox(height: 16),
              Text(
                _error ?? '初始化主文件失敗',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurface,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _initializeMainDocument,
                icon: const Icon(Icons.refresh),
                label: const Text('重試建立'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ResponsiveScaffold(
      title: '建立 ${widget.documentTypeName}',
      isFullscreen: true,
      onBackPressed: () => Navigator.of(context).maybePop(),
      body: BusyOverlay(
        busy: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _busy ? _buildLoadingState(theme) : _buildErrorState(theme),
        ),
      ),
    );
  }
}
