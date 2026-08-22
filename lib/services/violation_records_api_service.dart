import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config_service.dart';
import 'auth_request_headers.dart';

class ViolationAnalytics {
  final ViolationAnalyticsSummary summary;
  final List<ViolationAnalyticsTrendPoint> trend;
  final List<ViolationAnalyticsTypeStat> byType;
  final List<ViolationAnalyticsSiteStat> bySite;
  final List<ViolationAnalyticsHourStat> byHour;

  const ViolationAnalytics({
    required this.summary,
    required this.trend,
    required this.byType,
    required this.bySite,
    required this.byHour,
  });

  factory ViolationAnalytics.empty() {
    return const ViolationAnalytics(
      summary: ViolationAnalyticsSummary(
        total: 0,
        today: 0,
        topSite: null,
        topType: null,
      ),
      trend: <ViolationAnalyticsTrendPoint>[],
      byType: <ViolationAnalyticsTypeStat>[],
      bySite: <ViolationAnalyticsSiteStat>[],
      byHour: <ViolationAnalyticsHourStat>[],
    );
  }

  factory ViolationAnalytics.fromJson(Map<String, dynamic> json) {
    final List<ViolationAnalyticsTypeStat> byType =
        _readList(json['by_type'] ?? json['byType'] ?? json['types'])
            .map(ViolationAnalyticsTypeStat.fromJson)
            .toList();
    final List<ViolationAnalyticsSiteStat> bySite =
        _readList(json['by_site'] ?? json['bySite'] ?? json['sites'])
            .map(ViolationAnalyticsSiteStat.fromJson)
            .toList();

    return ViolationAnalytics(
      summary: ViolationAnalyticsSummary.fromJson(
        _readMap(json['summary']),
        byType: byType,
        bySite: bySite,
      ),
      trend: _readList(json['trend'] ?? json['series'])
          .map(ViolationAnalyticsTrendPoint.fromJson)
          .toList(),
      byType: byType,
      bySite: bySite,
      byHour: _readList(json['by_hour'] ?? json['byHour'] ?? json['hours'])
          .map(ViolationAnalyticsHourStat.fromJson)
          .toList(),
    );
  }

  bool get hasData {
    return summary.total > 0 ||
        trend.any((ViolationAnalyticsTrendPoint point) => point.count > 0) ||
        byType.any((ViolationAnalyticsTypeStat item) => item.count > 0) ||
        bySite.any((ViolationAnalyticsSiteStat item) => item.count > 0) ||
        byHour.any((ViolationAnalyticsHourStat item) => item.count > 0);
  }
}

class ViolationAnalyticsSummary {
  final int total;
  final int today;
  final ViolationAnalyticsTopItem? topSite;
  final ViolationAnalyticsTopItem? topType;

  const ViolationAnalyticsSummary({
    required this.total,
    required this.today,
    required this.topSite,
    required this.topType,
  });

  factory ViolationAnalyticsSummary.fromJson(
    Map<String, dynamic> json, {
    required List<ViolationAnalyticsTypeStat> byType,
    required List<ViolationAnalyticsSiteStat> bySite,
  }) {
    return ViolationAnalyticsSummary(
      total: _readInt(json['total'] ?? json['total_count']),
      today: _readInt(json['today'] ?? json['today_count']),
      topSite: ViolationAnalyticsTopItem.fromDynamic(json['top_site']) ??
          (bySite.isNotEmpty
              ? ViolationAnalyticsTopItem(
                  label: bySite.first.siteName,
                  count: bySite.first.count,
                )
              : null),
      topType: ViolationAnalyticsTopItem.fromDynamic(json['top_type']) ??
          (byType.isNotEmpty
              ? ViolationAnalyticsTopItem(
                  label: byType.first.label,
                  count: byType.first.count,
                )
              : null),
    );
  }
}

class ViolationAnalyticsTopItem {
  final String label;
  final int count;

  const ViolationAnalyticsTopItem({
    required this.label,
    required this.count,
  });

  static ViolationAnalyticsTopItem? fromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return ViolationAnalyticsTopItem(label: value, count: 0);
    }
    final Map<String, dynamic> json = _readMap(value);
    if (json.isEmpty) return null;
    return ViolationAnalyticsTopItem(
      label: _readString(json['label'] ?? json['site_name'] ?? json['type']),
      count: _readInt(json['count']),
    );
  }
}

