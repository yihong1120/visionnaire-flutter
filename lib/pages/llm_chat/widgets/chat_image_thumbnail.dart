import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'chat_attachment_image.dart';

class ChatImageThumbnail extends StatelessWidget {
  final Uint8List? bytes;
  final Map<String, dynamic>? attachment;
  final Future<Uint8List> Function(String url) getBytes;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  final double size;
  final bool isImage;
  final String? filename;

  const ChatImageThumbnail({
    super.key,
    required this.bytes,
    required this.attachment,
    required this.getBytes,
    required this.onRemove,
    required this.onTap,
    this.size = 80,
    this.isImage = true,
    this.filename,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isImage
                ? (bytes != null
                    ? Image.memory(bytes!,
                        width: size, height: size, fit: BoxFit.cover)
                    : ChatAttachmentImage(
                        attachment: attachment!,
                        getBytes: getBytes,
                        width: size,
                        height: size,
                      ))
                : Container(
                    width: size,
                    height: size,
                    color: colors.surfaceContainerHighest,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.insert_drive_file,
                          size: size * 0.5,
                          color: colors.onSurfaceVariant,
                        ),
                        if (filename != null) ...[
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              filename!,
                              style: TextStyle(
                                fontSize: size * 0.15,
                                color: colors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
