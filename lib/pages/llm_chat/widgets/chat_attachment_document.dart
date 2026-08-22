import 'package:flutter/material.dart';

class ChatAttachmentDocument extends StatelessWidget {
  final Map<String, dynamic> attachment;
  final VoidCallback? onTap;

  const ChatAttachmentDocument({
    super.key,
    required this.attachment,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String? extractedName = (attachment['original_name'] as String?) ??
        (attachment['filename'] as String?) ??
        (attachment['name'] as String?);
    if (extractedName == null || extractedName.isEmpty) {
      final url = attachment['url'] as String?;
      if (url != null && url.isNotEmpty) {
        try {
          extractedName = Uri.parse(url).pathSegments.last;
        } catch (_) {}
      }
    }
    if (extractedName == null ||
        extractedName == 'content' ||
        extractedName.isEmpty) {
      extractedName = attachment.keys.join(', ');
    }
    final filename = extractedName;
    final size =
        (attachment['file_size'] as int?) ?? (attachment['size'] as int?);

    // Format size
    String sizeStr = '';
    if (size != null) {
      if (size < 1024) {
        sizeStr = '\$size B';
      } else if (size < 1024 * 1024) {
        sizeStr = '\${(size / 1024).toStringAsFixed(1)} KB';
      } else {
        sizeStr = '\${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
      }
    }

    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file,
              color: theme.colorScheme.primary,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    filename,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeStr.isNotEmpty)
                    Text(
                      sizeStr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.download_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