class ViolationAnalyticsTrendPoint {
  final String bucket;
  final int count;

  const ViolationAnalyticsTrendPoint({
    required this.bucket,
    required this.count,
  });

  factory ViolationAnalyticsTrendPoint.fromJson(Map<String, dynamic> json) {
    return ViolationAnalyticsTrendPoint(
      bucket: _readString(json['bucket'] ?? json['label'] ?? json['date']),
      count: _readInt(json['count'] ?? json['total']),
    );
  }
}

class ViolationAnalyticsTypeStat {
  final String type;
  final String label;
  final int count;

  const ViolationAnalyticsTypeStat({
    required this.type,
    required this.label,
    required this.count,
  });

  factory ViolationAnalyticsTypeStat.fromJson(Map<String, dynamic> json) {
    final String type = _readString(json['type'] ?? json['key']);
    return ViolationAnalyticsTypeStat(
      type: type,
      label: _readString(json['label'] ?? json['name']).isNotEmpty
          ? _readString(json['label'] ?? json['name'])
          : type,
      count: _readInt(json['count'] ?? json['total']),
    );
  }
}

class ViolationAnalyticsSiteStat {
  final int? siteId;
  final String siteName;
  final int count;

  const ViolationAnalyticsSiteStat({
    required this.siteId,
    required this.siteName,
    required this.count,
  });

  factory ViolationAnalyticsSiteStat.fromJson(Map<String, dynamic> json) {
    return ViolationAnalyticsSiteStat(
      siteId: _readNullableInt(json['site_id'] ?? json['id']),
      siteName: _readString(json['site_name'] ?? json['name'] ?? json['label']),
      count: _readInt(json['count'] ?? json['total']),
    );
  }
}

class ViolationAnalyticsHourStat {
  final int hour;
  final int count;

  const ViolationAnalyticsHourStat({
    required this.hour,
    required this.count,
  });

  factory ViolationAnalyticsHourStat.fromJson(Map<String, dynamic> json) {
    return ViolationAnalyticsHourStat(
      hour: _readInt(json['hour'] ?? json['bucket']),
      count: _readInt(json['count'] ?? json['total']),
    );
  }
}

/// Filter values available to the current user for violation queries.
class ViolationFilterOptions {
  const ViolationFilterOptions({
    required this.cameras,
    required this.violationTypes,
  });

  const ViolationFilterOptions.empty()
      : cameras = const <ViolationCameraFilterOption>[],
        violationTypes = const <ViolationTypeFilterOption>[];

  final List<ViolationCameraFilterOption> cameras;
  final List<ViolationTypeFilterOption> violationTypes;

  factory ViolationFilterOptions.fromJson(Map<String, dynamic> json) {
    final Set<String> cameraIds = <String>{};
    final List<ViolationCameraFilterOption> cameras =
        <ViolationCameraFilterOption>[];
    for (final Map<String, dynamic> item
        in _readList(json['cameras'] ?? json['streams'])) {
      final ViolationCameraFilterOption camera =
          ViolationCameraFilterOption.fromJson(item);
      if (camera.streamId.isNotEmpty && cameraIds.add(camera.streamId)) {
        cameras.add(camera);
      }
    }

    final Set<String> typeCodes = <String>{};
    final List<ViolationTypeFilterOption> violationTypes =
        <ViolationTypeFilterOption>[];
    for (final Map<String, dynamic> item in _readList(
      json['violation_types'] ?? json['violationTypes'] ?? json['types'],
    )) {
      final ViolationTypeFilterOption type =
          ViolationTypeFilterOption.fromJson(item);
      if (type.code.isNotEmpty && typeCodes.add(type.code)) {
        violationTypes.add(type);
      }
    }

    return ViolationFilterOptions(
      cameras: cameras,
      violationTypes: violationTypes,
    );
  }
}

class ViolationCameraFilterOption {
  const ViolationCameraFilterOption({
    required this.streamId,
    required this.name,
  });

  final String streamId;
  final String name;

  factory ViolationCameraFilterOption.fromJson(Map<String, dynamic> json) {
    final String streamId = _firstNonEmpty(json, <String>[
      'stream_id',
      'streamId',
      'camera_id',
      'cameraId',
      'id',
    ]);
    final String name = _firstNonEmpty(json, <String>[
      'name',
      'stream_name',
      'streamName',
      'camera_name',
      'cameraName',
      'label',
    ]);
    return ViolationCameraFilterOption(
      streamId: streamId,
      name: name.isEmpty ? streamId : name,
    );
  }
}

