import 'dart:typed_data';

import 'package:flutter/material.dart';

class ChatBrowserContextImage extends StatelessWidget {
  final Uint8List bytes;
  final String mimeType;
  final BoxFit fit;
  final VoidCallback? onTap;
  final bool hideWhenViewerOpen;

  const ChatBrowserContextImage({
    super.key,
    required this.bytes,
    required this.mimeType,
    required this.fit,
    this.onTap,
    this.hideWhenViewerOpen = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Image.memory(
        bytes,
        fit: fit,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Icon(
              Icons.broken_image,
              color: Theme.of(context).colorScheme.error,
            ),
          );
        },
      ),
    );
  }
}

class ChatBrowserContextImageRegistry {
  static void setViewerOpen(bool open) {}
}
