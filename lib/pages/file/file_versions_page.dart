import 'dart:async';
import 'package:visionnaire/utils/auth_utils.dart';

import '../../../l10n/app_localizations.dart';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../widgets/responsive_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/file_manage_api_service.dart';
import '../../utils/app_navigation.dart';
import '../../utils/file_routes.dart';

class FileVersionsPage extends StatefulWidget {
  const FileVersionsPage({
    super.key,
    required this.fileId,
    required this.docRef,
    this.docName,
  });

  final int fileId;
  final String docRef;
  final String? docName;

  @override
  State<FileVersionsPage> createState() => _FileVersionsPageState();
}

class _FileVersionsPageState extends State<FileVersionsPage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _versions = [];

  // ------ 自動輪詢 ------
  Timer? _pollTimer;
  int _retryCount = 0;
  static const int _maxRetry = 6;
  static const Duration _retryInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _fetchVersions(autoRetry: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel(); // ← 取消輪詢
    super.dispose();
  }

  Future<void> _fetchVersions({bool autoRetry = false}) async {
    if (!mounted) return; // widget 已卸載就直接返回

    try {
      final res = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.getDocumentVersions(
          token: token,
          docId: widget.fileId,
        ),
      );
      if (!mounted) return;

      setState(() {
        _versions = res;
        _loading = false;
        _error = null;
      });

      // --- 檢查有沒有尚未轉好的 PDF ---
      final hasPending = res.any((v) => v['pdf_path'] == null);

      _pollTimer?.cancel(); // 先把舊 timer 清掉
      if (autoRetry && hasPending && _retryCount < _maxRetry) {
        _retryCount += 1;
        _pollTimer =
            Timer(_retryInterval, () => _fetchVersions(autoRetry: true));
      } else {
        _retryCount = 0;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _downloadVersion(
    Map<String, dynamic> v,
    String kind,
    BuildContext buttonContext,
  ) async {
    if (!mounted) return;

    final int verId = v['id'] as int;
    final String filePath =
        (kind == 'pdf' ? v['pdf_path'] : v['file_path']) as String;
    final String fileName = filePath.split('/').last;

    try {
      final url = await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.generateTempUrl(
          token: token,
          versionId: verId,
          kind: kind,
        ),
      );

      // ── Web：直接開新分頁 ──
      if (kIsWeb) {
        final ok = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
        if (!ok) throw '無法啟動瀏覽器下載';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.browserDownloadStarted)));
        }
        return;
      }

      // ── Android：確認權限 ──
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.storagePermissionRequired)));
          }
          return;
        }
      }

      // ── 下載到 App documents ──
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$fileName';
      await Dio().download(url, savePath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.downloadComplete)));

      Rect? shareOrigin;
      if (!buttonContext.mounted) return;
      final renderObj = buttonContext.findRenderObject();
      if (renderObj is RenderBox && renderObj.hasSize) {
        shareOrigin = renderObj.localToGlobal(Offset.zero) & renderObj.size;
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(savePath)],
          sharePositionOrigin: shareOrigin,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!
                .downloadFailedError(e.toString()))));
      }
    }
  }

  Future<void> _deleteVer(Map<String, dynamic> v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!
            .deleteVersionConfirm(v['version_num'].toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) => FileManageAPIService.deleteVersion(
          token: token,
          versionId: v['id'] as int,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.versionDeleted)));
        setState(() => _loading = true);
        _fetchVersions(autoRetry: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!
                .deleteVersionFailedError(e.toString()))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!
          .documentVersionListTitle(widget.docName ?? ''),
      isFullscreen: true,
      onBackPressed: () => appBackOrGo(
        context,
        filePreviewLocation(docRef: widget.docRef),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: AppLocalizations.of(context)!.refresh,
          onPressed: () {
            setState(() => _loading = true);
            _fetchVersions(autoRetry: true);
          },
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child:
                      Text(AppLocalizations.of(context)!.errorPrefix(_error!)))
              : RefreshIndicator(
                  onRefresh: () => _fetchVersions(autoRetry: false),
                  child: ListView.builder(
                    itemCount: _versions.length,
                    itemBuilder: (_, idx) {
                      final v = _versions[idx];
                      final pdfReady = v['pdf_path'] != null;
                      return ListTile(
                        title: Text(AppLocalizations.of(context)!
                            .versionNumber(v['version_num'].toString())),
                        subtitle:
                            Text(fmt.format(DateTime.parse(v["created_at"]))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Builder(
                              builder: (btnCtx) => IconButton(
                                icon: const Icon(Icons.description),
                                tooltip:
                                    AppLocalizations.of(context)!.downloadDocx,
                                onPressed: () =>
                                    _downloadVersion(v, 'docx', btnCtx),
                              ),
                            ),
                            Builder(
                              builder: (btnCtx) => IconButton(
                                icon: const Icon(Icons.picture_as_pdf),
                                tooltip: pdfReady
                                    ? AppLocalizations.of(context)!.downloadPdf
                                    : AppLocalizations.of(context)!
                                        .pdfConverting,
                                onPressed: pdfReady
                                    ? () => _downloadVersion(v, 'pdf', btnCtx)
                                    : null,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: AppLocalizations.of(context)!
                                  .deleteVersionTooltip,
                              onPressed: () => _deleteVer(v),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