class ViolationTypeFilterOption {
  const ViolationTypeFilterOption({
    required this.code,
    required this.label,
  });

  final String code;
  final String label;

  factory ViolationTypeFilterOption.fromJson(Map<String, dynamic> json) {
    final String code = _firstNonEmpty(json, <String>[
      'code',
      'violation_type',
      'violationType',
      'type',
      'key',
    ]);
    final String label = _firstNonEmpty(json, <String>[
      'label',
      'name',
      'display_name',
      'displayName',
    ]);
    return ViolationTypeFilterOption(
      code: code,
      label: label.isEmpty ? code : label,
    );
  }
}

/// Service class for interacting with the violation records backend API.
///
/// Provides static methods for fetching violation lists, site lists, violation details, and image URLs.
class ViolationRecordsAPIService {
  /// Timeout for HTTP requests, in seconds.
  static const int timeoutSeconds = 600;
  static const int _filterOptionsTimeoutSeconds = 30;

  /// Get the base URL from configuration service
  static Future<String> get baseUrl async {
    return await ApiConfigService.getApiUrl('violationRecords');
  }

  /// Fetches a paginated list of violation records from the backend.
  ///
  /// [token] The authentication token (required).
  /// [keyword] Optional keyword for searching.
  /// [siteId] Optional site ID for filtering.
  /// [startTime] Optional start time for filtering.
  /// [endTime] Optional end time for filtering.
  /// [limit] Number of records per page (default: 20).
  /// [offset] Offset for pagination (default: 0).
  ///
  /// Returns a map containing the list of violations and metadata.
  static Future<Map<String, dynamic>> getViolations({
    required String token,
    String? keyword,
    int? siteId,
    int? groupId,
    String? streamId,
    String? violationType,
    bool? flagged,
    String? reviewStatus,
    DateTime? startTime,
    DateTime? endTime,
    int limit = 20,
    int offset = 0,
  }) async {
    final Map<String, String> queryParams = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
    };

