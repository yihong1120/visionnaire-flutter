import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/document_draft.dart';
import 'api_config_service.dart';
import 'auth_request_headers.dart';

class FileManageApiException implements Exception {
  const FileManageApiException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class CreatedDocumentResult {
  const CreatedDocumentResult({
    required this.documentId,
    required this.fullFileCode,
  });

  factory CreatedDocumentResult.fromJson(Map<String, dynamic> json) {
    return CreatedDocumentResult(
      documentId: (json['document_id'] as num).toInt(),
      fullFileCode: json['full_file_code'] as String,
    );
  }

  final int documentId;
  final String fullFileCode;
}

class BundleUploadFile {
  const BundleUploadFile({
    required this.filename,
    required this.bytes,
    this.contentType,
    this.draftBytes,
  });

  final String filename;
  final Uint8List bytes;
  final MediaType? contentType;
  final Uint8List? draftBytes;
}

class BundleChildDraftResult {
  const BundleChildDraftResult({
    required this.documentTypeName,
    required this.payload,
    this.files = const <BundleUploadFile>[],
  });

  final String documentTypeName;
  final Map<String, dynamic> payload;
  final List<BundleUploadFile> files;
}

class DocumentDraftAttachmentResult {
  const DocumentDraftAttachmentResult({
    required this.attachmentId,
    required this.filename,
    this.contentType,
    this.byteSize,
    this.sha256,
    this.createdAt,
  });

  factory DocumentDraftAttachmentResult.fromJson(Map<String, dynamic> json) {
    return DocumentDraftAttachmentResult(
      attachmentId: (json['attachment_id'] ?? '').toString(),
      filename: (json['filename'] ?? '').toString(),
      contentType: json['content_type']?.toString(),
      byteSize: (json['byte_size'] as num?)?.toInt(),
      sha256: json['sha256']?.toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }

  final String attachmentId;
  final String filename;
  final String? contentType;
  final int? byteSize;
  final String? sha256;
  final DateTime? createdAt;
}

@visibleForTesting
Map<String, dynamic> normalizeSignerResponse(dynamic decodedBody) {
  if (decodedBody is Map) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(decodedBody);
    final Object? rawItems = data['items'];
    if (rawItems != null && rawItems is! List) {
      throw const FormatException('Unexpected signer items response type');
    }

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    for (final Object? item in rawItems as List? ?? const <Object?>[]) {
      if (item is! Map) {
        throw const FormatException('Unexpected signer item response type');
      }
      items.add(Map<String, dynamic>.from(item));
    }

    return <String, dynamic>{
      'total':
          data['total'] is num ? (data['total'] as num).toInt() : items.length,
      'items': items,
    };
  }

  throw FormatException(
    'Unexpected signer response type: ${decodedBody.runtimeType}',
  );
}

@visibleForTesting
Map<String, dynamic>? findUniqueDocumentByReference(
  Iterable<Object?> files,
  String reference,
) {
  Map<String, dynamic>? match;
  for (final Object? rawFile in files) {
    if (rawFile is! Map) continue;
    final Map<String, dynamic> file = Map<String, dynamic>.from(rawFile);
    if (!_matchesDocumentReference(file, reference)) continue;

    if (match != null) {
      throw StateError('Document reference is not unique: $reference');
    }
    match = file;
  }
  return match;
}

bool _matchesDocumentReference(
  Map<String, dynamic> file,
  String reference,
) {
  for (final String key in _documentReferenceKeys) {
    final String? value = file[key]?.toString().trim();
    if (value == reference) return true;
  }
  return false;
}

const List<String> _documentReferenceKeys = <String>[
  'public_id',
  'uuid',
  'slug',
  'document_uuid',
  'document_public_id',
  'full_file_code',
  'file_code',
  'document_code',
];

@visibleForTesting
String draftBaseUrlFromFileManagementBase(String fileManagementBaseUrl) {
  final trimmed = fileManagementBaseUrl.trim();
  if (trimmed.endsWith('/') && trimmed.length > 1) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

@visibleForTesting
Map<String, dynamic> documentDraftUpsertBody(DocumentDraft draft) {
  return <String, dynamic>{
    'draft_type': draft.type,
    'payload': draft.payload,
    'client_updated_at': draft.updatedAt.toIso8601String(),
    'expires_at': draft.expiresAt.toIso8601String(),
  };
}

/// Service class for managing files, documents, versions, signatures, and related operations.
///
/// Provides static methods for file CRUD, document upload, signature flows, field filling, and more.
class FileManageAPIService {
  /// Timeout for HTTP requests, in seconds.
  static const int timeoutSeconds = 600;
  static const int draftTimeoutSeconds = 10;

  /// The base URL for the file management API.
  static Future<String> get baseUrl async {
    return await ApiConfigService.getApiUrl('fileManagement');
  }

  static Future<String> get draftBaseUrl async {
    return draftBaseUrlFromFileManagementBase(await baseUrl);
  }

  /// Rewrites an image URL that may use an internal server address
  /// (e.g. http://127.0.0.1:8004/images/...) to the externally-accessible
  /// URL by replacing the origin with the configured [fileManagementBaseUrl].
  static String rewriteServerImageUrl(
      String imageUrl, String fileManagementBaseUrl) {
    if (imageUrl.isEmpty) return imageUrl;
    final trimmedUrl = imageUrl.trim();

    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null) return imageUrl;
    if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
      final base = fileManagementBaseUrl.endsWith('/')
          ? fileManagementBaseUrl.substring(0, fileManagementBaseUrl.length - 1)
          : fileManagementBaseUrl;
      return '$base${uri.path}';
    }
    return trimmedUrl;
  }

