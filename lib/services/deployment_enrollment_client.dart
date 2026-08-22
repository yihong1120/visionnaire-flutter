import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/deployment_profile.dart';

/// A safe failure returned by the fixed company-enrollment service.
///
/// The code intentionally contains no enrollment code, URL, response body, or
/// other sensitive transport detail.
final class DeploymentEnrollmentException implements Exception {
  const DeploymentEnrollmentException(this.code);

  final String code;

  @override
  String toString() => 'DeploymentEnrollmentException: $code';
}

/// Exchanges a one-time company enrollment code for a deployment identifier.
///
/// The enrollment exchange can select a deployment, but it cannot supply an
/// API URL. The caller must resolve the returned ID through the signed
/// deployment registry before using it.
abstract interface class DeploymentEnrollment {
  Future<String> exchange(String enrollmentCode);
}

/// Exchanges company invite codes with the immutable deployment registry.
///
/// The registry base is fixed at build time. This request deliberately has no
/// authorization or cookie header: an enrollment code is the only credential
/// accepted by the exchange endpoint.
final class DeploymentEnrollmentClient implements DeploymentEnrollment {
  DeploymentEnrollmentClient({
    required Uri registryBaseUri,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 10),
  })  : _registryBaseUri = _parseRegistryBaseUri(registryBaseUri),
        _httpClient = httpClient ?? http.Client(),
        _requestTimeout = requestTimeout {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'The enrollment timeout must be positive.',
      );
    }
  }

  /// Creates an enrollment client from the immutable registry build setting.
  factory DeploymentEnrollmentClient.fromBuildConfiguration() {
    return DeploymentEnrollmentClient(
      registryBaseUri: _parseRegistryUrl(_buildRegistryUrl),
    );
  }

  static const String _buildRegistryUrl = String.fromEnvironment(
    'DEPLOYMENT_REGISTRY_URL',
    defaultValue: 'https://registry.example.invalid',
  );
  static const int _maxResponseBytes = 1024;

  final Uri _registryBaseUri;
  final http.Client _httpClient;
  final Duration _requestTimeout;

  @override
  Future<String> exchange(String enrollmentCode) async {
    if (enrollmentCode.isEmpty) {
      throw const DeploymentEnrollmentException('invalid_enrollment_code');
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    final http.Request request = http.Request('POST', _exchangeUri())
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.addAll(const <String, String>{
        'accept': 'application/json',
        'cache-control': 'no-store',
        'content-type': 'application/json',
      })
      ..bodyBytes = utf8.encode(
        jsonEncode(<String, String>{'enrollment_code': enrollmentCode}),
      );

    final http.StreamedResponse response;
    try {
      response =
          await _httpClient.send(request).timeout(_remainingTimeout(stopwatch));
    } on TimeoutException {
      throw const DeploymentEnrollmentException('enrollment_unavailable');
    } on DeploymentEnrollmentException {
      rethrow;
    } catch (_) {
      throw const DeploymentEnrollmentException('enrollment_unavailable');
    }

    _requireSuccess(response.statusCode);
    _requireJsonContentType(response.headers['content-type']);
    final List<int> body = await _readBody(response, stopwatch);
    return _parseDeploymentId(body);
  }

  Uri _exchangeUri() {
    final String base = _registryBaseUri.toString().replaceFirst(
          RegExp(r'/+$'),
          '',
        );
    return Uri.parse('$base/v1/enrollments/exchange');
  }

  Duration _remainingTimeout(Stopwatch stopwatch) {
    final Duration remaining = _requestTimeout - stopwatch.elapsed;
    if (remaining.inMicroseconds <= 0) {
      throw const DeploymentEnrollmentException('enrollment_unavailable');
    }
    return remaining;
  }

  Future<List<int>> _readBody(
    http.StreamedResponse response,
    Stopwatch stopwatch,
  ) async {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    var size = 0;
    final StreamIterator<List<int>> iterator = StreamIterator<List<int>>(
      response.stream,
    );
    try {
      while (await iterator.moveNext().timeout(_remainingTimeout(stopwatch))) {
        final List<int> chunk = iterator.current;
        size += chunk.length;
        if (size > _maxResponseBytes) {
          throw const DeploymentEnrollmentException(
            'invalid_enrollment_response',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } on TimeoutException {
      throw const DeploymentEnrollmentException('enrollment_unavailable');
    } on DeploymentEnrollmentException {
      rethrow;
    } catch (_) {
      throw const DeploymentEnrollmentException('enrollment_unavailable');
    } finally {
      try {
        await iterator.cancel();
      } catch (_) {}
    }
  }

  static String _parseDeploymentId(List<int> body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } catch (_) {
      throw const DeploymentEnrollmentException('invalid_enrollment_response');
    }
    if (decoded is! Map ||
        decoded.length != 1 ||
        !decoded.containsKey('deployment_id') ||
        decoded['deployment_id'] is! String) {
      throw const DeploymentEnrollmentException('invalid_enrollment_response');
    }
    try {
      return DeploymentProfileContract.requiredUuid(
        decoded['deployment_id'],
        'deployment_id',
      );
    } on DeploymentProfileFormatException {
      throw const DeploymentEnrollmentException('invalid_enrollment_response');
    }
  }

  static void _requireSuccess(int statusCode) {
    switch (statusCode) {
      case 200:
        return;
      case 301:
      case 302:
      case 303:
      case 307:
      case 308:
        throw const DeploymentEnrollmentException(
          'enrollment_redirect_rejected',
        );
      case 400:
      case 401:
      case 403:
      case 404:
        throw const DeploymentEnrollmentException('enrollment_code_rejected');
      case 409:
      case 410:
        throw const DeploymentEnrollmentException('enrollment_code_expired');
      case 429:
        throw const DeploymentEnrollmentException('enrollment_rate_limited');
      default:
        if (statusCode >= 500 && statusCode <= 599) {
          throw const DeploymentEnrollmentException('enrollment_unavailable');
        }
        throw const DeploymentEnrollmentException('enrollment_request_failed');
    }
  }

  static void _requireJsonContentType(String? value) {
    final String mediaType = value?.split(';').first.trim().toLowerCase() ?? '';
    if (mediaType != 'application/json') {
      throw const DeploymentEnrollmentException('invalid_enrollment_response');
    }
  }

  static Uri _parseRegistryUrl(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      throw const DeploymentEnrollmentException('invalid_registry_url');
    }
    return _parseRegistryBaseUri(uri, rawValue: value);
  }

  static Uri _parseRegistryBaseUri(Uri uri, {String? rawValue}) {
    if (!uri.isAbsolute ||
        !uri.hasAuthority ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const DeploymentEnrollmentException('invalid_registry_url');
    }
    final String value = rawValue ?? uri.toString();
    final bool hasOneTrailingSlash =
        uri.path.endsWith('/') && !uri.path.endsWith('//');
    if (value != uri.toString() ||
        !value.startsWith('https://') ||
        uri.host != uri.host.toLowerCase() ||
        !_asciiHost.hasMatch(uri.host) ||
        uri.path.contains('//') ||
        uri.pathSegments.any(
          (String segment) => segment == '.' || segment == '..',
        ) ||
        (uri.hasPort && uri.port == 443)) {
      throw const DeploymentEnrollmentException('invalid_registry_url');
    }
    if (!hasOneTrailingSlash) return uri;
    return uri.replace(path: uri.path.substring(0, uri.path.length - 1));
  }
}

final RegExp _asciiHost = RegExp(r'^[a-z0-9.:-]+$');