    if (keyword != null && keyword.isNotEmpty) queryParams["keyword"] = keyword;
    if (siteId != null) queryParams["site_id"] = siteId.toString();
    if (groupId != null) queryParams["group_id"] = groupId.toString();
    if (streamId != null && streamId.isNotEmpty) {
      queryParams['stream_id'] = streamId;
    }
    if (violationType != null && violationType.isNotEmpty) {
      queryParams['violation_type'] = violationType;
    }
    if (flagged != null) queryParams["flagged"] = flagged.toString();
    if (reviewStatus != null && reviewStatus.isNotEmpty) {
      queryParams["review_status"] = reviewStatus;
    }
    if (startTime != null) {
      queryParams["start_time"] = startTime.toIso8601String();
    }
    if (endTime != null) {
      queryParams["end_time"] = endTime.toIso8601String();
    }

    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse("$baseUrlValue/violations")
        .replace(queryParameters: queryParams);
    final http.Response response = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200) {
      final dynamic data = _tryDecodeJson(decoded);
      if (data is Map<String, dynamic>) return data;
      throw Exception(_formatResponseError(
        response,
        fallbackMessage: 'Failed to parse violations response',
      ));
    }
    throw Exception(_formatResponseError(
      response,
      fallbackMessage: 'Failed to fetch violations',
    ));
  }

  /// Fetches camera and violation-type values allowed for the current scope.
  static Future<ViolationFilterOptions> getViolationFilterOptions({
    required String token,
    int? siteId,
    int? groupId,
  }) async {
    final Map<String, String> queryParams = <String, String>{};
    if (siteId != null) queryParams['site_id'] = siteId.toString();
    if (groupId != null) queryParams['group_id'] = groupId.toString();

    final String baseUrlValue = (await baseUrl).replaceAll(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$baseUrlValue/filter-options').replace(
      queryParameters: queryParams,
    );
    final http.Response response = await http.get(uri,
        headers: <String, String>{
          ...AuthRequestHeaders.forRequest(token)
        }).timeout(const Duration(seconds: _filterOptionsTimeoutSeconds));

    final String decoded = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200) {
      final dynamic data = _tryDecodeJson(decoded);
      if (data is Map<String, dynamic>) {
        return ViolationFilterOptions.fromJson(data);
      }
      throw Exception(_formatResponseError(
        response,
        fallbackMessage: 'Failed to parse violation filter options',
      ));
    }
    throw Exception(_formatResponseError(
      response,
      fallbackMessage: 'Failed to fetch violation filter options',
    ));
  }

  static Future<ViolationAnalytics> getViolationAnalytics({
    required String token,
    int? siteId,
    DateTime? startTime,
    DateTime? endTime,
    String? streamId,
    String? violationType,
    String bucket = 'day',
  }) async {
    final Map<String, String> queryParams = <String, String>{
      'bucket': bucket,
    };

    if (siteId != null) queryParams['site_id'] = siteId.toString();
    if (streamId != null && streamId.isNotEmpty) {
      queryParams['stream_id'] = streamId;
    }
    if (violationType != null && violationType.isNotEmpty) {
      queryParams['violation_type'] = violationType;
    }
    if (startTime != null) queryParams['start'] = startTime.toIso8601String();
    if (endTime != null) queryParams['end'] = endTime.toIso8601String();

    final String baseUrlValue = (await baseUrl).replaceAll(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$baseUrlValue/violations/analytics')
        .replace(queryParameters: queryParams);
    final http.Response response = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: timeoutSeconds));
    return _decodeAnalyticsResponse(response);
  }

  /// Fetches the list of sites available to the user.
  ///
  /// [token] The authentication token (required).
  /// Returns a list of site objects.
  static Future<List<dynamic>> getMySites({required String token}) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse("$baseUrlValue/my_sites");

    final http.Response response = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200) {
      final dynamic data = _tryDecodeJson(decoded);
      if (data is List<dynamic>) return data;
      throw Exception(_formatResponseError(
        response,
        fallbackMessage: 'Failed to parse sites response',
      ));
    }
    throw Exception(_formatResponseError(
      response,
      fallbackMessage: 'Failed to fetch sites',
    ));
  }

  /// Generates the URL for fetching a violation image (no token required).
  ///
  /// [imagePath] The path to the image file.
  /// Returns the full URL as a string.
  static Future<String> getViolationImageUrl(String imagePath) async {
    final List<String> candidates = await getViolationImageUrlCandidates(
      imagePath,
    );
    if (candidates.isEmpty) {
      throw Exception('Violation image path is empty.');
    }
    return candidates.first;
  }

  static Future<List<String>> getViolationImageUrlCandidates(
    String imagePath,
  ) async {
    final String trimmedPath = imagePath.trim();
    if (trimmedPath.isEmpty) return <String>[];

    final String baseUrlValue = (await baseUrl).replaceAll(RegExp(r'/+$'), '');
    final Uri? baseUri = Uri.tryParse(baseUrlValue);
    if (baseUri == null || !baseUri.hasScheme) return <String>[];

    final List<String> candidateBases = <String>[
      baseUrlValue,
      ..._relatedViolationImageBases(baseUri),
    ];
    final Set<String> seen = <String>{};
    final List<String> urls = <String>[];

    for (final String candidateBase in candidateBases) {
      final Uri? candidateUri = Uri.tryParse(candidateBase);
      if (candidateUri == null || !candidateUri.hasScheme) continue;
      final String url = candidateUri.replace(
        path: '${candidateUri.path.replaceAll(RegExp(r'/+$'), '')}'
            '/get_violation_image',
        queryParameters: <String, String>{'image_path': trimmedPath},
      ).toString();
      if (seen.add(url)) urls.add(url);
    }

    return urls;
  }

  static bool hasViolationThumbnail(dynamic record) {
    final Map<String, dynamic> data = _readMap(record);
    return _firstNonEmpty(data, _thumbnailUrlKeys).isNotEmpty ||
        _firstNonEmpty(data, _thumbnailPathKeys).isNotEmpty ||
        _firstNonEmpty(data, _imageUrlKeys).isNotEmpty ||
        _firstNonEmpty(data, _imagePathKeys).isNotEmpty;
  }

  static Future<String?> resolveViolationThumbnailUrl(dynamic record) async {
    final List<String> candidates =
        await resolveViolationThumbnailUrlCandidates(record);
    return candidates.isEmpty ? null : candidates.first;
  }

  static Future<List<String>> resolveViolationThumbnailUrlCandidates(
    dynamic record,
  ) async {
    final Map<String, dynamic> data = _readMap(record);
    final List<String> candidates = <String>[];
    final Set<String> seen = <String>{};

    Future<void> addReference(String value) async {
      final String trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return;
      final List<String> resolved = await _resolveImageReferenceCandidates(
        trimmed,
      );
      for (final String url in resolved) {
        if (seen.add(url)) candidates.add(url);
      }
    }

    for (final String key in _thumbnailUrlKeys) {
      await addReference(_readString(data[key]));
    }
    for (final String key in _thumbnailPathKeys) {
      await addReference(_readString(data[key]));
    }
    for (final String key in _imageUrlKeys) {
      await addReference(_readString(data[key]));
    }
    for (final String key in _imagePathKeys) {
      await addReference(_readString(data[key]));
    }

    return candidates;
  }

  static Future<String> resolveViolationImageUrl(
    dynamic record, {
    String? fallbackImageUrl,
  }) async {
    final List<String> candidates = await resolveViolationImageUrlCandidates(
      record,
      fallbackImageUrl: fallbackImageUrl,
    );
    if (candidates.isEmpty) {
      throw Exception('Violation image path is empty.');
    }
    return candidates.first;
  }

  static Future<List<String>> resolveViolationImageUrlCandidates(
    dynamic record, {
    String? fallbackImageUrl,
  }) async {
    final Map<String, dynamic> data = _readMap(record);
    final List<String> candidates = <String>[];
    final Set<String> seen = <String>{};

    Future<void> addReference(String value) async {
      final String trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return;
      final List<String> resolved = await _resolveImageReferenceCandidates(
        trimmed,
      );
      for (final String url in resolved) {
        if (seen.add(url)) candidates.add(url);
      }
    }

    for (final String key in _imagePathKeys) {
      await addReference(_readString(data[key]));
    }
    for (final String key in _imageUrlKeys) {
      await addReference(_readString(data[key]));
    }
    await addReference(fallbackImageUrl ?? '');

    return candidates;
  }

  /// Fetches the details of a single violation record by its ID.
  ///
  /// [token] The authentication token (required).
  /// [violationId] The ID of the violation to fetch.
  /// Returns a map containing the violation details.
  static Future<Map<String, dynamic>> getViolationById({
    required String token,
    required String violationId,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse("$baseUrlValue/violations/$violationId");
    final http.Response response = await http.get(uri, headers: {
      ...AuthRequestHeaders.forRequest(token)
    }).timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200) {
      final dynamic data = _tryDecodeJson(decoded);
      if (data is Map<String, dynamic>) return data;
      throw Exception(_formatResponseError(
        response,
        fallbackMessage: 'Failed to parse violation detail response',
      ));
    }
    throw Exception(_formatResponseError(
      response,
      fallbackMessage: 'Failed to fetch violation detail',
    ));
  }

  /// Updates the admin review state for a violation record.
  static Future<Map<String, dynamic>> updateViolationReview({
    required String token,
    required String recordId,
    required String reviewStatus,
    String? reviewNote,
  }) async {
    final String baseUrlValue = (await baseUrl).replaceAll(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$baseUrlValue/violations/$recordId/review');
    final Map<String, dynamic> payload = <String, dynamic>{
      'review_status': reviewStatus,
      if (reviewNote != null) 'review_note': reviewNote.trim(),
    };

    final http.Response response = await http
        .patch(
          uri,
          headers: <String, String>{
            ...AuthRequestHeaders.forRequest(token),
            'Content-Type': 'application/json',
          },
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200 || response.statusCode == 201) {
      if (decoded.trim().isEmpty) {
        return <String, dynamic>{'ok': true};
      }
      final dynamic data = _tryDecodeJson(decoded);
      if (data is Map<String, dynamic>) {
        return data;
      }
      return <String, dynamic>{'data': data ?? decoded};
    }
    if (response.statusCode == 204) {
      return <String, dynamic>{'ok': true};
    }

    final dynamic error = _tryDecodeJson(decoded);
    final String detail =
        error is Map<String, dynamic> ? _readString(error['detail']) : decoded;
    throw Exception(
      detail.isEmpty ? 'Failed to update violation review' : detail,
    );
  }

  static Future<List<Map<String, dynamic>>> getViolationAuditLog({
    required String token,
    required String recordId,
  }) async {
    final String baseUrlValue = (await baseUrl).replaceAll(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$baseUrlValue/violations/$recordId/audit-log');
    final http.Response response = await http.get(
      uri,
      headers: <String, String>{...AuthRequestHeaders.forRequest(token)},
    ).timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded.trim().isEmpty) return <Map<String, dynamic>>[];
      final dynamic data = _tryDecodeJson(decoded);
      final dynamic rawItems = data is Map<String, dynamic>
          ? data['items'] ?? data['history'] ?? data['audit_log']
          : data;
      if (rawItems is List) {
        return rawItems
            .whereType<Map<dynamic, dynamic>>()
            .map(
                (Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
      return <Map<String, dynamic>>[];
    }

    final dynamic error = _tryDecodeJson(decoded);
    final String detail =
        error is Map<String, dynamic> ? _readString(error['detail']) : decoded;
    throw Exception(detail.isEmpty ? 'Failed to load audit log' : detail);
  }

  /// Submits model feedback for a violation record.
  ///
  /// Use [type] values such as `false_positive`, `false_negative`,
  /// `wrong_class`, or `bad_bbox`. Bounding boxes are expected in original image
  /// coordinates as [left, top, right, bottom].
  static Future<Map<String, dynamic>> submitFeedback({
    required String token,
    required String recordId,
    required String type,
    String? targetDetectionId,
    String? originalLabel,
    String? correctedLabel,
    List<num>? originalBbox,
    List<num>? correctedBbox,
    String? note,
    String? modelVersion,
  }) async {
    final String baseUrlValue = (await baseUrl).replaceAll(RegExp(r'/+$'), '');
    final Uri uri = Uri.parse('$baseUrlValue/violations/$recordId/feedback');

    final Map<String, dynamic> payload = <String, dynamic>{
      'type': type,
      if (targetDetectionId != null && targetDetectionId.isNotEmpty)
        'target_detection_id': targetDetectionId,
      if (originalLabel != null && originalLabel.isNotEmpty)
        'original_label': originalLabel,
      if (correctedLabel != null && correctedLabel.isNotEmpty)
        'corrected_label': correctedLabel,
      if (originalBbox != null) 'original_bbox': originalBbox,
      if (correctedBbox != null) 'corrected_bbox': correctedBbox,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (modelVersion != null && modelVersion.isNotEmpty)
        'model_version': modelVersion,
    };

    final http.Response response = await http
        .post(
          uri,
          headers: <String, String>{
            ...AuthRequestHeaders.forRequest(token),
            'Content-Type': 'application/json',
          },
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    final String decoded = utf8.decode(response.bodyBytes);
    if (response.statusCode == 200 || response.statusCode == 201) {
      if (decoded.trim().isEmpty) {
        return <String, dynamic>{'ok': true};
      }
      final dynamic data = _tryDecodeJson(decoded);
      if (data is Map<String, dynamic>) {
        return data;
      }
      return <String, dynamic>{'data': data ?? decoded};
    }
    if (response.statusCode == 204) {
      return <String, dynamic>{'ok': true};
    }

    final dynamic error = _tryDecodeJson(decoded);
    final String detail =
        error is Map<String, dynamic> ? _readString(error['detail']) : decoded;
    throw Exception(
      detail.isEmpty ? 'Failed to submit feedback' : detail,
    );
  }
}

const List<String> _thumbnailUrlKeys = <String>[
  'thumbnail',
  'thumbnail_url',
  'thumbnailUrl',
  'thumb_url',
  'thumbUrl',
  'thumb',
  'preview',
  'preview_url',
  'previewUrl',
  'small_image_url',
  'smallImageUrl',
  'snapshot_thumbnail_url',
  'snapshotThumbnailUrl',
];

const List<String> _thumbnailPathKeys = <String>[
  'thumbnail_path',
  'thumbnailPath',
  'thumb_path',
  'thumbPath',
  'preview_path',
  'previewPath',
  'snapshot_thumbnail_path',
  'snapshotThumbnailPath',
];

const List<String> _imageUrlKeys = <String>[
  'image_url',
  'imageUrl',
  'image',
  'image_uri',
  'imageUri',
  'original_image_url',
  'originalImageUrl',
  'full_image_url',
  'fullImageUrl',
  'file_url',
  'fileUrl',
  'frame_url',
  'frameUrl',
  'snapshot_url',
  'snapshotUrl',
];

const List<String> _imagePathKeys = <String>[
  'image_path',
  'imagePath',
  'image_file',
  'imageFile',
  'image_filename',
  'imageFilename',
  'file_name',
  'fileName',
  'original_image_path',
  'originalImagePath',
  'full_image_path',
  'fullImagePath',
  'file_path',
  'filePath',
  'frame_path',
  'framePath',
  'snapshot_path',
  'snapshotPath',
];

ViolationAnalytics _decodeAnalyticsResponse(http.Response response) {
  final String decoded = utf8.decode(response.bodyBytes);
  if (response.statusCode == 200) {
    final dynamic body =
        decoded.isEmpty ? <String, dynamic>{} : _tryDecodeJson(decoded);
    if (body is Map<String, dynamic>) {
      return ViolationAnalytics.fromJson(body);
    }
    return ViolationAnalytics.empty();
  }
  if (response.statusCode == 204) {
    return ViolationAnalytics.empty();
  }

  throw Exception(_formatResponseError(
    response,
    fallbackMessage: 'Failed to fetch violation analytics',
  ));
}

List<Map<String, dynamic>> _readList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) =>
            item.map((dynamic key, dynamic value) => MapEntry('$key', value)))
        .toList();
  }
  return <Map<String, dynamic>>[];
}

