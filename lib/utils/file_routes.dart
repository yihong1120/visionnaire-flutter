String fileListLocation() => '/files';

String? documentRouteRefFromMap(Map<dynamic, dynamic>? document) {
  if (document == null) return null;
  final directRef = _documentRouteRefFromDirectMap(document);
  if (directRef != null) return directRef;

  const nestedKeys = <String>[
    'main_document',
    'document',
    'file',
    'data',
  ];
  for (final key in nestedKeys) {
    final nested = document[key];
    if (nested is Map) {
      final nestedRef = documentRouteRefFromMap(nested);
      if (nestedRef != null) return nestedRef;
    }
  }
  return null;
}

String? _documentRouteRefFromDirectMap(Map<dynamic, dynamic> document) {
  const keys = <String>[
    'public_id',
    'uuid',
    'slug',
    'document_uuid',
    'document_public_id',
    'full_file_code',
    'file_code',
    'document_code',
  ];

  for (final key in keys) {
    final value = document[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String filePreviewLocation({
  required String docRef,
  int? versionId,
  String? downloadKind,
}) {
  return Uri(
    path: '/files',
    queryParameters: <String, String>{
      'doc': _docRouteToken(docRef),
      if (versionId != null) 'v': '$versionId',
      if (downloadKind != null && downloadKind.trim().isNotEmpty)
        'dl': downloadKind.trim(),
    },
  ).toString();
}

String fileEditLocation({
  required String docRef,
  bool freshlyCreated = false,
  String? clientDraftId,
}) {
  return Uri(
    path: '/files',
    queryParameters: <String, String>{
      'doc': _docRouteToken(docRef),
      'view': 'edit',
      if (freshlyCreated) 'fresh': '1',
      if (clientDraftId != null && clientDraftId.trim().isNotEmpty)
        'draft': clientDraftId.trim(),
    },
  ).toString();
}

String fileVersionsLocation({required String docRef}) {
  return Uri(
    path: '/files',
    queryParameters: <String, String>{
      'doc': _docRouteToken(docRef),
      'view': 'versions',
    },
  ).toString();
}

String _docRouteToken(String docRef) {
  final normalized = docRef.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(docRef, 'docRef', '文件缺少公開代碼，無法產生網址');
  }
  return normalized;
}
