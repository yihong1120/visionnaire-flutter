import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/bff_config.dart';
import '../../services/chat_api_service.dart';
import '../../utils/authenticated_uri.dart';
import '../../utils/authenticated_http.dart';
import '../../utils/auth_utils.dart';
import '../../utils/cross_platform_download.dart';
import '../../services/auth_request_headers.dart';

class ChatCitationsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> sources;
  final VoidCallback? onClose;
  const ChatCitationsPanel({super.key, required this.sources, this.onClose});

  bool _isDocumentDownloadLink(Uri uri) {
    // Server-provided document download endpoint (requires Authorization header).
    return uri.path.contains(BffConfig.chatDocumentDownloadPath);
  }

  String _filenameFromTitle(String title, int index) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'source_${index + 1}';
    return trimmed.startsWith('doc:') ? trimmed.substring(4) : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return Container(
      color: Theme.of(ctx).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                const Icon(Icons.source, size: 18),
                const SizedBox(width: 8),
                Text('Citations', style: Theme.of(ctx).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: onClose ?? () => Navigator.of(ctx).pop(),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: sources.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = sources[index];
                final rawTitle = (s['title'] as String? ?? '').trim();
                final title =
                    rawTitle.isEmpty ? 'Source ${index + 1}' : rawTitle;
                final urlStr = s['url'] as String?;
                return ListTile(
                  leading: const Icon(Icons.link, size: 20),
                  title:
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: urlStr != null
                      ? Text(urlStr,
                          maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  onTap: urlStr == null
                      ? null
                      : () async {
                          final uri = Uri.tryParse(urlStr);
                          if (uri == null) return;

                          final Uri chatBase = Uri.parse(
                            await ChatAPIService.baseUrl,
                          );
                          if (!context.mounted) return;
                          final bool trusted =
                              AuthenticatedUri.isTrusted(uri, chatBase);
                          final Uri target = trusted
                              ? AuthenticatedUri.resolve(uri, chatBase)
                              : uri;

                          if (trusted && _isDocumentDownloadLink(target)) {
                            // Download via authenticated request so the user doesn't hit
                            // "Credentials are not provided" in a browser tab.
                            if (!kIsWeb) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('目前僅支援 Web 端下載檔案引用')),
                                );
                              }
                              return;
                            }

                            try {
                              final token = await AuthUtils.withAuthRetry(
                                  context, (t) async => t);
                              final response = await AuthenticatedHttp.get(
                                target,
                                headers: AuthRequestHeaders.forRequest(token),
                                timeout: const Duration(
                                  seconds: ChatAPIService.timeoutSeconds,
                                ),
                              );

                              if (response.statusCode == 200) {
                                final filename =
                                    _filenameFromTitle(title, index);
                                CrossPlatformDownload.downloadBytes(
                                  response.bodyBytes,
                                  filename,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('下載成功')),
                                  );
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('下載失敗: ${response.statusCode}'),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('下載失敗: $e')),
                                );
                              }
                            }
                            return;
                          }

                          await launchUrl(target,
                              mode: LaunchMode.externalApplication);
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