Map<String, dynamic> _readMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map(
      (dynamic key, dynamic value) => MapEntry<String, dynamic>('$key', value),
    );
  }
  return <String, dynamic>{};
}

String _readString(dynamic value) {
  if (value == null) return '';
  return value.toString();
}

String _firstNonEmpty(Map<String, dynamic> data, List<String> keys) {
  for (final String key in keys) {
    final String value = _readString(data[key]).trim();
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

String _normalizeImageUrl(String value) {
  return value.trim();
}

String _formatResponseError(
  http.Response response, {
  required String fallbackMessage,
}) {
  final String decoded = utf8.decode(response.bodyBytes, allowMalformed: true);
  final dynamic error = _tryDecodeJson(decoded);
  String detail = '';

  if (error is Map<String, dynamic>) {
    final dynamic rawDetail =
        error['detail'] ?? error['message'] ?? error['error'];
    if (rawDetail is List) {
      detail = rawDetail.map((dynamic item) => item.toString()).join('; ');
    } else {
      detail = _readString(rawDetail);
    }
  } else if (error is List) {
    detail = error.map((dynamic item) => item.toString()).join('; ');
  } else {
    detail = decoded.trim();
  }

  final String status = response.statusCode.toString();
  if (detail.isEmpty) {
    return '$fallbackMessage ($status)';
  }
  return '$fallbackMessage ($status): $detail';
}

Future<List<String>> _resolveImageReferenceCandidates(String value) async {
  final String trimmed = _normalizeImageUrl(value);
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return <String>[trimmed];
  return ViolationRecordsAPIService.getViolationImageUrlCandidates(trimmed);
}

List<String> _relatedViolationImageBases(Uri baseUri) {
  final List<String> bases = <String>[];
  final List<String> segments = baseUri.pathSegments
      .where((String segment) => segment.trim().isNotEmpty)
      .toList(growable: false);

  Uri withSegments(List<String> nextSegments) {
    return baseUri.replace(
      pathSegments: nextSegments,
      query: null,
      queryParameters: null,
      fragment: null,
    );
  }

  if (segments.isNotEmpty && segments.last == 'violations') {
    bases.add(withSegments(segments.take(segments.length - 1).toList())
        .toString()
        .replaceAll(RegExp(r'/+$'), ''));
  } else {
    bases.add(withSegments(<String>[...segments, 'violations'])
        .toString()
        .replaceAll(RegExp(r'/+$'), ''));
  }

  return bases;
}

dynamic _tryDecodeJson(String value) {
  if (value.trim().isEmpty) return null;
  try {
    return json.decode(value);
  } catch (_) {
    return null;
  }
}

int _readInt(dynamic value) {
  return _readNullableInt(value) ?? 0;
}

int? _readNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
