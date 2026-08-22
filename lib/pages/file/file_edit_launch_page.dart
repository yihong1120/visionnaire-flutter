import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/file_manage_api_service.dart';
import '../../utils/auth_utils.dart';
import '../../widgets/responsive_scaffold.dart';
import 'audit_fix_doc_create_page.dart';
import 'file_edit_page.dart';
import 'photo_doc_create_page.dart';

class FileEditLaunchPage extends StatefulWidget {
  const FileEditLaunchPage({
    super.key,
    required this.docId,
    this.freshlyCreated = false,
    this.clientDraftId,
  });

  final int docId;
  final bool freshlyCreated;
  final String? clientDraftId;

  @override
  State<FileEditLaunchPage> createState() => _FileEditLaunchPageState();
}

class _FileEditLaunchPageState extends State<FileEditLaunchPage> {
  bool _loading = true;
  String? _error;
  String _documentType = '';

  @override
  void initState() {
    super.initState();
    _loadDocumentType();
  }

  Future<void> _loadDocumentType() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> docInfo = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getFileById(
          token: token,
          fileId: widget.docId,
        ),
      );

      if (!mounted) return;
      setState(() {
        _documentType = (docInfo['document_type_name'] as String? ?? '').trim();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context)!.loadFailedError(e.toString());
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.edit,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.edit,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadDocumentType,
                  child: Text(AppLocalizations.of(context)!.tryAgain),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_documentType == '圖片表格列') {
      return PhotoDocCreatePage(fileId: widget.docId);
    }
    if (_documentType == '缺失稽核改善') {
      return AuditFixDocCreatePage(fileId: widget.docId);
    }
    return FileEditPage(
      fileId: widget.docId,
      freshlyCreated: widget.freshlyCreated,
      clientDraftId: widget.clientDraftId,
    );
  }
}
