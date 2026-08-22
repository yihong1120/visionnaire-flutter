import 'dart:typed_data';

class ChatAttachment {
  final int id;
  final String filename;
  final String originalName;
  final int fileSize;
  final String contentType;
  final String url;
  final String? previewUrl;
  final bool canPreview;
  final String previewKind;
  final String status;

  ChatAttachment({
    required this.id,
    required this.filename,
    required this.originalName,
    required this.fileSize,
    required this.contentType,
    required this.url,
    required this.previewUrl,
    required this.canPreview,
    required this.previewKind,
    required this.status,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'],
      filename: json['filename'],
      originalName: json['original_name'],
      fileSize: json['file_size'],
      contentType: json['content_type'],
      url: json['url'],
      previewUrl: json['preview_url'],
      canPreview: json['can_preview'] ?? false,
      previewKind: json['preview_kind'] ?? 'file',
      status: json['status'] ?? 'attached',
    );
  }
}

// Lightweight model for local file bytes (before upload)
class LocalAttachmentBytes {
  final String name;
  final Uint8List bytes;
  final String mime;
  LocalAttachmentBytes(
      {required this.name, required this.bytes, required this.mime});
}

class ChatEditingAttachment {
  final String?
      uuid; // Server ID (could be int but let's keep String? for compat or change to int?)
  final int? id; // New integer ID from ChatAttachment
  final String? url;
  final String? previewUrl;
  final Uint8List? bytes;
  final String? name;
  final String? mime;

  ChatEditingAttachment.fromServer(Map<String, dynamic> attachment)
      : uuid = attachment['uuid'] as String?,
        id = attachment['id'] as int?,
        url = attachment['url'] as String?,
        previewUrl = attachment['preview_url'] as String?,
        bytes = null,
        name = attachment['original_name'] as String?,
        mime = attachment['content_type'] as String?;

  ChatEditingAttachment.fromLocal(LocalAttachmentBytes localImage)
      : uuid = null,
        id = null,
        url = null,
        previewUrl = null,
        bytes = localImage.bytes,
        name = localImage.name,
        mime = localImage.mime;

  bool get isLocal => bytes != null;
}