  /// Fetches a paginated list of files.
  ///
  /// [token] The authentication token (required).
  /// [keyword] Optional keyword for searching.
  /// [siteId] Optional site ID for filtering.
  /// [startTime] Optional start time for filtering.
  /// [endTime] Optional end time for filtering.
  /// [limit] Number of records per page (default: 20).
  /// [offset] Offset for pagination (default: 0).
  ///
  /// Returns a map containing the list of files and metadata.
  static Future<Map<String, dynamic>> getFiles({
    required String token,
    String? keyword,
    int? siteId,
    DateTime? startTime,
    DateTime? endTime,
    int? creatorId,
    int? editorId,
    int? signerId,
    int limit = 20,
    int offset = 0,
  }) async {
    final baseUrlValue = await baseUrl;
    final Map<String, String> params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
    if (siteId != null) params['site_id'] = '$siteId';
    if (startTime != null) params['start_time'] = startTime.toIso8601String();
    if (endTime != null) params['end_time'] = endTime.toIso8601String();
    if (creatorId != null) params['creator_id'] = '$creatorId';
    if (editorId != null) params['editor_id'] = '$editorId';
    if (signerId != null) params['signer_id'] = '$signerId';

    final Uri uri =
        Uri.parse('$baseUrlValue/files').replace(queryParameters: params);
    final http.Response res = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    final String body = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) {
      return json.decode(body) as Map<String, dynamic>;
    }
    throw Exception('Failed to fetch files: ${json.decode(body)['detail']}');
  }

  static Future<Map<String, dynamic>?> findDocumentByReference({
    required String token,
    required String reference,
  }) async {
    final normalized = reference.trim();
    if (normalized.isEmpty) return null;

    final response = await getFiles(
      token: token,
      keyword: normalized,
      limit: 50,
    );
    final Object? rawFiles = response['files'];
    if (rawFiles != null && rawFiles is! List) {
      throw const FormatException('Unexpected files response type');
    }
    return findUniqueDocumentByReference(
      rawFiles as List? ?? const <Object?>[],
      normalized,
    );
  }

  static Future<DocumentDraft?> getDocumentDraft({
    required String token,
    required String draftKey,
  }) async {
    final baseUrlValue = await draftBaseUrl;
    final Uri uri = Uri.parse(
      '$baseUrlValue/drafts/${Uri.encodeComponent(draftKey)}',
    );
    final http.Response response = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: draftTimeoutSeconds));

    if (response.statusCode == 204 || response.statusCode == 404) {
      return null;
    }
    final Map<String, dynamic> decoded = _decodeJsonResponse(
      response: response,
      errorPrefix: 'Failed to load document draft',
    );
    return documentDraftFromResponse(decoded, fallbackKey: draftKey);
  }

  static Future<void> upsertDocumentDraft({
    required String token,
    required DocumentDraft draft,
  }) async {
    final baseUrlValue = await draftBaseUrl;
    final Uri uri = Uri.parse(
      '$baseUrlValue/drafts/${Uri.encodeComponent(draft.key)}',
    );
    final Map<String, dynamic> body = documentDraftUpsertBody(draft);
    final Map<String, String> headers = <String, String>{
      ...AuthRequestHeaders.forRequest(token),
      'Content-Type': 'application/json',
    };
    final http.Response response = await http
        .put(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: draftTimeoutSeconds));

    _decodeDynamicResponse(
      response: response,
      errorPrefix: 'Failed to save document draft',
    );
  }

  static Future<void> deleteDocumentDraft({
    required String token,
    required String draftKey,
  }) async {
    final baseUrlValue = await draftBaseUrl;
    final Uri uri = Uri.parse(
      '$baseUrlValue/drafts/${Uri.encodeComponent(draftKey)}',
    );
    final http.Response response = await http.delete(uri, headers: {
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: draftTimeoutSeconds));

    if (response.statusCode == 404) return;
    _decodeDynamicResponse(
      response: response,
      errorPrefix: 'Failed to delete document draft',
    );
  }

  static Future<DocumentDraftAttachmentResult> uploadDocumentDraftAttachment({
    required String token,
    required String draftKey,
    required String draftType,
    required Uint8List bytes,
    required String filename,
    DateTime? expiresAt,
  }) async {
    final baseUrlValue = await draftBaseUrl;
    final Uri uri = Uri.parse(
      '$baseUrlValue/drafts/${Uri.encodeComponent(draftKey)}/attachments',
    );
    final request = http.MultipartRequest('POST', uri);
    AuthRequestHeaders.apply(request, token);
    request.fields['draft_type'] = draftType;
    if (expiresAt != null) {
      request.fields['expires_at'] = expiresAt.toUtc().toIso8601String();
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: _safeUploadFilename(filename),
        contentType: _mediaTypeForFilename(filename),
      ),
    );

    final http.StreamedResponse streamedResponse = await request
        .send()
        .timeout(const Duration(seconds: draftTimeoutSeconds));
    final http.Response response =
        await http.Response.fromStream(streamedResponse);
    final Map<String, dynamic> decoded = _decodeJsonResponse(
      response: response,
      errorPrefix: 'Failed to upload document draft attachment',
    );
    final result = DocumentDraftAttachmentResult.fromJson(decoded);
    if (result.attachmentId.isEmpty) {
      throw const FormatException(
          'Missing attachment_id in draft attachment response');
    }
    return result;
  }

  static Future<Uint8List?> getDocumentDraftAttachment({
    required String token,
    required String draftKey,
    required String attachmentId,
  }) async {
    final baseUrlValue = await draftBaseUrl;
    final Uri uri = Uri.parse(
      '$baseUrlValue/drafts/${Uri.encodeComponent(draftKey)}/attachments/${Uri.encodeComponent(attachmentId)}',
    );
    final http.Response response = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: draftTimeoutSeconds));

    if (response.statusCode == 404) return null;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    _throwApiException(
      response: response,
      errorPrefix: 'Failed to load document draft attachment',
    );
  }

  static Future<void> deleteDocumentDraftAttachment({
    required String token,
    required String draftKey,
    required String attachmentId,
  }) async {
    final baseUrlValue = await draftBaseUrl;
    final Uri uri = Uri.parse(
      '$baseUrlValue/drafts/${Uri.encodeComponent(draftKey)}/attachments/${Uri.encodeComponent(attachmentId)}',
    );
    final http.Response response = await http.delete(uri, headers: {
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: draftTimeoutSeconds));

    if (response.statusCode == 404) return;
    _decodeDynamicResponse(
      response: response,
      errorPrefix: 'Failed to delete document draft attachment',
    );
  }

  @visibleForTesting
  static DocumentDraft? documentDraftFromResponse(
    Map<String, dynamic> response, {
    required String fallbackKey,
  }) {
    if (response.containsKey('draft') && response['draft'] == null) {
      return null;
    }
    if (response.containsKey('item') && response['item'] == null) {
      return null;
    }
    final dynamic rawDraft = response['draft'] ?? response['item'] ?? response;
    if (rawDraft is! Map) return null;

    final Map<String, dynamic> data = Map<String, dynamic>.from(rawDraft);
    final dynamic payload = data['payload'];
    final String key =
        (data['key'] ?? data['draft_key'] ?? fallbackKey).toString();
    final String type = (data['type'] ?? data['draft_type'] ?? '').toString();
    final DateTime? updatedAt = DateTime.tryParse(
      (data['updated_at'] ??
              data['client_updated_at'] ??
              data['server_updated_at'] ??
              '')
          .toString(),
    );
    final DateTime? expiresAt = DateTime.tryParse(
      (data['expires_at'] ?? '').toString(),
    );

    if (key.isEmpty ||
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
      updatedAt: updatedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
    );
  }

  /// Fetches the list of sites available to the user.
  ///
  /// [token] The authentication token (required).
  /// Returns a list of site objects.
  static Future<List<dynamic>> getMySites({required String token}) async {
    final violationRecordsApiUrl =
        await ApiConfigService.getApiUrl('violationRecords');
    final Uri uri = Uri.parse('$violationRecordsApiUrl/my_sites');
    final http.Response res = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    final String body = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) {
      return json.decode(body) as List<dynamic>;
    }
    throw Exception(json.decode(body)['detail'] ?? 'Failed to fetch sites');
  }

  /// Fetches the groups available to the signer picker.
  static Future<List<Map<String, dynamic>>> getSignerPickerGroups({
    required String token,
    required int versionId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/sign/groups').replace(
      queryParameters: <String, String>{
        'version_id': '$versionId',
      },
    );

    final http.Response res = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));
    if (res.statusCode != 200) {
      throw 'getSignerPickerGroups() ${res.statusCode} ${res.body}';
    }

    return List<Map<String, dynamic>>.from(
        jsonDecode(res.body) as List<dynamic>);
  }

  /// Fetches the list of signers for document signing.
  ///
  /// [token] The authentication token (required).
  /// [keyword] Optional keyword for searching signers.
  /// [groupId] Optional group ID for filtering.
  /// [siteId] Optional site ID for filtering.
  /// [versionId] Optional document version ID for filtering.
  /// [limit] Optional limit for number of signers.
  /// [offset] Optional offset for pagination.
  /// Returns a paginated signer payload.
  static Future<Map<String, dynamic>> getSigners({
    required String token,
    String? keyword,
    int? groupId,
    int? siteId,
    int? versionId,
    int? limit,
    int? offset,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/sign/users').replace(
      queryParameters: <String, String>{
        if (keyword != null && keyword.isNotEmpty) 'q': keyword,
        if (groupId != null) 'group_id': '$groupId',
        if (siteId != null) 'site_id': '$siteId',
        if (versionId != null) 'version_id': '$versionId',
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      },
    );

    final http.Response res = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));
    if (res.statusCode != 200) {
      throw 'getSigners() ${res.statusCode} ${res.body}';
    }

    return normalizeSignerResponse(jsonDecode(res.body));
  }

  /// Sets up a signature flow for a document version.
  ///
  /// [token] The authentication token (required).
  /// [versionId] The document version ID.
  /// [assignments] The list of assignments for the signature flow.
  static Future<void> setupSignatureFlow({
    required String token,
    required int versionId,
    required bool ordered,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/sign/setup/$versionId');
    final Map<String, String> headers = <String, String>{
      ...AuthRequestHeaders.forRequest(token),
      'Content-Type': 'application/json',
    };

    http.Response res = await http
        .post(
          uri,
          headers: headers,
          body: json.encode(<String, dynamic>{
            'ordered': ordered,
            'assignments': assignments,
          }),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    if (res.statusCode == 422) {
      final String decoded = utf8.decode(res.bodyBytes);
      if (decoded.contains('list_type')) {
        res = await http
            .post(
              uri,
              headers: headers,
              body: json.encode(assignments),
            )
            .timeout(const Duration(seconds: timeoutSeconds));
      }
    }

    if (res.statusCode != 200) {
      throw Exception('Setup failed: ${utf8.decode(res.bodyBytes)}');
    }
  }

  /// Fetches file details by file ID.
  static Future<Map<String, dynamic>> getFileById({
    required String token,
    required int fileId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/$fileId');
    final http.Response res = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) {
      return json.decode(decoded) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to fetch file details: ${json.decode(decoded)['detail']}',
    );
  }

  /// Uploads a document and returns the created document payload.
  static Future<CreatedDocumentResult> uploadDocument({
    required String token,
    required String fileName,
    required Uint8List bytes,
    required int siteId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/upload');
    final http.MultipartRequest req = http.MultipartRequest('POST', uri)
      ..headers.addAll(AuthRequestHeaders.forRequest(token))
      ..fields['site_id'] = '$siteId';

    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );

    final http.Response res = await http.Response.fromStream(await req.send())
        .timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) {
      return CreatedDocumentResult.fromJson(
        json.decode(decoded) as Map<String, dynamic>,
      );
    }
    throw Exception('Upload failed: ${json.decode(decoded)['detail']}');
  }

  /// Fetches the fields for a document by file ID.
  ///
  /// Returns a map with keys `document_type_name` (String?) and `fields` (`List<dynamic>`).
  static Future<Map<String, dynamic>> getDocumentFields({
    required String token,
    required int fileId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/fields/$fileId');
    final http.Response res = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) {
      return json.decode(decoded) as Map<String, dynamic>;
    }
    throw Exception(
        'Failed to fetch fields: ${json.decode(decoded)['detail']}');
  }

  /// Fills document fields and returns the updated document data.
  static Future<Map<String, dynamic>> fillDocumentFields({
    required String token,
    required int fileId,
    required List<Map<String, dynamic>> fillData,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/fill/$fileId');
    final request = http.MultipartRequest('POST', uri);

    AuthRequestHeaders.apply(request, token);

    List<Map<String, dynamic>> metadataFillData = [];
    int counter = 0;

    for (var i = 0; i < fillData.length; i++) {
      final item = Map<String, dynamic>.from(fillData[i]);
      if (item.containsKey('_bytes')) {
        final bytes = item['_bytes'] as List<int>;
        final filename = item['new_text'] ?? 'image_$counter.png';
        request.files.add(
            http.MultipartFile.fromBytes('files', bytes, filename: filename));
        item.remove('_bytes');
        counter++;
      }
      metadataFillData.add(item);
    }

    request.fields['metadata'] = json.encode({'fill_data': metadataFillData});

    final streamedResponse =
        await request.send().timeout(const Duration(seconds: timeoutSeconds));
    final res = await http.Response.fromStream(streamedResponse);

    final String decoded = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw Exception(
        'Fill failed: ${json.decode(decoded)['detail'] ?? res.body}',
      );
    }
    return json.decode(decoded) as Map<String, dynamic>;
  }

  /// Fills a document with a structured payload using the shared /fill endpoint.
  static Future<Map<String, dynamic>> fillDocumentStructured({
    required String token,
    required int fileId,
    required Map<String, dynamic> payload,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/fill/$fileId');
    final request = http.MultipartRequest('POST', uri);

    AuthRequestHeaders.apply(request, token);
    final payloadCopy = _prepareStructuredPayloadForMultipart(
      request: request,
      payload: payload,
    );

    request.fields['metadata'] = json.encode(payloadCopy);

    final streamedResponse =
        await request.send().timeout(const Duration(seconds: timeoutSeconds));
    final res = await http.Response.fromStream(streamedResponse);

    final String decoded = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw Exception(
        'Fill failed: ${json.decode(decoded)['detail'] ?? res.body}',
      );
    }
    return json.decode(decoded) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getFileBundle({
    required String token,
    required int fileId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/$fileId/bundle');
    final http.Response res = await http.get(uri, headers: <String, String>{
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: timeoutSeconds));

    return _decodeJsonResponse(
      response: res,
      errorPrefix: 'Failed to fetch bundle',
    );
  }

  static Future<Map<String, dynamic>> createFileBundle({
    required String token,
    required Map<String, dynamic> metadata,
    List<BundleUploadFile> files = const <BundleUploadFile>[],
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/bundle');
    final http.MultipartRequest request = http.MultipartRequest('POST', uri)
      ..headers.addAll(AuthRequestHeaders.forRequest(token));

    _attachBundleFiles(request: request, files: files);
    request.fields['metadata'] = json.encode(metadata);

    return _sendMultipartJson(
      request: request,
      errorPrefix: 'Bundle create failed',
    );
  }

  static Future<Map<String, dynamic>> updateFileBundle({
    required String token,
    required int fileId,
    required Map<String, dynamic> metadata,
    List<BundleUploadFile> files = const <BundleUploadFile>[],
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/$fileId/bundle');
    final http.MultipartRequest request = http.MultipartRequest('POST', uri)
      ..headers.addAll(AuthRequestHeaders.forRequest(token));

    _attachBundleFiles(request: request, files: files);
    request.fields['metadata'] = json.encode(metadata);

    return _sendMultipartJson(
      request: request,
      errorPrefix: 'Bundle save failed',
    );
  }

  static Future<List<Map<String, dynamic>>> getFileLinks({
    required String token,
    required int fileId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/$fileId/links');
    final http.Response res = await http.get(uri, headers: <String, String>{
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: timeoutSeconds));

    final dynamic decoded = _decodeDynamicResponse(
      response: res,
      errorPrefix: 'Failed to fetch links',
    );
    if (decoded is List) {
      return decoded
          .map((dynamic item) =>
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>))
          .toList();
    }
    if (decoded is Map<String, dynamic>) {
      final List<dynamic> items =
          (decoded['items'] as List<dynamic>?) ?? const <dynamic>[];
      return items
          .map((dynamic item) =>
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>))
          .toList();
    }
    throw const FormatException('Unexpected file links response');
  }

  static Future<Map<String, dynamic>> linkExistingChild({
    required String token,
    required int fileId,
    required Map<String, dynamic> payload,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/$fileId/links');
    final http.Response res = await http
        .post(
          uri,
          headers: <String, String>{
            ...AuthRequestHeaders.forRequest(token),
            'Content-Type': 'application/json',
          },
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    return _decodeJsonResponse(
      response: res,
      errorPrefix: 'Failed to link child document',
    );
  }

  static Future<Map<String, dynamic>> updateFileLinks({
    required String token,
    required int fileId,
    required List<Map<String, dynamic>> items,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/$fileId/links');
    final http.Response res = await http
        .put(
          uri,
          headers: <String, String>{
            ...AuthRequestHeaders.forRequest(token),
            'Content-Type': 'application/json',
          },
          body: json.encode(<String, dynamic>{'items': items}),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    return _decodeJsonResponse(
      response: res,
      errorPrefix: 'Failed to update links',
    );
  }

  static Future<void> unlinkFileLink({
    required String token,
    required int linkId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/file-links/$linkId');
    final http.Response res = await http.delete(uri, headers: <String, String>{
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: timeoutSeconds));

    if (res.statusCode == 200 || res.statusCode == 204) {
      return;
    }

    _throwApiException(
      response: res,
      errorPrefix: 'Failed to unlink child document',
    );
  }

  static Future<Map<String, dynamic>> createFileExportJob({
    required String token,
    required int fileId,
    required Map<String, dynamic> payload,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/$fileId/exports');
    final http.Response res = await http
        .post(
          uri,
          headers: <String, String>{
            ...AuthRequestHeaders.forRequest(token),
            'Content-Type': 'application/json',
          },
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    return _decodeJsonResponse(
      response: res,
      errorPrefix: 'Failed to create export job',
    );
  }

  static Future<Map<String, dynamic>> getExportJob({
    required String token,
    required int jobId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/export-jobs/$jobId');
    final http.Response res = await http.get(uri, headers: <String, String>{
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: timeoutSeconds));

    return _decodeJsonResponse(
      response: res,
      errorPrefix: 'Failed to fetch export job',
    );
  }

  static Future<String> generateExportTempUrl({
    required String token,
    required int jobId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/exports/$jobId/generate_temp_url');
    final http.Response res = await http.get(uri, headers: <String, String>{
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: timeoutSeconds));

    final Map<String, dynamic> decoded = _decodeJsonResponse(
      response: res,
      errorPrefix: 'Failed to generate export download URL',
    );
    return _resolveTempUrl(decoded['temp_url']);
  }

  static Map<String, dynamic> _prepareStructuredPayloadForMultipart({
    required http.MultipartRequest request,
    required Map<String, dynamic> payload,
  }) {
    final payloadCopy = Map<String, dynamic>.from(payload);
    final rawItems = payloadCopy['items'];
    if (rawItems is! List) {
      return payloadCopy;
    }

    final updatedItems = <Map<String, dynamic>>[];

    void attachBytes({
      required Map<String, dynamic> map,
      required String bytesKey,
      required String fileNameKey,
      required String fallbackFileName,
    }) {
      if (!map.containsKey(bytesKey)) return;
      final bytes = map[bytesKey] as List<int>;
      final filename = (map[fileNameKey] as String?)?.trim().isNotEmpty == true
          ? (map[fileNameKey] as String).trim()
          : fallbackFileName;
      request.files.add(
        http.MultipartFile.fromBytes('files', bytes, filename: filename),
      );
      map.remove(bytesKey);
    }

    for (int counter = 0; counter < rawItems.length; counter++) {
      final dynamic rawItem = rawItems[counter];
      if (rawItem is! Map) continue;

      final itemCopy = Map<String, dynamic>.from(rawItem);
      attachBytes(
        map: itemCopy,
        bytesKey: '_bytes',
        fileNameKey: 'image',
        fallbackFileName: 'image_$counter.png',
      );
      attachBytes(
        map: itemCopy,
        bytesKey: '_bytes_before',
        fileNameKey: 'image_before',
        fallbackFileName: 'before_$counter.png',
      );
      attachBytes(
        map: itemCopy,
        bytesKey: '_bytes_improv',
        fileNameKey: 'image_improv',
        fallbackFileName: 'improv_$counter.png',
      );
      attachBytes(
        map: itemCopy,
        bytesKey: '_bytes_after',
        fileNameKey: 'image_after',
        fallbackFileName: 'after_$counter.png',
      );

      for (final entry in <(String, String)>[
        ('before', 'before_$counter.png'),
        ('improv', 'improv_$counter.png'),
        ('after', 'after_$counter.png'),
      ]) {
        final nestedKey = entry.$1;
        final fallbackFileName = entry.$2;
        final nestedRaw = itemCopy[nestedKey];
        if (nestedRaw is! Map) continue;

        final nestedMap = Map<String, dynamic>.from(nestedRaw);
        attachBytes(
          map: nestedMap,
          bytesKey: '_bytes',
          fileNameKey: 'image',
          fallbackFileName: fallbackFileName,
        );
        itemCopy[nestedKey] = nestedMap;
      }

      updatedItems.add(itemCopy);
    }

    payloadCopy['items'] = updatedItems;
    return payloadCopy;
  }

  static void _attachBundleFiles({
    required http.MultipartRequest request,
    required List<BundleUploadFile> files,
  }) {
    for (final BundleUploadFile file in files) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          file.bytes,
          filename: file.filename,
          contentType: file.contentType,
        ),
      );
    }
  }

  static Future<Map<String, dynamic>> _sendMultipartJson({
    required http.MultipartRequest request,
    required String errorPrefix,
  }) async {
    final http.StreamedResponse streamedResponse =
        await request.send().timeout(const Duration(seconds: timeoutSeconds));
    final http.Response response =
        await http.Response.fromStream(streamedResponse);

    return _decodeJsonResponse(
      response: response,
      errorPrefix: errorPrefix,
    );
  }

  static Map<String, dynamic> _decodeJsonResponse({
    required http.Response response,
    required String errorPrefix,
  }) {
    final dynamic decoded = _decodeDynamicResponse(
      response: response,
      errorPrefix: errorPrefix,
    );
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    throw FormatException(
      '$errorPrefix: unexpected response type ${decoded.runtimeType}',
    );
  }

  static dynamic _decodeDynamicResponse({
    required http.Response response,
    required String errorPrefix,
  }) {
    final String decodedBody = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decodedBody.trim().isEmpty) return <String, dynamic>{};
      return json.decode(decodedBody);
    }

    _throwApiException(
      response: response,
      errorPrefix: errorPrefix,
      decodedBody: decodedBody,
    );
  }

  static Never _throwApiException({
    required http.Response response,
    required String errorPrefix,
    String? decodedBody,
  }) {
    final String body = decodedBody ?? utf8.decode(response.bodyBytes);
    String detail = body;
    if (body.trim().isNotEmpty) {
      try {
        final dynamic parsed = json.decode(body);
        if (parsed is Map<String, dynamic>) {
          detail = (parsed['detail'] ?? parsed['message'] ?? body).toString();
        }
      } catch (_) {}
    }

    throw FileManageApiException(
      statusCode: response.statusCode,
      message: '$errorPrefix: $detail',
    );
  }

  static String _safeUploadFilename(String filename) {
    final trimmed = filename.trim();
    if (trimmed.isEmpty) return 'draft_attachment.bin';
    return trimmed
        .split(RegExp(r'[/\\]+'))
        .where((segment) => segment.trim().isNotEmpty)
        .last
        .replaceAll(RegExp(r'[\r\n]+'), '_');
  }

  static MediaType? _mediaTypeForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    return null;
  }

  static Future<String> _resolveTempUrl(dynamic tempUrlValue) async {
    final String tempUrl = tempUrlValue?.toString().trim() ?? '';
    if (tempUrl.isEmpty) {
      throw const FormatException('Missing temp_url in response');
    }

    if (!tempUrl.startsWith('/')) {
      return tempUrl;
    }

    final String rootUrl = await ApiConfigService.getApiUrl('fileManagement');
    final Uri uri = Uri.parse(rootUrl);
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$tempUrl';
  }

  /// Updates the content of a file.
  static Future<void> updateFileContent({
    required String token,
    required int fileId,
    required Map<String, dynamic> updatedContent,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/update/$fileId');
    final http.Response res = await http
        .put(
          uri,
          headers: {
            ...AuthRequestHeaders.forRequest(token),
            'Content-Type': 'application/json',
          },
          body: json.encode(updatedContent),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) {
      return;
    }

    final dynamic body = decoded.isEmpty ? null : json.decode(decoded);
    final String message = body is Map<String, dynamic>
        ? (body['detail']?.toString() ?? decoded)
        : decoded;
    throw FileManageApiException(
      statusCode: res.statusCode,
      message: message,
    );
  }

  /// Deletes a document by document ID.
  static Future<void> deleteDocument({
    required String token,
    required int docId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/delete/$docId');
    final http.Response res = await http.delete(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    if (res.statusCode != 200) {
      throw Exception(
        'Delete failed: ${json.decode(utf8.decode(res.bodyBytes))['detail']}',
      );
    }
  }

  /// Deletes a document version by version ID.
  static Future<void> deleteVersion({
    required String token,
    required int versionId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/version/$versionId');
    final http.Response res = await http.delete(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    if (res.statusCode != 200) {
      final String decoded = utf8.decode(res.bodyBytes);
      throw Exception(
          'Failed to delete version: ${json.decode(decoded)['detail']}');
    }
  }

  /// Fetches the list of document versions for a document.
  static Future<List<dynamic>> getDocumentVersions({
    required String token,
    required int docId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/versions/$docId');
    final http.Response res =
        await http.get(uri, headers: {...AuthRequestHeaders.forRequest(token)});
    if (res.statusCode == 200) {
      final Map<String, dynamic> map = json.decode(utf8.decode(res.bodyBytes));
      return map['items'] as List<dynamic>;
    }
    throw Exception('Failed to fetch version list');
  }

  /// Generates a temporary download URL for a document version.
  static Future<String> generateTempUrl({
    required String token,
    required int versionId,
    String kind = 'docx',
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse(
        '$baseUrlValue/versions/$versionId/generate_temp_url?kind=$kind');
    final http.Response res =
        await http.get(uri, headers: {...AuthRequestHeaders.forRequest(token)});

    if (res.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(utf8.decode(res.bodyBytes));
      return _resolveTempUrl(data['temp_url']);
    }
    throw Exception('Failed to fetch temporary URL');
  }

  /// Creates a photo document for the given site and images.
  static Future<CreatedDocumentResult> createPhotoDoc({
    required String token,
    required int siteId,
    required List<Map<String, dynamic>> images,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/create_photo_doc');
    final request = http.MultipartRequest('POST', uri);

    AuthRequestHeaders.apply(request, token);

    List<Map<String, dynamic>> imagesMetadata = [];

    for (var i = 0; i < images.length; i++) {
      final img = Map<String, dynamic>.from(images[i]);
      if (img.containsKey('_bytes')) {
        final bytes = img['_bytes'] as List<int>;
        final filename = img['filename'] ?? 'image_$i.png';
        request.files.add(
            http.MultipartFile.fromBytes('files', bytes, filename: filename));
        img.remove('_bytes');
      }
      imagesMetadata.add(img);
    }

    request.fields['metadata'] = json.encode({
      'site_id': siteId,
      'images': imagesMetadata,
    });

    final streamedResponse =
        await request.send().timeout(const Duration(seconds: timeoutSeconds));
    final res = await http.Response.fromStream(streamedResponse);

    final String decoded = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw Exception(
        'Create failed: ${json.decode(decoded)['detail']}',
      );
    }

    return CreatedDocumentResult.fromJson(
      json.decode(decoded) as Map<String, dynamic>,
    );
  }

  /// Creates an audit fix document using the backend's flat multipart metadata shape.
  static Future<CreatedDocumentResult> createAuditFixDoc({
    required String token,
    required int siteId,
    required String auditDate,
    required List<Map<String, dynamic>> items,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/create_audit_fix_doc');
    final request = http.MultipartRequest('POST', uri);

    AuthRequestHeaders.apply(request, token);
    final itemsMetadata = <Map<String, dynamic>>[];

    for (var i = 0; i < items.length; i++) {
      final item = Map<String, dynamic>.from(items[i]);
      if (item.containsKey('_bytes_before')) {
        final bytesBefore = item['_bytes_before'] as List<int>;
        final filename = item['image_before'] ?? 'before_$i.png';
        request.files.add(
          http.MultipartFile.fromBytes('files', bytesBefore,
              filename: filename),
        );
        item.remove('_bytes_before');
      }
      if (item.containsKey('_bytes_improv')) {
        final bytesImprov = item['_bytes_improv'] as List<int>;
        final filename = item['image_improv'] ?? 'improv_$i.png';
        request.files.add(
          http.MultipartFile.fromBytes('files', bytesImprov,
              filename: filename),
        );
        item.remove('_bytes_improv');
      }
      if (item.containsKey('_bytes_after')) {
        final bytesAfter = item['_bytes_after'] as List<int>;
        final filename = item['image_after'] ?? 'after_$i.png';
        request.files.add(
          http.MultipartFile.fromBytes('files', bytesAfter, filename: filename),
        );
        item.remove('_bytes_after');
      }
      itemsMetadata.add(item);
    }

    request.fields['metadata'] = json.encode({
      'site_id': siteId,
      'audit_date': auditDate,
      'items': itemsMetadata,
    });

    final streamedResponse =
        await request.send().timeout(const Duration(seconds: timeoutSeconds));
    final res = await http.Response.fromStream(streamedResponse);

    final String decoded = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw Exception(
        'Create failed: ${json.decode(decoded)['detail']}',
      );
    }

    return CreatedDocumentResult.fromJson(
      json.decode(decoded) as Map<String, dynamic>,
    );
  }

  /*──────── 簽署流程相關 ────────*/
  /// Fetches the list of signature tasks assigned to the user.
  static Future<List<Map<String, dynamic>>> getMySignTasks({
    required String token,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/sign/tasks');
    final http.Response resp =
        await http.get(uri, headers: {...AuthRequestHeaders.forRequest(token)});
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch signature tasks: ${resp.statusCode}');
    }
    final List<dynamic> data = jsonDecode(resp.body);
    return data.cast<Map<String, dynamic>>();
  }

  /// Fetches a single signature task assigned to the current user.
  static Future<Map<String, dynamic>> getSingleSignTask({
    required String token,
    required int taskId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/sign/task/$taskId');
    final http.Response resp = await http.get(
      uri,
      headers: {...AuthRequestHeaders.forRequest(token)},
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch signature task: ${resp.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(resp.bodyBytes)));
  }

  /// Gets the download URL for a document version.
  static Future<String> getVersionDownloadUrl({
    required String token,
    required int versionId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/files/download/$versionId');
    final http.Response resp =
        await http.get(uri, headers: {...AuthRequestHeaders.forRequest(token)});
    if (resp.statusCode == 200) {
      final Map<String, dynamic> m = jsonDecode(resp.body);
      if (m.containsKey('url')) {
        return m['url'] as String;
      } else {
        throw Exception('Backend did not return download URL');
      }
    } else {
      throw Exception('Failed to fetch download URL: ${resp.statusCode}');
    }
  }

  /// Submits a signature or comment for a signature task.
  static Future<Map<String, dynamic>> submitSignature({
    required String token,
    required int taskId,
    required String status, // 'signed' | 'commented' | 'rejected' | 'skipped'
    Uint8List? pngBytes, // Only required for 'signed'
    required String comment,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/sign/submit/$taskId');
    final http.MultipartRequest request = http.MultipartRequest('POST', uri)
      ..headers.addAll(AuthRequestHeaders.forRequest(token))
      ..fields['status'] = status
      ..fields['comment'] = comment;

    if (status == 'signed') {
      if (pngBytes == null) {
        throw Exception('Missing signature file');
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          pngBytes,
          filename: 'signature.png',
          contentType: MediaType('image', 'png'),
        ),
      );
    }

    final http.StreamedResponse streamed = await request.send();
    final http.Response resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      final String decoded = utf8.decode(resp.bodyBytes);
      String detail = decoded;
      try {
        final dynamic body = jsonDecode(decoded);
        if (body is Map<String, dynamic>) {
          detail = (body['detail'] ?? body['message'] ?? decoded).toString();
        }
      } catch (_) {}
      throw Exception(
        'Signature submission failed: ${resp.statusCode} $detail',
      );
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// Fetches the list of document categories.
  static Future<List<dynamic>> getCategories({required String token}) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/document_categories');
    final http.Response res =
        await http.get(uri, headers: {...AuthRequestHeaders.forRequest(token)});
    if (res.statusCode == 200) return json.decode(res.body) as List<dynamic>;
    throw Exception('Failed to load categories: ${res.statusCode}');
  }

  /// Fetches the list of document types for a given category.
  static Future<List<dynamic>> getTypes({
    required String token,
    required int categoryId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri =
        Uri.parse('$baseUrlValue/document_types?category_id=$categoryId');
    final http.Response res =
        await http.get(uri, headers: {...AuthRequestHeaders.forRequest(token)});
    if (res.statusCode == 200) return json.decode(res.body) as List<dynamic>;
    throw Exception('Failed to load document types: ${res.statusCode}');
  }

  /// Creates a new document from a template and returns the created document payload.
  static Future<CreatedDocumentResult> createDocFromTemplate({
    required String token,
    required int siteId,
    required String filePrefix,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/create_from_template');
    final http.MultipartRequest req = http.MultipartRequest('POST', uri)
      ..headers.addAll(AuthRequestHeaders.forRequest(token))
      ..fields['site_id'] = '$siteId'
      ..fields['file_prefix'] = filePrefix;

    final http.Response res = await http.Response.fromStream(await req.send())
        .timeout(const Duration(seconds: timeoutSeconds));

    final String body = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) {
      return CreatedDocumentResult.fromJson(
        json.decode(body) as Map<String, dynamic>,
      );
    }
    throw Exception(
        'Create-from-template failed: ${json.decode(body)['detail']}');
  }

  /// Fetches the list of signature assignments for a document version.
  static Future<List<Map<String, dynamic>>> getSignatureAssignments({
    required String token,
    required int versionId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse('$baseUrlValue/sign/assignments/$versionId');
    final http.Response res = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    final String body = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) {
      final List<dynamic> arr = json.decode(body);
      return arr.cast<Map<String, dynamic>>();
    }
    throw Exception(
        'Failed to fetch assignments: ${json.decode(body)['detail']}');
  }
}
