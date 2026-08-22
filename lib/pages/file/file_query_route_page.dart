import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/file_manage_api_service.dart';
import '../../utils/auth_utils.dart';
import '../../utils/file_routes.dart';
import '../../widgets/web_selectable_content.dart';
import 'file_edit_launch_page.dart';
import 'file_versions_page.dart';
import 'pdf_preview_page.dart';

class FileQueryRoutePage extends StatefulWidget {
  const FileQueryRoutePage({
    super.key,
    required this.docToken,
    required this.view,
    this.docName,
    this.initialVersionId,
    this.autoDownload,
    this.freshlyCreated = false,
    this.clientDraftId,
  });

  final String docToken;
  final String view;
  final String? docName;
  final int? initialVersionId;
  final String? autoDownload;
  final bool freshlyCreated;
  final String? clientDraftId;

  @override
  State<FileQueryRoutePage> createState() => _FileQueryRoutePageState();
}

class _FileQueryRoutePageState extends State<FileQueryRoutePage> {
  Future<_ResolvedDocumentRoute>? _resolveFuture;

  @override
  void initState() {
    super.initState();
    _resolveFuture = _resolveDocument();
  }

  @override
  void didUpdateWidget(covariant FileQueryRoutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.docToken != widget.docToken ||
        oldWidget.view != widget.view) {
      _resolveFuture = _resolveDocument();
    }
  }

  Future<_ResolvedDocumentRoute> _resolveDocument() async {
    final token = widget.docToken.trim();
    final document = await AuthUtils.withAuthRetry(
      context,
      (accessToken) => FileManageAPIService.findDocumentByReference(
        token: accessToken,
        reference: token,
      ),
    );
    if (document == null) {
      throw Exception('找不到文件：$token');
    }

    final docId = _intFromValue(document['id'] ?? document['document_id']);
    if (docId == null) {
      throw Exception('文件缺少 id：$token');
    }

    return _ResolvedDocumentRoute(
      docId: docId,
      docName: widget.docName ??
          (document['full_file_code'] as String?) ??
          (document['file_name'] as String?) ??
          (document['name'] as String?),
      docRef: documentRouteRefFromMap(document) ?? token,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedDocumentRoute>(
      future: _resolveFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: WebSelectableContent(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(snapshot.error?.toString() ?? '找不到文件'),
                    const SizedBox(height: 12),
                    WebNonSelectableContent(
                      child: FilledButton(
                        onPressed: () => context.go(fileListLocation()),
                        child: const Text('返回文件列表'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final resolved = snapshot.data!;
        final view = widget.view.trim().toLowerCase();
        if (view == 'versions') {
          return FileVersionsPage(
            fileId: resolved.docId,
            docName: resolved.docName,
            docRef: resolved.docRef,
          );
        }
        if (view == 'edit') {
          return FileEditLaunchPage(
            docId: resolved.docId,
            freshlyCreated: widget.freshlyCreated,
            clientDraftId: widget.clientDraftId,
          );
        }

        return PdfPreviewPage(
          docId: resolved.docId,
          docRef: resolved.docRef,
          docName: resolved.docName,
          initialVersionId: widget.initialVersionId,
          autoDownload: widget.autoDownload,
        );
      },
    );
  }
}

class _ResolvedDocumentRoute {
  const _ResolvedDocumentRoute({
    required this.docId,
    required this.docName,
    required this.docRef,
  });

  final int docId;
  final String? docName;
  final String docRef;
}

int? _intFromValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
