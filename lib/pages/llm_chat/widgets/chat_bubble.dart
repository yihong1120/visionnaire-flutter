import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import '../models/chat_attachment_model.dart';
import 'chat_attachment_image.dart';
import 'chat_attachment_document.dart';
import 'chat_image_thumbnail.dart';

class ChatBubble extends StatefulWidget {
  final Key? itemKey;

  final Map<String, dynamic> message;
  final bool isEditing;
  final TextEditingController? editController;
  final List<ChatEditingAttachment> editingAttachments;
  final Future<Uint8List> Function(String url) getAttachmentBytes;
  final VoidCallback? onCancelEdit;
  final Function(int id)? onConfirmEdit;
  final VoidCallback? onPickImagesForEdit;
  final VoidCallback? onPickFilesForEdit;
  final Function(int index)? onRemoveAttachment;
  final Function(Map<String, dynamic> attachment)? onFileTap;
  final Function(Uint8List? bytes, Map<String, dynamic>? attachment)?
      onImageTap;
  final Function(int id, String content, List<dynamic>? attachments)?
      onStartEdit;
  final Function(int id)? onRemoveMessage;
  final Function(int id)? onRegenerate;
  final Function(List<Map<String, dynamic>> sources)? onOpenSources;
  final Function(String url)? onLinkTap;
  final int? pairedQuestionId;
  final String? runState;
  final bool isLastMessage;

