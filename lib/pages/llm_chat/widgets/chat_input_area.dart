import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import '../models/chat_attachment_model.dart';
import '../utils/chat_intents.dart';
import '../utils/chat_utils.dart';

class ChatInputArea extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<ChatAttachment> draftAttachments;
  final bool isBusy;
  final String? runState;
  final bool isWide;
  final bool useMobileEnterForNewline;
  final VoidCallback onSend;
  final VoidCallback onPickImages;
  final VoidCallback onPickFiles;
  final Function(int index) onRemovePendingImage;
  final Function(ChatAttachment attachment) onAttachmentTap;
  final Future<Uint8List> Function(ChatAttachment attachment)
      onLoadAttachmentPreview;
  final VoidCallback onCancelStream;
  final Function(List<LocalAttachmentBytes> files) onFilesDropped;
  final Function(String error) onError;
  final VoidCallback onInputTap;
  final bool isEditing;
  final int? chatId;

  const ChatInputArea({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.draftAttachments,
    required this.isBusy,
    this.runState,
    required this.isWide,
    required this.useMobileEnterForNewline,
    required this.onSend,
    required this.onPickImages,
    required this.onPickFiles,
    required this.onRemovePendingImage,
    required this.onAttachmentTap,
    required this.onLoadAttachmentPreview,
    required this.onCancelStream,
    required this.onFilesDropped,
    required this.onError,
    required this.onInputTap,
    this.isEditing = false,
    this.chatId,
  });

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea> {
  bool _draggingOver = false;

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    final ColorScheme colors = Theme.of(context).colorScheme;

    if (widget.isEditing) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pending image previews (thumbnails)
        if (widget.draftAttachments.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            color: Theme.of(context).cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image count indicator
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.image, size: 14, color: colors.primary),
                      const SizedBox(width: 4),
                      Text(
                        local.attachmentCount(widget.draftAttachments.length),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: widget.draftAttachments.asMap().entries.map((e) {
                      final idx = e.key;
                      final att = e.value;
                      final sizeMB =
                          (att.fileSize / (1024 * 1024)).toStringAsFixed(1);

                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: () => widget.onAttachmentTap(att),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      color: colors.surfaceContainerHighest,
                                      child: (att.previewKind == 'image' &&
                                              att.previewUrl != null)
                                          ? FutureBuilder<Uint8List>(
                                              future: widget
                                                  .onLoadAttachmentPreview(att),
                                              builder: (context, snapshot) {
                                                if (snapshot.connectionState !=
                                                    ConnectionState.done) {
                                                  return const Center(
                                                    child: SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    ),
                                                  );
                                                }
                                                if (!snapshot.hasData) {
                                                  return const Icon(
                                                    Icons.broken_image,
                                                  );
                                                }
                                                return Image.memory(
                                                  snapshot.data!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Icon(
                                                    Icons.broken_image,
                                                  ),
                                                );
                                              },
                                            )
                                          : Icon(
                                              att.previewKind == 'video'
                                                  ? Icons.videocam
                                                  : att.previewKind == 'audio'
                                                      ? Icons.audiotrack
                                                      : Icons.insert_drive_file,
                                              size: 32,
                                              color: colors.onSurfaceVariant,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$sizeMB MB',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              right: -6,
                              top: -6,
                              child: IconButton(
                                splashRadius: 16,
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () =>
                                    widget.onRemovePendingImage(idx),
                              ),
                            )
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        // Input row with DropTarget
        DropTarget(
          onDragEntered: (_) => setState(() => _draggingOver = true),
          onDragExited: (_) => setState(() => _draggingOver = false),
          onDragDone: (details) async {
            setState(() => _draggingOver = false);
            const maxBytes = 8 * 1024 * 1024;
            final List<LocalAttachmentBytes> newFiles = [];

            for (final xf in details.files) {
              final bytes = await xf.readAsBytes();
              final name = xf.name;

              if (bytes.length > maxBytes) {
                widget.onError('圖片 $name 超過 8MB 限制');
                continue;
              }

              final mime = inferImageMime(name);
              if (!mime.startsWith('image/')) {
                widget.onError('僅支援圖片檔案格式');
                continue;
              }

              newFiles.add(
                  LocalAttachmentBytes(name: name, bytes: bytes, mime: mime));
            }
            if (newFiles.isNotEmpty) {
              widget.onFilesDropped(newFiles);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Theme.of(context)
                .cardColor
                .withValues(alpha: _draggingOver ? 0.96 : 1.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: widget.useMobileEnterForNewline
                      ? TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          onTap: widget.onInputTap,
                          decoration: InputDecoration(
                            hintText: local.inputMessage,
                            border: InputBorder.none,
                            prefixIcon: _draggingOver
                                ? Icon(
                                    Icons.file_download,
                                    color: colors.primary,
                                  )
                                : null,
                          ),
                        )
                      : Shortcuts(
                          shortcuts: <ShortcutActivator, Intent>{
                            const SingleActivator(LogicalKeyboardKey.enter):
                                const SendMessageIntent(),
                            const SingleActivator(
                                    LogicalKeyboardKey.numpadEnter):
                                const SendMessageIntent(),
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              shift: true,
                            ): const NewlineIntent(),
                          },
                          child: Actions(
                            actions: <Type, Action<Intent>>{
                              SendMessageIntent:
                                  CallbackAction<SendMessageIntent>(
                                onInvoke: (intent) {
                                  widget.onSend();
                                  return null;
                                },
                              ),
                              NewlineIntent: CallbackAction<NewlineIntent>(
                                onInvoke: (intent) {
                                  final value = widget.controller.value;
                                  final sel = value.selection;
                                  final start = sel.isValid
                                      ? sel.start
                                      : value.text.length;
                                  final end =
                                      sel.isValid ? sel.end : value.text.length;
                                  widget.controller.value = value.copyWith(
                                    text: value.text
                                        .replaceRange(start, end, '\n'),
                                    selection: TextSelection.collapsed(
                                        offset: start + 1),
                                    composing: TextRange.empty,
                                  );
                                  return null;
                                },
                              ),
                            },
                            child: TextField(
                              controller: widget.controller,
                              focusNode: widget.focusNode,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.send,
                              onTap: widget.onInputTap,
                              onSubmitted: (_) => widget.onSend(),
                              decoration: InputDecoration(
                                hintText: local.inputMessage,
                                border: InputBorder.none,
                                prefixIcon: _draggingOver
                                    ? Icon(
                                        Icons.file_download,
                                        color: colors.primary,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                ),
                // Add file button
                IconButton(
                  tooltip: local.addFiles,
                  icon: const Icon(Icons.attach_file),
                  onPressed: widget.onPickFiles,
                ),
                // Add image button
                IconButton(
                  tooltip: local.addImages,
                  icon: const Icon(Icons.image_outlined),
                  onPressed: widget.onPickImages,
                ),
                // While busy: show spinner and cancel button
                if (widget.isBusy) ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Cancel button
                  IconButton(
                    tooltip: local.cancelGeneration,
                    icon: const Icon(Icons.stop),
                    onPressed: widget.onCancelStream,
                  ),
                ] else
                  // Show different button for blank chat vs existing chat
                  IconButton(
                    icon: Icon(widget.chatId == null
                        ? Icons.add_circle_outline
                        : Icons.send),
                    tooltip: widget.chatId == null
                        ? local.createChatRoom
                        : local.sendMessage,
                    onPressed: widget
                        .onSend, // Logic for disabled state handled in parent or here? Parent checks isBusy.
                  )
              ],
            ),
          ),
        ),
      ],
    );
  }
}
