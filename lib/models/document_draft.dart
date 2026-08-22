class DocumentDraft {
  const DocumentDraft({
    required this.key,
    required this.type,
    required this.payload,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String key;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime updatedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'type': type,
        'payload': payload,
        'updated_at': updatedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

  static DocumentDraft? fromJson(Map<String, dynamic> json) {
    final String? key = json['key'] as String?;
    final String? type = json['type'] as String?;
    final dynamic payload = json['payload'];
    final DateTime? updatedAt = DateTime.tryParse(
      json['updated_at']?.toString() ?? '',
    );
    final DateTime? expiresAt = DateTime.tryParse(
      json['expires_at']?.toString() ?? '',
    );

    if (key == null ||
        key.isEmpty ||
        type == null ||
        type.isEmpty ||
        payload is! Map ||
        updatedAt == null ||
        expiresAt == null) {
      return null;
    }

    return DocumentDraft(
      key: key,
      type: type,
      payload: Map<String, dynamic>.from(payload),
      updatedAt: updatedAt,
      expiresAt: expiresAt,
    );
  }
}