  const ChatBubble({
    this.itemKey,
    super.key,
    required this.message,
    required this.getAttachmentBytes,
    this.isEditing = false,
    this.editController,
    this.editingAttachments = const [],
    this.onCancelEdit,
    this.onConfirmEdit,
    this.onPickImagesForEdit,
    this.onPickFilesForEdit,
    this.onRemoveAttachment,
    this.onFileTap,
    this.onImageTap,
    this.onStartEdit,
    this.onRemoveMessage,
    this.onRegenerate,
    this.onOpenSources,
    this.onLinkTap,
    this.pairedQuestionId,
    this.runState,
    this.isLastMessage = false,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive =>
      widget.isEditing ||
      (widget.isLastMessage && widget.runState != null) ||
      _hasImageAttachments(widget.message) ||
      _hasEditingImageAttachments();

  @override
  void didUpdateWidget(covariant ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateKeepAlive();
  }

  bool _hasEditingImageAttachments() {
    return widget.editingAttachments.any((ChatEditingAttachment attachment) {
      final String mime = attachment.mime ?? '';
      final String name = (attachment.name ?? '').toLowerCase();
      return mime.startsWith('image/') ||
          name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.gif') ||
          name.endsWith('.webp');
    });
  }

  bool _hasImageAttachments(Map<String, dynamic> message) {
    final List<dynamic>? attachments = message['attachments'] as List?;
    if (attachments == null || attachments.isEmpty) return false;

    for (final dynamic rawAttachment in attachments) {
      if (rawAttachment is! Map) continue;
      final Map<String, dynamic> attachment =
          Map<String, dynamic>.from(rawAttachment);
      final String contentType =
          (attachment['content_type'] as String? ?? '').toLowerCase();
      final String name = ((attachment['original_name'] as String?) ??
              (attachment['filename'] as String?) ??
              (attachment['name'] as String?) ??
              '')
          .toLowerCase();
      if (contentType.startsWith('image/') ||
          name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.gif') ||
          name.endsWith('.webp')) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _extractSources(Map<String, dynamic> msg) {
    final raw = msg['sources'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final message = widget.message;
    final isEditing = widget.isEditing;
    final editController = widget.editController;
    final editingAttachments = widget.editingAttachments;
    final getAttachmentBytes = widget.getAttachmentBytes;
    final onCancelEdit = widget.onCancelEdit;
    final onConfirmEdit = widget.onConfirmEdit;
    final onPickImagesForEdit = widget.onPickImagesForEdit;
    final onPickFilesForEdit = widget.onPickFilesForEdit;
    final onRemoveAttachment = widget.onRemoveAttachment;
    final onFileTap = widget.onFileTap;
    final onImageTap = widget.onImageTap;

    final onRegenerate = widget.onRegenerate;
    final onOpenSources = widget.onOpenSources;
    final onLinkTap = widget.onLinkTap;
    final pairedQuestionId = widget.pairedQuestionId;
    final runState = widget.runState;
    final isLastMessage = widget.isLastMessage;
    final isUser = message['role'] == 'user';
    final theme = Theme.of(context);
    final local = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final Color bgColor =
        isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final Color fgColor =
        isUser ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    // Edit Mode
    if (isUser && isEditing) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (editingAttachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: editingAttachments.asMap().entries.map((entry) {
                    final index = entry.key;
                    final att = entry.value;
                    final attMap =
                        att.isLocal ? null : {'url': att.url, 'uuid': att.uuid};

                    final mime = att.mime ?? '';
                    final name = (att.name ?? '').toLowerCase();
                    final isImage = mime.startsWith('image/') ||
                        name.endsWith('.png') ||
                        name.endsWith('.jpg') ||
                        name.endsWith('.jpeg') ||
                        name.endsWith('.gif') ||
                        name.endsWith('.webp');

                    return ChatImageThumbnail(
                      bytes: att.isLocal ? att.bytes : null,
                      attachment: attMap,
                      getBytes: getAttachmentBytes,
                      onRemove: () => onRemoveAttachment?.call(index),
                      onTap: () {
                        if (isImage) {
                          onImageTap?.call(
                              att.isLocal ? att.bytes : null, attMap);
                        } else if (!att.isLocal) {
                          onFileTap?.call(attMap!);
                        }
                      },
                      isImage: isImage,
                      filename: att.name,
                    );
                  }).toList(),
                ),
              ),
            TextField(
              controller: editController,
              maxLines: null,
              minLines: 2,
              decoration: InputDecoration(
                hintText: local.editQuestionHint,
                border: InputBorder.none,
              ),
              style: theme.textTheme.bodyLarge?.copyWith(color: fgColor),
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: local.addImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: onPickImagesForEdit,
                ),
                IconButton(
                  tooltip: local.addFiles,
                  icon: const Icon(Icons.attach_file),
                  onPressed: onPickFilesForEdit,
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: onCancelEdit,
                  child: Text(local.cancel),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => onConfirmEdit?.call(message['id'] as int),
                  child: Text(local.sendMessage),
                ),
              ],
            )
          ],
        ),
      );
    }

    // User Message
    if (isUser) {
      final attachments = message['attachments'] as List?;
      var textContent = (message['content'] as String? ?? '').trim();

      // Extract file name from the backend injected attachment text markers
      final embeddedNames = RegExp(
              r'\[(?:document|image|file|video|audio):\s*([^\]]+)\]',
              caseSensitive: false)
          .allMatches(textContent)
          .map((m) => m.group(1)?.trim())
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>()
          .toList();

      // Remove backend injected attachment text markers like [Document: filename.ext]
      textContent = textContent
          .replaceAll(
              RegExp(r'\s*\[(?:document|image|file|video|audio):\s*[^\]]+\]',
                  caseSensitive: false),
              '')
          .trim();
      final maxWidth = MediaQuery.of(context).size.width * 0.85;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (attachments != null && attachments.isNotEmpty)
            ...attachments.asMap().entries.map((entry) {
              final idx = entry.key;
              final attMap = Map<String, dynamic>.from(entry.value as Map);
              final contentType = attMap['content_type'] as String? ?? '';

              if (idx < embeddedNames.length &&
                  (attMap['original_name'] == null ||
                      (attMap['original_name'] as String).isEmpty) &&
                  (attMap['filename'] == null ||
                      (attMap['filename'] as String).isEmpty) &&
                  (attMap['name'] == null ||
                      (attMap['name'] as String).isEmpty)) {
                attMap['name'] = embeddedNames[idx];
              }

              final tempName = (attMap['original_name'] as String?) ??
                  (attMap['filename'] as String?) ??
                  (attMap['name'] as String?) ??
                  '';
              final isImage = contentType.startsWith('image/') ||
                  tempName.toLowerCase().endsWith('.png') ||
                  tempName.toLowerCase().endsWith('.jpg') ||
                  tempName.toLowerCase().endsWith('.jpeg') ||
                  tempName.toLowerCase().endsWith('.gif') ||
                  tempName.toLowerCase().endsWith('.webp');

              return Container(
                margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: isImage
                    ? ChatAttachmentImage(
                        attachment: attMap,
                        getBytes: getAttachmentBytes,
                        onTap: () => onImageTap?.call(null, attMap),
                      )
                    : ChatAttachmentDocument(
                        attachment: attMap,
                        onTap: () => onFileTap?.call(attMap),
                      ),
              );
            }),
          if (attachments != null &&
              attachments.isNotEmpty &&
              textContent.isNotEmpty)
            const SizedBox(height: 8),
          if (textContent.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(12),
              constraints: BoxConstraints(maxWidth: maxWidth),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                textContent,
                style: theme.textTheme.bodyMedium?.copyWith(color: fgColor),
              ),
            ),
        ],
      );
    }

    // Assistant Message
    final sources = _extractSources(message);
    final streamStatus = message['stream_status'];
    final streamStatusType =
        streamStatus is Map ? (streamStatus['type'] as String?) : null;
    final streamStatusStage =
        streamStatus is Map ? (streamStatus['stage'] as String?) : null;
    final streamStatusMessage =
        streamStatus is Map ? (streamStatus['message'] as String?) : null;

    final hasStreamStatus = (streamStatusType != null &&
            streamStatusType.trim().isNotEmpty) ||
        (streamStatusStage != null && streamStatusStage.trim().isNotEmpty) ||
        (streamStatusMessage != null && streamStatusMessage.trim().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasStreamStatus)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              [
                '[${(streamStatusType ?? 'event').trim()}]',
                if (streamStatusStage != null &&
                    streamStatusStage.trim().isNotEmpty)
                  '[${streamStatusStage.trim()}]',
                if (streamStatusMessage != null &&
                    streamStatusMessage.trim().isNotEmpty)
                  streamStatusMessage.trim(),
              ].join(' '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (hasStreamStatus) const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MarkdownBody(
            data: message['content'] as String? ?? '',
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium?.copyWith(color: fgColor),
              h1: theme.textTheme.headlineSmall?.copyWith(color: fgColor),
              h2: theme.textTheme.titleLarge?.copyWith(color: fgColor),
              h3: theme.textTheme.titleMedium?.copyWith(color: fgColor),
              code: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: scheme.onSurface,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              codeblockDecoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              blockquoteDecoration: BoxDecoration(
                color: scheme.surface,
                border:
                    Border(left: BorderSide(color: scheme.outline, width: 4)),
              ),
              blockquote: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              listBullet: theme.textTheme.bodyMedium?.copyWith(color: fgColor),
              a: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.tertiary,
                decoration: TextDecoration.underline,
              ),
            ),
            onTapLink: (text, href, title) {
              if (href != null) onLinkTap?.call(href);
            },
            imageBuilder: (uri, title, alt) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      uri.toString(),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        if (!(runState != null && isLastMessage))
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: AppLocalizations.of(context)!.copyToClipboard,
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(
                        text: message['content'] as String? ?? ''));
                  },
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context)!.regenerateAnswer,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: pairedQuestionId == null
                      ? null
                      : () => onRegenerate?.call(pairedQuestionId),
                ),
                if (sources.isNotEmpty)
                  IconButton(
                    tooltip: 'Sources',
                    icon: const Icon(Icons.source, size: 18),
                    onPressed: () => onOpenSources?.call(sources),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
